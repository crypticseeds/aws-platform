# Runbook: bootstrap the Terraform state bucket

Creates the S3 bucket that holds Terraform state for every project in the account. Run once per account. The bucket is never destroyed (`prevent_destroy = true`).

## One bucket, one state file per project

Every project (this repo and any future one, in any repo) stores state in this bucket under its own key, so projects never share a state file or a lock:

```
<project>/<environment>/terraform.tfstate     e.g. aws-platform/dev/terraform.tfstate
bootstrap/terraform.tfstate                   this root's own state
```

A project's backend block:

```hcl
terraform {
  backend "s3" {
    bucket       = "<state bucket name>"
    key          = "<project>/<environment>/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }
}
```

The bucket is tagged `Project=aws-platform` (the project that created it) and `Scope=shared` (used by every project).

## Why this is a two-step process

Terraform needs somewhere to keep its state before it can create anything, but the place we want to keep it (S3) does not exist yet. So the `bootstrap/` root is applied once with **local** state, and then its own state is moved into the bucket it just created.

Locking uses S3-native lock files (`use_lockfile = true`, a `.tflock` object next to the state). There is no DynamoDB table: HashiCorp has deprecated DynamoDB-based locking for the S3 backend. See ADR 0005 when it lands.

## What gets created

| Resource | Setting |
|---|---|
| S3 bucket `aws-platform-tfstate-<suffix>` | The name contains `tfstate`, so the agent's read deny on state objects applies. AWS generates the suffix, so no account ID appears in the name. |
| Versioning | Enabled. Every state write is kept, so a bad apply can be rolled back. |
| Lifecycle | Old versions deleted after 30 days: a month to notice and roll back a bad apply. State files are small (under 1 MB), so the cost is effectively zero. Incomplete uploads aborted after 7 days. |
| Encryption | SSE-S3 (AES256). |
| Public access | All four Block Public Access flags on. Object ownership `BucketOwnerEnforced` (ACLs off). |
| Bucket policy | Denies any request not made over TLS. |

No secrets are involved, so `doppler run --` is not needed here.

## Step 1: apply with local state (owner)

`bootstrap/backend.tf` is committed and points at the bucket this repo already created. In a **fresh account** that bucket doesn't exist yet, so `terraform init` would fail. Move the backend file aside for the first apply, so Terraform uses local state. (Files that don't end in `.tf` are ignored by Terraform.)

```
aws sso login --profile platform-admin        # shortcut: aws-admin-login
export AWS_PROFILE=platform-admin
aws sts get-caller-identity                   # shortcut: aws-admin-identity

cd bootstrap
mv backend.tf backend.tf.off                  # fresh account only
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output state_bucket_name
```

Check before applying: the plan should show **7 to add, 0 to change, 0 to destroy**, and the role in `get-caller-identity` should be `AWSReservedSSO_PlatformAdmin_...`.

## Step 2: move bootstrap state into the bucket (owner)

Put the new bucket name (from `terraform output state_bucket_name`) into **both** backend files, then move the bootstrap one back:

- `bootstrap/backend.tf.off`: `bucket = "<new bucket name>"`, then `mv backend.tf.off backend.tf`
- `envs/dev/backend.tf`: `bucket = "<new bucket name>"` (and any other root that uses the bucket)

Then, still in `bootstrap/`:

```
terraform init -migrate-state
```

Answer `yes` when asked to copy the existing state. Then confirm:

```
terraform state list
terraform plan
```

`terraform plan` must print `No changes.` From now on Terraform reads and writes only the copy in S3. The local `terraform.tfstate` (the pre-migration copy) and `terraform.tfstate.backup` (the version before that) are stale. Deleting them changes nothing in AWS or in the S3 state, but leaving them around invites mistakes and keeps copies of possibly sensitive values on disk. They are git-ignored. Still in `bootstrap/`, the owner deletes them (`-f`: no error if one is already gone):

```
rm -f terraform.tfstate terraform.tfstate.backup
```

Finish the session:

```
unset AWS_PROFILE
aws sso logout
aws sso login --profile agent-readonly --no-browser
```

`aws sso logout` clears every SSO session, the agent's included, even when given `--profile` (tested 2026-10-03). That's why the last line logs the agent back in if work continues.

Shortcut (owner's dotfiles, `zsh/.config/zsh/aliases.zsh`): `aws-admin-logout` logs out the admin only. It removes just the `seeds-admin` token and derived role credentials, then unsets `AWS_PROFILE`, so the agent stays logged in. Either way, admin role credentials already issued expire on their own within the permission set's 2-hour session duration.

Shortcuts used in this runbook:

| Shortcut | Standard command |
|---|---|
| `aws-admin-login` | `aws sso login --profile platform-admin --color on` |
| `aws-agent-login` | `aws sso login --profile agent-readonly --no-browser --color on` |
| `aws-admin-identity` | `aws sts get-caller-identity --profile platform-admin` |
| `aws-agent-identity` | `aws sts get-caller-identity --profile agent-readonly` |
| `aws-admin-logout` | removes only the admin SSO token (see above) |

## Verification (agent, read-only MCP)

- `GetBucketVersioning` returns `Enabled`.
- `GetBucketEncryption` returns `AES256`.
- `GetPublicAccessBlock` returns all four flags `true`.
- `GetBucketPolicy` contains the `aws:SecureTransport = false` deny.
- `GetObject` on the state key is **denied** for the agent (explicit deny in `policies/agent-readonly-inline.json`).
- While a `terraform plan` is running, a `.tflock` object exists next to the state key.

## Recovery

- **Bad state write:** versioning keeps the previous object. List versions of the state key, then restore the previous one by copying it over the current version.
- **Stale lock after a crash:** `terraform force-unlock <LOCK_ID>`, using the ID printed in the lock error. Only do this when certain no other run is active.
- **Bucket deleted by mistake:** not possible while `prevent_destroy` is set and the bucket holds objects. If it happens anyway, re-run step 1, then `terraform import` each root's resources, or rebuild `envs/dev` from scratch (it is disposable by design).

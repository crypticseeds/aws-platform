# Runbook: apply the account root (GitHub OIDC and the CI plan role)

Creates the account-wide resources that must survive `envs/dev` destroys ([ADR 0010](../decisions/0010-multi-project-state-layout.md)): the GitHub Actions OIDC provider and the plan-only CI role ([ADR 0007](../decisions/0007-plan-only-ci.md)). Run once per account, and again whenever `account/` changes.

State lives in the shared bucket under its own key:

```
aws-platform/account/terraform.tfstate
```

## What gets created

| Resource | Setting |
|---|---|
| IAM OIDC provider `token.actions.githubusercontent.com` | Client ID `sts.amazonaws.com`. No thumbprint: AWS checks GitHub's certificate against its own trusted CAs. One per account, shared by every project's CI role. |
| IAM role `aws-platform-ci-plan` | Assumable only through that provider when `aud = sts.amazonaws.com` and `sub = repo:crypticseeds/aws-platform:pull_request` (both `StringEquals`). Pushes to `main`, other branches, tags and other repos cannot assume it. Maximum session 1 hour. |
| Managed policy `ReadOnlyAccess` | Attached to the role. |
| Inline policy `terraform-state` | `s3:ListBucket` on the state bucket, `s3:GetObject` on its objects, `s3:PutObject` and `s3:DeleteObject` only on `*.tflock` keys (the S3-native lock, [ADR 0005](../decisions/0005-s3-native-state-locking.md)). |

Unlike the agent, **this role can read state**. That is intended: a plan has to read state (ADR 0007). The `sub` condition and the workflow's permissions are the guard.

No secrets are involved, so `doppler run --` is not needed here.

## Apply (owner)

The state bucket must already exist ([bootstrap.md](bootstrap.md)).

```
aws sso login --profile platform-admin        # shortcut: aws-admin-login
export AWS_PROFILE=platform-admin
aws sts get-caller-identity                   # shortcut: aws-admin-identity

cd account
terraform init
terraform plan -out=account.tfplan
terraform apply account.tfplan
terraform output ci_plan_role_arn
terraform plan
```

Check before applying: the plan should show **4 to add, 0 to change, 0 to destroy**, and the role in `get-caller-identity` should be `AWSReservedSSO_PlatformAdmin_...`.

The second `terraform plan` must print `No changes.`

`ci_plan_role_arn` is the value the plan workflow needs as a repository variable (DEV-135).

Finish the session as in [bootstrap.md](bootstrap.md) (`unset AWS_PROFILE`, then log out the admin).

## Verification (agent, read-only MCP)

- `GetRole` for `aws-platform-ci-plan`: the trust policy has exactly the `aud` and `sub` conditions above, and `MaxSessionDuration` is `3600`.
- `ListAttachedRolePolicies` returns only `ReadOnlyAccess`. `ListRolePolicies` returns only `terraform-state`, and `GetRolePolicy` matches the table above.
- IAM Access Analyzer (external access): the only new finding for the role is the GitHub OIDC federation, which the owner archives with a reason.
- `SimulatePrincipalPolicy` for the role: denied for `ec2:RunInstances`, `iam:CreateRole` and `s3:PutObject` on a non-lock key; allowed for `ec2:DescribeVpcs`, `s3:GetObject` on a state key and `s3:PutObject` on a `.tflock` key.

## Recovery

- **Role or trust changed by hand:** the next `terraform plan` shows the drift. Apply to put it back.
- **OIDC provider deleted:** every project's CI role stops working. Re-apply this root. The provider ARN is derived from the URL, so the roles' trust policies stay valid.

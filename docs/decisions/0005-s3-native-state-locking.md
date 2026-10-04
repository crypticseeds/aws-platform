# 0005. S3-native state locking (`use_lockfile`) instead of DynamoDB

- Status: accepted
- Date: 2026-10-03

## Context

Terraform state must be locked while a plan or apply runs, so two runs cannot change the same state at once.

**How DynamoDB locking worked.** The S3 backend took the name of a DynamoDB table (`dynamodb_table`) whose partition key was `LockID`. To take the lock, Terraform made a conditional write of an item for the state path, which failed if the item already existed. It deleted the item when the run finished. The same table also held a digest of the state file, so Terraform could detect a stale read. That mattered because S3 did not always return the newest version of an object straight after a write. The cost was a second service to create, secure and pay for in every account.

**Why it was retired.** S3 has since gained strong read-after-write consistency and conditional writes (create an object only if it does not exist). With those, S3 can do the atomic "create the lock if nobody holds it" step itself. Terraform 1.10 added `use_lockfile = true`, which writes a `<key>.tflock` object next to the state. HashiCorp's S3 backend documentation now says DynamoDB-based locking "is deprecated and will be removed in a future minor version".

## Decision

Every backend in this repo uses `use_lockfile = true` and no DynamoDB table (`bootstrap/backend.tf`, `envs/dev/backend.tf`). Terraform is pinned to `~> 1.14`.

The state bucket name must contain `tfstate`. `bootstrap/variables.tf` enforces this with a validation, because the agent's read deny targets `arn:aws:s3:::*tfstate*/*` ([0002](0002-identity-center-and-read-only-agent.md)).

## Consequences

- One less resource per account, and nothing extra to secure or pay for.
- Locking works: the agent saw `aws-platform/dev/terraform.tfstate.tflock` in the bucket during the first `envs/dev` apply (journal 03).
- Anyone running a plan or apply needs `s3:PutObject` and `s3:DeleteObject` on the `.tflock` key as well as read on the state. The CI plan role has to allow that, or run `plan -lock=false` (DEV-133).
- Renaming the bucket to something without `tfstate` would silently remove the agent's state deny. The validation makes that a plan error instead.
- Managed platforms (HCP Terraform, Spacelift, Atlantis) store state and handle locking themselves, so this choice only matters for a self-managed S3 backend.

## Alternatives

- **DynamoDB lock table.** Deprecated, and an extra resource. Rejected.
- **No locking.** Only one person applies today, but CI plans will run alongside local work. Rejected.
- **A managed platform (HCP Terraform and similar).** Removes backend management entirely, but adds an external service and hides the mechanics this project is meant to show.

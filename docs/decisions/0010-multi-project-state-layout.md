# 0010. Multi-project state layout: one account-wide bucket, one key per project

- Status: accepted
- Date: 2026-10-04

## Context

This account will host more projects than `aws-platform`. Each needs remote state that is isolated from the others, and a destroy in one must never touch another. Some resources can exist only once per account and are shared by every project.

## Decision

- **One state bucket for the account**, created by `bootstrap/` with `bucket_prefix = "aws-platform-tfstate-"`. AWS appends a unique suffix, so no account ID appears in the name. The bucket is tagged `Scope=shared` and has `prevent_destroy`.
- **One key per project, environment and layer:**

  ```
  bootstrap/terraform.tfstate                                     the bucket's own state
  aws-platform/dev/terraform.tfstate                              shared platform (envs/dev)
  aws-platform/dev/apps/concurrent-job-queue/terraform.tfstate    app-owned resources (P2)
  <next-project>/<env>/terraform.tfstate                          a future project
  ```

- **Old state versions kept for 30 days** (`noncurrent_version_retention_days = 30`, validated to be at least 7), with versioning on, SSE-S3, Block Public Access, TLS-only access and S3-native locks ([0005](0005-s3-native-state-locking.md)).
- **Account-wide singletons live in a permanent root**, not in `envs/dev`. The main one is the GitHub OIDC provider. IAM allows only one OIDC provider per issuer URL in an account, so every project's CI role must share the `token.actions.githubusercontent.com` provider. If `envs/dev` created it, destroying dev would break CI for every project (DEV-133 recommends an `account/` root).

## Consequences

- A future project only needs a backend block with its own key. Each key has its own `.tflock`, so projects never block or overwrite each other.
- All projects share one bucket policy and one encryption setting. A project that needs different access rules would need its own bucket.
- The agent's `*tfstate*` read deny covers every project's state at once.
- **Retention:** 7 days is the floor, so a bad apply can still be rolled back after a few days away. 30 days gives room to notice a bad state across several destroy and recreate cycles. State files are small (the bootstrap state is about 15 KB), so the storage cost of keeping versions is negligible either way. 90 days would also be cheap. It was not chosen because a month already covers the realistic gap between sessions, and the variable makes it easy to raise.
- The bucket is the one resource that must never be destroyed. `prevent_destroy` and the `bootstrap/` runbook protect it.

## Alternatives

- **A bucket per project.** Stronger isolation, but more to bootstrap and secure each time. Rejected while one owner runs everything.
- **Workspaces in one key.** Hides which state is which, and shares one backend config across very different lifecycles. Rejected.
- **The GitHub OIDC provider in `envs/dev`.** Destroyed with the environment and impossible to share. Rejected.

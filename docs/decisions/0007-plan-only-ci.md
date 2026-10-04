# 0007. CI runs `terraform plan` only, through an OIDC role; no apply from CI

- Status: accepted (not yet implemented: DEV-133, DEV-135)
- Date: 2026-10-03

## Context

Pull requests that change Terraform should show a plan before review. Running a plan in GitHub Actions needs AWS credentials. Long-lived access keys stored as GitHub secrets are exactly what [0002](0002-identity-center-and-read-only-agent.md) rules out.

An apply from CI would need a role that can create and destroy anything in the account, assumable by a workflow in a public repo.

## Decision

- **CI only ever runs `terraform plan`** (README, "How to run"). Every apply and destroy is run by the owner, locally, with short-lived `PlatformAdmin` credentials.
- GitHub Actions authenticates through **OIDC**: an IAM OIDC provider for `token.actions.githubusercontent.com` and a role `aws-platform-ci-plan`, assumable only when `aud = sts.amazonaws.com` and `sub` matches this repo's pull requests (DEV-133).
- The role gets `ReadOnlyAccess` plus exactly what a plan needs on the state bucket: read the state, and write or delete only the `.tflock` object ([0005](0005-s3-native-state-locking.md)). Maximum session is one hour.

## Consequences

- No AWS secret stored in GitHub. Tokens are minted per run and expire.
- A compromised workflow can read the account but cannot change it.
- **The CI role can read state**, which the agent cannot. That is intended: a plan has to read state. It means state contents are reachable from this repo's pull request workflows, so the `sub` condition and workflow permissions are the guard.
- Applies are manual and depend on the owner being available. Drift is caught by the next plan, not fixed automatically.
- The OIDC provider is account-wide and survives `envs/dev` destroys, so it belongs in a permanent root ([0010](0010-multi-project-state-layout.md)).

## Alternatives

- **Apply from CI on merge (GitOps for Terraform).** The norm in larger teams with protected environments and approvals. Rejected here: it needs an admin-capable role trusted by a public repo's workflows.
- **Access keys in GitHub secrets.** Long-lived and unrotated. Rejected.
- **Plan with `-lock=false` and no write permission at all.** Simpler IAM, but a plan could read state mid-apply. Kept open as an option in DEV-133.

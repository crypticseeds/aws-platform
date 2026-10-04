# 0001. One AWS account, the Organization management account

- Status: accepted
- Date: 2026-10-02

## Context

The project needs somewhere to build. The existing account (`crypticseeds`) is already the management account of an AWS Organization, which was found when Identity Center was set up (journal 01, step 2). The SCP policy type is disabled and no member accounts exist.

The project is a time-boxed portfolio with many short experiments. Everything in `envs/dev` is created and destroyed in a single session, so most of the cost and risk sits in the infrastructure, not the account.

## Decision

Build everything in the single management account. Create no member accounts for now.

## Consequences

- Nothing extra to set up or track: one account, one bill, one trail (`account-trail`, not an organization trail, see journal 02).
- **No SCPs apply.** Service control policies never restrict the management account, even when enabled. That leaves IAM as the only guardrail: the owner's `PlatformAdmin` role is full admin, and the agent's limits come only from its own permission set ([0002](0002-identity-center-and-read-only-agent.md)).
- Organization-level options (organization trail, organization zone of trust in Access Analyzer, organization-level S3 Block Public Access) are left off because they add setup for no extra coverage in one account.
- One OIDC provider per issuer per account means the GitHub provider is shared by every project here ([0010](0010-multi-project-state-layout.md)).
- Moving to a member account later means re-pointing the state bucket, the Identity Center assignments and the CI role. Nothing in the code hard-codes the account ID, so the Terraform itself moves unchanged.

## Alternatives

- **A dedicated member account (`aws-platform-dev`) under the Organization.** This is what a company would do: per-environment accounts from account vending (Control Tower Account Factory or Terraform), with SCP guardrails such as a region lock. Rejected for now because of limited time and the extra moving parts. In a job, accounts are long-lived and the infrastructure inside them is what gets created and destroyed, and that is the part this project practises.

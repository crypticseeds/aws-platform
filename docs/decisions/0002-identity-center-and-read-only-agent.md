# 0002. Identity Center SSO, separate owner and agent identities, read-only agent through MCP

- Status: accepted
- Date: 2026-10-02

## Context

Two actors use the account: the owner, who applies and destroys infrastructure, and an AI coding agent, which reads the account to plan, review and verify. An agent chooses its API calls at runtime and can be misled by prompt injection or its own wrong reasoning, so its permissions have to be sized by the damage that is acceptable, not by what it is meant to do (journal 01).

An Identity Center session token can fetch credentials for **any** permission set its user holds. If one user held both admin and read-only, a token created for the agent could also fetch admin.

## Decision

- No long-lived access keys. Both actors get short-lived credentials from IAM Identity Center (eu-west-2) with MFA on every sign-in.
- The owner signs in as `seeds-sso` and holds `PlatformAdmin` (`AdministratorAccess`, 2-hour sessions), used only for apply and destroy.
- The agent has its own user, `seeds-agent`, which can only hold `AgentReadOnly`: AWS `ReadOnlyAccess`, plus `AmazonEKSMCPReadOnlyAccess` for the EKS MCP Server, plus a targeted inline deny ([`policies/agent-readonly-inline.json`](../../policies/agent-readonly-inline.json)) on:
  - `secretsmanager:GetSecretValue` and `kms:Decrypt` (which also covers SSM SecureString values);
  - RDS log downloads, which can capture credentials;
  - `s3:GetObject` and `s3:GetObjectVersion` on any bucket whose name contains `tfstate`.
- The agent reaches AWS only through the managed AWS MCP Server and EKS MCP Server, pinned to the `agent-readonly` profile. Its shell sandbox blocks the SSO token cache, so it cannot use the AWS CLI directly.

## Consequences

- The agent's login cannot become admin, whatever the agent does with it.
- IAM is the real control. The MCP proxy, the plugin hook and the sandbox are extra layers, not the boundary.
- MCP calls are recorded in CloudTrail with `invokedBy: aws-mcp.amazonaws.com`, so the agent's activity can be filtered out from the owner's (journals 01 and 02).
- **The state bucket name must contain `tfstate`**, or the state deny stops applying. This is enforced by a variable validation in `bootstrap/` ([0005](0005-s3-native-state-locking.md)).
- The owner and the agent run as the same OS user, so the guard is against accidents, not a determined local attacker. The owner logs in as admin only to apply or destroy.
- Kubernetes Secrets are out of IAM's reach. The agent's cluster access needs RBAC with no Secret reads (DEV-136, not yet applied).
- Not yet proven: a write attempt by `AgentReadOnly` being refused in the console (DEV-129). The `*tfstate*` deny has been proven (journal 03).

## Alternatives

- **IAM user access keys stored in Doppler.** Still long-lived keys. Rejected.
- **A second permission set on the owner's user.** The shared SSO token could mint admin. Rejected.
- **Broad denies on all data-plane reads** (all S3 objects, SSM parameters, DynamoDB items, Lambda). This was the first draft. It blocked harmless reads such as public EKS AMI parameters and protected nothing extra, so each deny was kept only if the read actually returns a secret.
- **The MCP proxy's `--read-only` flag on the AWS MCP Server.** It hides `run_script`, the only tool that can read the account, so IAM is used as the control instead. The EKS MCP Server does run with `--read-only`.

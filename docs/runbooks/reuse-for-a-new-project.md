# Runbook: start a new project from this one

One page, links not copies. Each step says what to do, the command or file, and which runbook has the detail. The order matters: part 1 happens once per AWS account, part 2 once per project, part 3 every working session.

Status: written from the setup of `aws-platform` (journal [03](../journal/03-terraform-foundation.md)). The second-project path has **not been run yet**, so the first real reuse should correct this page.

## Part 1: once per AWS account

Skip all of this when the account already has it (it does, for `aws-platform`). A second project in the same account starts at part 2.

| # | Step | Where | Detail |
|---|---|---|---|
| 1 | Secure the account: root, MFA, SSO, no long-lived keys | AWS console | [journal 01](../journal/01-secure-aws-access-for-ai-agents.md), [journal 02](../journal/02-account-baseline.md) |
| 2 | Add the read-only agent role (permission set `AgentReadOnly`, explicit deny on reading `*tfstate*` buckets) and the `agent-readonly` SSO profile | Identity Center | [ADR 0002](../decisions/0002-identity-center-and-read-only-agent.md), journal 03 step 2 |
| 3 | Create the state bucket, then move its state into itself | `bootstrap/` | [bootstrap.md](bootstrap.md) |
| 4 | Create the GitHub OIDC provider and the plan-only CI role | `account/` | [account.md](account.md), [ADR 0007](../decisions/0007-plan-only-ci.md), [ADR 0010](../decisions/0010-multi-project-state-layout.md) |
| 5 | Baseline items: CloudTrail, Access Analyzer, console budgets | `account/baseline-*.tf` (imports) | journal 03 step 21 |
| 6 | Activate the `Project` cost allocation tag in Billing (one switch, account-wide, never in a destroyable root) | Billing console | journal 03 step 22 |

Rules for this part: the OIDC provider exists once per account, so a new project adds its own role, not a second provider ([ADR 0010](../decisions/0010-multi-project-state-layout.md)). Never destroy `bootstrap/` or `account/` ([teardown.md](teardown.md), "Never destroy").

## Part 2: once per project

| # | Step | Where | Detail |
|---|---|---|---|
| 1 | Create the repo from this layout (`bootstrap/` and `account/` stay in the account's repo; copy `envs/`, `modules/`, `charts/`, `argocd/`, `platform/`, `policies/`, `docs/`, `.pre-commit-config.yaml`, `.tflint.hcl`, `.yamllint.yaml`, `.gitignore`) | new repo | [README](../../README.md) |
| 2 | Copy the two workflows and fix the roots they plan | `.github/workflows/checks.yml`, `terraform-plan.yml` | [ci.md](ci.md) |
| 3 | Create `envs/<name>/` with its own state key `<project>/<env>/terraform.tfstate`, pointing at the shared bucket | `envs/<name>/backend.tf` | [ADR 0010](../decisions/0010-multi-project-state-layout.md), [ADR 0005](../decisions/0005-s3-native-state-locking.md) |
| 4 | Set the provider `default_tags`: `Project=<name>`, `Application`, `Environment`, `ManagedBy`, `Repository` | `envs/<name>/providers.tf` | [ADR 0008](../decisions/0008-tagging-and-layering.md) |
| 5 | Add the project's CI role (trusts only this repo's immutable OIDC subject: `<owner>@<owner-id>/<repo>@<repo-id>`) and apply it | account-level root | [account.md](account.md) |
| 6 | Create the Doppler project and config for the project's secrets | Doppler | `secret-hygiene` rules; never print values |
| 7 | Pick the Docker Hub namespace and set the image-build variable and secrets in each app repo | Docker Hub, app repos | [ADR 0006](../decisions/0006-docker-hub-not-ecr.md), journal 03 step 17 |
| 8 | Point the Argo root and the AppProject at the new repo and namespaces | `argocd/root.yaml`, `argocd/apps/project-*.yaml` | [deploy.md](deploy.md) section 4, [ADR 0011](../decisions/0011-argocd-install-by-helm.md) |
| 9 | Set the repository secrets, in exactly these formats | GitHub repo settings, set from a terminal | below |
| 10 | Add the project budget (`budget.tf`) and set its recipients | `envs/<name>/budget.tf` | journal 03 step 22 |

### Repository secrets and their formats

Set them from a terminal, never a web form (curly quotes break the value). A list variable needs a Terraform list literal:

```
printf '%s' 'arn:aws:iam::<account-id>:role/<project>-ci-plan' | gh secret set AWS_CI_PLAN_ROLE_ARN
printf '%s' '["x.x.x.x/32"]'                                    | gh secret set TF_VAR_endpoint_public_access_cidrs
printf '%s' '["you@example.com"]'                               | gh secret set TF_VAR_COST_ALERT_EMAILS
```

`AWS_CI_PLAN_ROLE_ARN` is a plain string. The other two are `list(string)`. Full rules and the exact error each mistake gives: [ci.md](ci.md), journal 03 step 20. The Snyk token is optional: [ci.md](ci.md).

### What to rename

Search for each old value, change it, and run the checks. The right-hand column says where the value lives today.

| Rename | Where it lives |
|---|---|
| Project name `aws-platform` (tags, cluster name, names) | `envs/*/providers.tf`, `envs/*/variables.tf` (`aws-platform-dev`), `bootstrap/*`, chart `Chart.yaml`, `argocd/**`, ALB group name |
| State key `aws-platform/dev/terraform.tfstate` | `envs/*/backend.tf` |
| State bucket name | stays: one bucket per account, reused (`backend.tf` in each root) |
| Repository URL | `argocd/root.yaml`, `argocd/apps/*.yaml`, `Repository` tag |
| Tag value `Project=aws-platform` | provider `default_tags`, `budget.tf` filter, cost allocation tag |
| OIDC subject (owner id, repo id) | `account/variables.tf` (see [account.md](account.md)) |
| CI role name `aws-platform-ci-plan` | `account/main.tf` |
| Namespaces `gateway`, `promscope`, `monitoring` | `argocd/apps/project-aws-platform.yaml`, app manifests |
| Image repositories and pinned tags | `argocd/apps/*.yaml` (Docker Hub namespace) |
| Doppler project and config | runbook commands in [deploy.md](deploy.md) |
| Endpoint allowlist and budget recipients | repository secrets, never the repo |

Do not rename and apply in one step. Run `terraform plan` and read it first.

## Part 3: every working session

| # | Step | Detail |
|---|---|---|
| 1 | Log in (`aws sso login` for the admin and the agent), check the identity | [deploy.md](deploy.md) sections 1 and 2 |
| 2 | Plan, apply, then a second plan that must print `No changes.` | [deploy.md](deploy.md) section 2 |
| 3 | Connect `kubectl`, install Argo CD and the root app, create the Doppler-piped secrets, let the add-ons and apps sync | [deploy.md](deploy.md) sections 3 to 6 |
| 4 | Verify read-only: Applications Synced and Healthy, one ALB, scrape targets up, health endpoint | [deploy.md](deploy.md) verification, [observability.md](observability.md) |
| 5 | Tear down in order: delete Ingresses, wait for the ALB to disappear, remove Argo CD and add-ons, plan then destroy | [teardown.md](teardown.md) sections 1 to 4 |
| 6 | Leak check: no cluster, VPC, NAT, EIP, instance, volume, ENI or load balancer left | [teardown.md](teardown.md) section 5 |
| 7 | Log out the admin only | [teardown.md](teardown.md) section 6 |

Check the budget and the leak check every time. The budget is late by hours and does not watch for leaks after a destroy.

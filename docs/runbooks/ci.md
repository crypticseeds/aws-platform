# Runbook: static-checks CI

`.github/workflows/checks.yml` runs on every pull request and on every push to `main`. It needs no AWS credentials. `terraform plan` is a separate workflow, see below.

## What runs

| Job | Tools | Result |
|---|---|---|
| `pre-commit` | `pre-commit run --all-files` with the repo's `.pre-commit-config.yaml`: merge-conflict, whitespace, JSON and private-key checks, gitleaks, terraform fmt/validate/tflint, trivy (HIGH, CRITICAL), yamllint | **Blocking** |
| `helm-charts` | `helm lint --strict`, then `helm template` piped into `kubeconform -strict` for every chart under `charts/`, with `values-dev.yaml` and `ci/test-values.yaml` | **Blocking** |
| `actionlint` | `actionlint` (and shellcheck on `run:` blocks) for every workflow | **Blocking** |
| `checkov` | checkov on `bootstrap/`, `envs/dev/`, `modules/` and the rendered charts | Advisory, SARIF to code scanning |
| `trivy-sarif` | `trivy config` (HIGH, CRITICAL), the same scan as the pre-commit hook | Report only, SARIF to code scanning. The gate is the pre-commit hook |
| `snyk-iac` | `snyk iac test --severity-threshold=high` on the Terraform and the rendered charts | Advisory, SARIF to code scanning. Skipped with a notice until the `SNYK_TOKEN` secret exists |

"Blocking" means branch protection on `main` requires the job (set by the owner). Advisory jobs never fail on findings, only when the tool itself breaks.

Every chart needs `values-dev.yaml` and `ci/test-values.yaml`; the chart loop fails if either is missing. `ci/test-values.yaml` supplies the values that are required at install time (image repository and tag) and is never deployed.

## Terraform plan on pull requests (DEV-135)

`.github/workflows/terraform-plan.yml` runs on pull requests that touch `**/*.tf`, `**/*.tfvars.example`, `**/.terraform.lock.hcl` or the workflow itself. For each root (`bootstrap`, `account`, `envs/dev`) it runs `terraform init`, `validate` and `plan` (with the normal S3 lock: the role may write and delete only `*.tflock` objects, ADR 0007), then posts the plan as one PR comment per root. A hidden marker (`<!-- terraform-plan:<root> -->`) lets later pushes edit the same comment instead of adding new ones; output over 60000 bytes is truncated with a link to the run. Formatting, tflint, trivy and checkov stay in `checks.yml`.

It authenticates to AWS through GitHub OIDC (`aws-actions/configure-aws-credentials`, region `eu-west-2`) and needs, set by the owner:

- repository **secret** `AWS_CI_PLAN_ROLE_ARN`: the read-only role the workflow assumes (a secret, so GitHub masks the account ID in it; no account ID lives in the repo)
- repository **secret** `TF_VAR_endpoint_public_access_cidrs`: the value for `envs/dev` (GitHub masks it in logs); the other roots do not use it. The value is read as a Terraform `list(string)`, so it must be a list literal with brackets and quotes, for example `["203.0.113.10/32"]`. A bare `203.0.113.10/32` fails the `envs/dev` plan with `Invalid number literal` and `No value for required variable`.
- repository **secret** `TF_VAR_COST_ALERT_EMAILS`: the recipients of the project cost alert in `envs/dev` (`budget.tf`). Same format rule as the CIDR secret: a Terraform list literal, for example `["you@example.com"]`. Until it exists the `envs/dev` plan job fails with `No value for required variable`; the other roots do not use it. The variable is `sensitive`, so the plan comment shows the addresses as `(sensitive value)`.

Until the role secret exists, or on a pull request from a fork (no OIDC token), each job prints a `::notice` and succeeds without planning.

The workflow never applies. Changes reach AWS only through an owner-run `terraform apply` after review, so a pull request, a fork or a compromised action can never change infrastructure: the role is read-only apart from the state lock file.

Because the repo is public, its Actions logs and PR comments are public too. The workflow masks the AWS account ID in logs (`mask-aws-account-id`) and replaces it with `<account-id>` in plan comments. `envs/dev`'s `endpoint_public_access_cidrs` is marked `sensitive`, so the owner's IP shows as `(sensitive value)` in plans.

## Exceptions

- trivy: inline `trivy:ignore:<rule>` comment with a reason, next to the code.
- checkov: inline `checkov:skip=<ID>:<reason>` comment, next to the code.

## Run the same checks locally

```
pre-commit run --all-files
.github/scripts/render-charts.sh rendered
kubeconform -strict -summary -kubernetes-version 1.36.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/4c8dc296d32b06d15ccde9668ff136c951f4d539/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  rendered/*.yaml
actionlint
```

`rendered/` is scratch output; delete it afterwards.

## Read results

```
gh pr checks <pr>
gh run view <run-id> --log-failed
gh api repos/crypticseeds/aws-platform/code-scanning/alerts
```

Job names start with the tool, so `--log-failed` shows which tool failed.

## Snyk token (owner)

Create a Snyk account, then add the API token as the repository secret `SNYK_TOKEN` (Settings, Secrets and variables, Actions). The workflow passes it to the Snyk CLI through the environment and never prints it.

## Updating pinned actions

Every `uses:` is pinned to a full commit SHA with the version in a trailing comment. To update one, look up the new tag's commit and replace both:

```
gh api repos/<owner>/<action>/git/ref/tags/<tag> --jq '.object.type + " " + .object.sha'
# If the type is "tag" (annotated), dereference it:
gh api repos/<owner>/<action>/git/tags/<sha> --jq .object.sha
```

Tool versions (terraform, tflint, trivy, helm, kubeconform, actionlint, pre-commit, checkov, Snyk CLI) are in the workflow's top-level `env:` and match the owner's local installs.

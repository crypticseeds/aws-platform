# Runbook: static-checks CI

`.github/workflows/checks.yml` runs on every pull request and on every push to `main`. It needs no AWS credentials. `terraform plan` is a separate workflow (DEV-135).

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

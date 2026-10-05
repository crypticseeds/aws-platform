# aws-platform

Infrastructure and GitOps for deploying a small SRE portfolio to AWS EKS: an LLM inference gateway, a Prometheus MCP server (Promscope), a Go job queue, and an SLO benchmark. Each phase ends in an artefact with measured numbers, not just running code.

Region: `eu-west-2` (London). Status and acceptance criteria for every task live in the Linear project [aws-platform](https://linear.app/devopsfoundry/project/aws-platform-520feda43527).

## Phases

| Phase | Goal | Evidence it produces |
|---|---|---|
| P1 Foundation | Terraform from a clean account to EKS, Argo CD app-of-apps, gateway and Promscope behind an ALB, Prometheus and Grafana | `docs/architecture.md`, runbooks, `docs/cost.md`, a clean destroy |
| P2 Data layer | RDS PostgreSQL and ElastiCache Redis, job queue on managed services, an expand-and-contract migration under load | `docs/runbooks/migration.md` with recorded numbers |
| P3 Disaster recovery | Cross-region snapshot copy, restore drill, full rebuild drill | `docs/runbooks/disaster-recovery.md` with measured RTO and RPO |
| P4 Capacity and cost | SLO gate in CI, measured queue numbers, right-sizing, cost actuals | `docs/capacity.md`, updated `docs/cost.md` |

## Layout

```
bootstrap/        Terraform root for the remote state bucket (applied once, never destroyed)
envs/dev/         Terraform root for the dev environment (destroyed between sessions)
modules/          Reusable Terraform modules used by the roots
docs/decisions/   Architecture decision records
docs/runbooks/    Bootstrap, deploy, teardown and drill procedures
docs/journal/     Narrative write-up of each phase
policies/         IAM policy documents applied outside Terraform
```

## How to run

Every command that touches AWS is run by the owner, with short-lived Identity Center (SSO) credentials. CI never applies: it runs static checks on every pull request ([docs/runbooks/ci.md](docs/runbooks/ci.md)) and, against AWS, only `terraform plan`. Start with [docs/runbooks/bootstrap.md](docs/runbooks/bootstrap.md).

Local checks before every commit:

```
pre-commit install
pre-commit run --all-files
```

## Safety rules for this public repo

- No AWS account ID, secret, token or personal identifier in any file or commit. The account ID comes from `data.aws_caller_identity`.
- Real `*.tfvars` files are ignored. Only `*.tfvars.example` with placeholders is committed.
- Kubernetes Secrets are created from Doppler by the owner and referenced by name. Nothing secret lives in Helm values or manifests.
- Argo CD, Grafana and Prometheus are reached by port-forward only.
- Agents get read-only AWS and Kubernetes access through MCP. See [docs/journal/01-secure-aws-access-for-ai-agents.md](docs/journal/01-secure-aws-access-for-ai-agents.md).

## License

See [LICENSE](LICENSE).

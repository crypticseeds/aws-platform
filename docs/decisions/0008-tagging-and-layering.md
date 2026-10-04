# 0008. Tagging standard and infrastructure layers

- Status: accepted
- Date: 2026-10-04

## Context

The account will host more projects later. Each must be trackable on its own in Cost Explorer, even after it has been deleted. Within this project, shared platform cost (VPC, EKS, NAT) needs to be told apart from what each application adds (databases, caches, IAM roles).

## Decision

### Tags on every resource

| Tag | Example | Purpose |
|---|---|---|
| `Project` | `aws-platform` | The initiative. Stays visible in Cost Explorer after the project is gone. |
| `Application` | `platform`, `concurrent-job-queue` | Shared platform vs the workload a resource serves |
| `Environment` | `dev`, `shared` | |
| `ManagedBy` | `terraform` | Code vs clicked |
| `Repository` | `github.com/crypticseeds/aws-platform` | Where the code lives |

The state bucket also carries `Scope=shared` (used by every project) and `Root=bootstrap`. There is no `Owner` tag: in a single-owner account it adds nothing. In a team it would name the owning team.

Tags are set through provider `default_tags`, **and** passed into the EKS module (`envs/dev/providers.tf`), because `default_tags` never reaches resources AWS creates for you. The module puts them on the node launch template, so instances and volumes get them. Load balancers created by the AWS Load Balancer Controller need the controller's own `defaultTags` (DEV-142).

The five tags are to be activated as cost allocation tags in Billing. That is not done yet (DEV-126, deferred).

### Layers

```
bootstrap/            account-wide: state bucket (later: GitHub OIDC)   once per account
envs/<env>/           shared platform: VPC, EKS, add-ons               Application=platform
apps/<app>/<env>/     an app's own AWS resources, own state             Application=<app>
                      + Kubernetes manifests deployed by Argo CD
```

App roots find platform values (VPC, subnets, node security group) with tag-based data sources, not `terraform_remote_state`.

## Consequences

- Cost Explorer can group by project and by application once the tags are activated.
- **AWS tags cannot split a shared node's cost between the pods on it.** A node is one EC2 instance with one set of tags. EKS split cost allocation data, using pod requests and Kubernetes labels, can (planned for P4).
- Each layer has its own state and lock, so destroying an app cannot touch the platform, and destroying `envs/dev` cannot touch the bucket.
- Resources created by controllers must be tagged through controller config, or they show up untagged.

## Alternatives

- **`Owner` / `CostCenter` tags.** Useful in an organisation, noise here.
- **Each app's infrastructure in its own repo.** This is how larger teams split ownership: a platform team owns `envs/`, product teams own their `apps/` roots in their own repos and point them at the same state bucket with their own keys. Kept in one repo here for one place to review, but the layout transfers unchanged.
- **One state for everything.** Simpler at first, but a single lock and a single blast radius. Rejected.

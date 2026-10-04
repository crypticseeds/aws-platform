# 0011. Argo CD on EKS, installed by a one-time `helm install`

- Status: accepted
- Date: 2026-10-04

## Context

GitOps needs a controller in place before anything else can be deployed from git: Argo CD has to be installed by some other means first. The dev cluster is created and destroyed in every working session (`envs/dev`), so this bootstrap step runs on every rebuild.

Two choices had to be made: where Argo CD runs, and what installs it.

## Decision

- **Argo CD runs inside the EKS cluster**, in the `argocd` namespace. Running it on the owner's Pi 5 k3s as a hub (DEV-155) is a later step.
- **The owner installs it with a documented one-time `helm install`** of the official `argo-cd` chart, pinned to **10.9.6** (Argo CD v3.5.3), using `argocd/values.yaml` ([deploy runbook, step 4](../runbooks/deploy.md#4-install-argo-cd-and-the-root-app-owner)).
- The owner then applies `argocd/bootstrap-project.yaml` and `argocd/root.yaml`. From then on, everything comes from `argocd/apps/` in git: automated sync, prune and selfHeal.
- The server is `ClusterIP` only and reached by port-forward. Dex (SSO) is off. Slack notifications go to `#alerts` on failed syncs and Degraded health, with the token in a Secret created from Doppler.

## Consequences

- **Terraform stays AWS-only.** `envs/dev` needs no Helm or Kubernetes provider, and `terraform destroy` never has to reach into the cluster.
- **Teardown order matters.** Argo CD and the Load Balancer Controller create AWS resources outside Terraform (ALBs, target groups, security groups). Apps must be deleted, and those resources gone, before `terraform destroy`, or the VPC deletion fails on dependencies. The full order is in `teardown.md` (DEV-145).
- One manual step per rebuild: helm install, then two `kubectl apply`s. The P3 rebuild drill times it.
- Argo CD shares the two t3.medium nodes with the workloads, with explicit requests and limits.
- Argo CD is lost with every destroy, and rebuilt from the same pinned chart and values. Its state lives in git, so nothing is lost with it.

## Alternatives

- **Terraform `helm_release` in `envs/dev`.** One apply builds everything, but it needs the Helm and Kubernetes providers configured against a cluster created in the same root. On destroy, Terraform would remove Argo CD while ALBs it created still hold the VPC. Rejected.
- **Argo CD on the Pi 5 k3s as a hub (DEV-155).** It survives EKS rebuilds and keeps controllers off the nodes, but it needs a private network path to the EKS API (Tailscale) and a machine identity first. Kept for later.
- **Argo CD Autopilot or a bootstrap script.** More tooling for a single install command. Rejected.

# 0006. Docker Hub for application images, no ECR

- Status: accepted (not yet implemented: DEV-125, DEV-137, DEV-138)
- Date: 2026-10-03

## Context

The application images (the inference gateway and Promscope) are built in their own repos and pulled by the cluster. The deployment manifests and Helm values that name those images live in this public repo.

An ECR image URI contains the AWS account ID (`<account>.dkr.ecr.eu-west-2.amazonaws.com/<repo>`). This repo's safety rules forbid an account ID in any file or commit (README). Hiding it would need templating at deploy time.

## Decision

- Images are pushed to **Docker Hub** by a workflow in each app repo, tagged with the git SHA (plus `latest`). Manifests in this repo pin the SHA tag.
- CI logs in to Docker Hub with a token scoped to that one repository. The owner creates the token and stores it as a repo secret (DEV-137).
- No ECR repositories are created.

## Consequences

- No account ID in any manifest, so the files stay safe to publish as they are.
- Images live outside AWS: pulls go through the NAT gateway ([0004](0004-single-nat-gateway.md)), and Docker Hub's pull rate limits apply.
- If an image is private, the cluster needs an image pull secret. That secret is created from Doppler by the owner and referenced by name, never committed (README, journal 01).
- The node role already has `AmazonEC2ContainerRegistryReadOnly` (attached by the EKS module), which goes unused.
- The Docker Hub namespace is still an open owner input (DEV-125), so the image workflows are blocked until it is chosen.

## Alternatives

- **ECR.** Pulls authenticated by the node's IAM role with no pull secret, and traffic stays inside AWS. Rejected because the URI exposes the account ID in a public repo.
- **GitHub Container Registry.** Not evaluated in detail.

# 0009. EKS security choices: default encryption, Pod Identity, restricted public endpoint

- Status: accepted
- Date: 2026-10-04

## Context

The dev cluster is created and destroyed in every working session. Three security settings interact with that lifecycle: how Kubernetes API data is encrypted, how pods get AWS permissions, and how the owner reaches the API server.

## Decision

1. **AWS-owned default envelope encryption, no customer-managed key (CMK).** Since 2025, EKS envelope-encrypts all Kubernetes API data by default on 1.28+ with an AWS-owned key. `modules/cluster` sets `create_kms_key = false` and `encryption_config = null`.
2. **EKS Pod Identity, not IRSA.** `enable_irsa = false`, and the `eks-pod-identity-agent` add-on is installed before nodes join. Workload roles trust `pods.eks.amazonaws.com` and are linked to a namespace and service account through the EKS API.
3. **Public endpoint limited to the owner's IPs, private endpoint on.** `endpoint_public_access_cidrs` has no default, and its validation accepts only single IPv4 addresses (`/32`). That rejects `0.0.0.0/0`, and also wider ranges such as two `/1`s that would amount to the same thing. Nodes reach the API privately.

Alongside these: access entries only (`authentication_mode = "API"`), no implicit admin for whoever ran apply, and audit and authenticator control-plane logs with 7-day retention.

## Consequences

- **No CMK:** no $1/month per key, and no key left pending deletion (7-30 days) after every destroy. Without a CMK there is no customer key policy, no per-decrypt audit trail of our own, and no kill switch by disabling the key. **Production would use a CMK** with deletion protection and tight IAM on who can schedule deletion.
- **Pod Identity:** workload roles survive cluster rebuilds unchanged. With IRSA, every rebuild creates a new OIDC provider, and every role's trust policy would have to change. Pods pick up a new association only after a restart.
- **Public endpoint:** reachable from the owner's IP with no VPN cost. It breaks when the home IP changes. A private endpoint over Tailscale is planned with the Argo-on-Pi work (DEV-155).

### Accepted trivy findings

Each is accepted with an inline `trivy:ignore` comment next to the resource, giving the reason:

| Finding | Where | Why accepted |
|---|---|---|
| AWS-0039 secrets encryption not enabled | EKS (`modules/cluster`) | EKS encrypts all API data by default with an AWS-owned key. The check predates that. |
| AWS-0040 public cluster endpoint | EKS | Needed for the owner's kubectl, limited to `/32` owner IPs |
| AWS-0104 unrestricted egress | node security group | Nodes need outbound access through the NAT for image pulls and AWS APIs |
| AWS-0132 no customer-managed key | state bucket (`bootstrap/`) | SSE-S3 by design; the agent is denied reading state separately ([0005](0005-s3-native-state-locking.md)) |

## Alternatives

- **CMK for secrets encryption.** Right for production, wasteful and fragile for a cluster destroyed daily.
- **IRSA.** Still widely used, but it ties roles to one cluster's OIDC provider.
- **Private endpoint with VPN or SSM port forwarding now.** Client VPN costs an estimated $70+/month per AZ association. SSM needs an instance and a TLS server-name override. Deferred in favour of Tailscale (DEV-155).

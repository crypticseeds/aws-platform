# 0004. One NAT gateway with private node subnets

- Status: accepted
- Date: 2026-10-04

## Context

Worker nodes need outbound internet access for image pulls and AWS APIs. Nodes should not have public IPs. A NAT gateway gives private subnets outbound access only, since nothing can start a connection in through it. NAT gateways are charged per hour plus per GB processed, and the standard highly available layout uses one per AZ.

The dev environment runs only during working sessions and is destroyed at the end of each one.

## Decision

- Nodes run in private subnets with no public IPs (verified in journal 03).
- **One NAT gateway** in a single public subnet, shared by all three AZs (`single_nat_gateway = true` in `modules/network`).
- A free **S3 gateway endpoint** on the private route table, so S3 traffic (including image layers served from S3) skips the NAT and its data charges.

## Consequences

- Cost: one NAT gateway instead of three. The original planning estimate was **about $32/month plus data processing** for one NAT gateway. That is an estimate, not a measured figure. Because `envs/dev` is destroyed after every session, the real charge is per running hour. Actual spend will be recorded in `docs/cost.md` (DEV-146).
- **Not AZ-redundant.** If the NAT's AZ fails, nodes in the other two AZs lose outbound access. That is acceptable for a disposable dev cluster.
- Production would use one NAT gateway per AZ (`one_nat_gateway_per_az = true`), which also avoids cross-AZ data charges.

## Alternatives

- **One NAT gateway per AZ.** AZ-redundant, but about three times the NAT cost. Rejected for dev.
- **Public node subnets with public IPs and no NAT.** Cheapest, but every node gets an internet-facing address that has to be defended with security groups alone. Rejected.
- **VPC endpoints for every AWS service instead of NAT.** Interface endpoints are charged per AZ per hour each, and image pulls from Docker Hub still need internet access. Only the free S3 gateway endpoint was added.

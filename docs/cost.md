# Cost

An itemised **estimate** of what `envs/dev` costs while it runs in `eu-west-2` (London), and a placeholder for the measured numbers. Nothing has been applied yet, so **there are no actuals**. Architecture: [architecture.md](architecture.md).

## How the numbers were sourced

Unit prices were read on **2026-10-05** from the AWS Price List bulk files (the machine-readable source behind the AWS pricing pages), region `eu-west-2`, On-Demand, USD. The file's own publication date is given per row. The EKS rate was also confirmed on the AWS EKS pricing page the same day. Quantities (hours, nodes, volume size) come from this repo; anything else is labelled as an assumption.

Price List file pattern: `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<OfferCode>/current/eu-west-2/index.json`.

## Unit prices

| Item | Unit price | Source (read 2026-10-05) |
|---|---|---|
| EKS control plane, standard support | $0.10 per cluster-hour | https://aws.amazon.com/eks/pricing/ and https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEKS/current/eu-west-2/index.json (published 2026-09-28) |
| EC2 t3.medium, Linux, On-Demand | $0.0472 per instance-hour | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/eu-west-2/index.json (published 2026-09-25), usage type `EUW2-BoxUsage:t3.medium` |
| NAT gateway, hours | $0.05 per hour | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/eu-west-2/index.json (published 2026-09-25), `EUW2-NatGateway-Hours` |
| NAT gateway, data processed | $0.05 per GB | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/eu-west-2/index.json (published 2026-09-25), `EUW2-NatGateway-Bytes` |
| Public IPv4 address, in use | $0.005 per address-hour | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/eu-west-2/index.json (published 2026-09-17), `EUW2-PublicIPv4:InUseAddress` |
| Application Load Balancer, hours | $0.02646 per hour | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/eu-west-2/index.json (published 2026-09-11), `EUW2-LoadBalancerUsage` |
| ALB capacity unit (LCU) | $0.0084 per LCU-hour | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/eu-west-2/index.json (published 2026-09-11), `EUW2-LCUUsage` (Application) |
| EBS gp3 storage | $0.0928 per GB-month | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/eu-west-2/index.json (published 2026-09-25), `EUW2-EBS:VolumeUsage.gp3` |
| CloudWatch Logs, vended logs ingested (EKS control plane logs), first 10 TB | $0.5985 per GB | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudWatch/current/eu-west-2/index.json (published 2026-09-22), `EUW2-VendedLog-Bytes` |

Note on the last row: that EKS control plane logs are charged at the vended-logs rate is an inference from the usage types in the price list, not something this repo or documentation read here states directly.

## Quantities and assumptions

| Item | Quantity | Basis |
|---|---|---|
| EKS control plane | 1 cluster | `modules/cluster/main.tf`. Kubernetes 1.36 is in standard support (`envs/dev/variables.tf`), so no extended-support surcharge |
| Nodes | 2 x t3.medium | `modules/cluster/variables.tf`: min 2, desired 2, max 3. The estimate assumes 2 |
| Node volumes | 2 x 20 GiB gp3 | **Unknown from the repo**: no volume size is set. The EKS module documents a 20 GiB default for node disks. Confirm with `DescribeVolumes` after the first apply |
| NAT gateway | 1, plus its Elastic IP | `modules/network/main.tf`, [ADR 0004](decisions/0004-single-nat-gateway.md). A NAT gateway needs a public IPv4 address, billed at the in-use rate |
| ALB | 1 (one shared group), 3 public IPv4 addresses | Created by the Load Balancer Controller from the gateway Ingress, so it exists only once the gateway app is synced (planned). One address per AZ is **assumed** for a 3-AZ internet-facing ALB |
| LCUs | 1 | **Assumption**: near-zero dev traffic bills about one LCU-hour as a floor. Not measured |
| NAT data | 5 GB per session | **Assumption**: Docker Hub and chart-repo pulls (Argo CD, Prometheus stack, controller, app images) go through the NAT. Not measured. S3 traffic uses the free gateway endpoint |
| Control plane logs | 0.5 GB per 8-hour session | **Assumption** for audit and authenticator logs on a small cluster. Not measured, could be well off. Retention is 7 days, so storage (about $0.0315 per GB-month in this region) is negligible |
| Month | 730 hours | Convention used to turn monthly rates into hourly ones |

## Estimate

Running cost per hour, with the cluster and ALB up:

| Item | Calculation | $ per hour |
|---|---|---|
| EKS control plane | 1 x 0.10 | 0.1000 |
| t3.medium nodes | 2 x 0.0472 | 0.0944 |
| NAT gateway | 1 x 0.05 | 0.0500 |
| Public IPv4 (NAT 1, ALB 3) | 4 x 0.005 | 0.0200 |
| ALB | 1 x 0.02646 | 0.0265 |
| ALB LCU | 1 x 0.0084 | 0.0084 |
| EBS gp3 | 40 GiB x 0.0928 / 730 | 0.0051 |
| **Total, time-based** | | **0.3043** |

| Period | Time-based | Plus usage-based | Total |
|---|---|---|---|
| 1 hour | $0.30 | n/a | $0.30 |
| **8-hour session** | $2.43 | NAT data 5 GB $0.25, control plane logs 0.5 GB $0.30 | **about $2.98** |
| 24 hours | $7.30 | not scaled | about $7.30 plus data |
| Left running for a 730-hour month | $222 | | about $222 plus data |

Not itemised, judged small: data transfer out to the internet (not priced here), cross-AZ traffic, ALB data processing, the account-wide items that outlive `envs/dev` (state bucket, trail, budgets; see the account baseline journal), and the first 14-20 minutes of each session while EKS is being created, which bill but are not in the 8-hour figure. Docker Hub pulls cost nothing in AWS but are subject to Docker's rate limits ([ADR 0006](decisions/0006-docker-hub-not-ecr.md)).

If the gateway is not yet deployed, there is no ALB: remove the ALB, LCU and 3 IPv4 lines, about $0.0499 per hour, leaving about $0.2544 per hour (about $2.03 for 8 hours, before data).

## Destroy every session

Almost the whole bill is per running hour, and the largest items (EKS control plane, NAT gateway, ALB, nodes) have no idle mode. The control plane alone is $73 a month if left up. So the discipline is: apply at the start of a session, destroy at the end, in the order of the teardown runbook (apps and the Load Balancer Controller first, so the ALB and its security groups are gone before the VPC is deleted; [ADR 0011](decisions/0011-argocd-install-by-helm.md), DEV-145). A forgotten stack costs about $7.30 a day.

Safety nets: the account's billing budgets and the Cost Anomaly Detection monitor (daily summaries, alerts above $5) described in the account baseline journal.

## Where this differs from the earlier estimates

| Earlier figure | Where | Sourced figure | Why they differ |
|---|---|---|---|
| NAT gateway about $32/month | [ADR 0004](decisions/0004-single-nat-gateway.md), journal 03 | $36.50/month for the hourly charge alone (0.05 x 730), plus $3.65 for its public IPv4 address, plus $0.05 per GB | $32 is close to 730 x $0.045, which I believe is the US East (N. Virginia) rate. That is an inference: the us-east-1 price was not fetched. In `eu-west-2` the rate read today is $0.05 |
| About $6-7 a day while running | journal 03, [deploy runbook](runbooks/deploy.md) step 6, journal 02 ($5-7 for a forgotten stack) | $6.11 a day for EKS, 2 nodes, NAT and its IP, and disks (0.2544 x 24); $7.30 a day once the ALB, its 3 addresses and an LCU are added | The earlier range matches the stack without the ALB. With the ALB it sits at the top of the range, just above it |
| (not estimated before) | | Public IPv4 addresses $0.02 per hour, about $14.60 a month if left up | Easy to miss; it appears as its own line in the Price List |

## Actuals (placeholder)

**Not measured yet.** To be filled by the agent after the first EKS apply, from Cost Explorer `GetCostAndUsage` over the first 7 days, grouped by service and by the `Project=aws-platform` cost allocation tag (activating the tag is DEV-126; until it is active, group by service only). Record the date range, the sessions run, hours up per session, and compare each line with the estimate above.

| Line | Estimate per 8-hour session | Actual (7-day total) | Sessions | Actual per session | Difference |
|---|---|---|---|---|---|
| EKS control plane | $0.80 | _pending_ | _pending_ | _pending_ | _pending_ |
| EC2 nodes | $0.76 | _pending_ | _pending_ | _pending_ | _pending_ |
| NAT gateway (hours and data) | $0.40 plus $0.25 data | _pending_ | _pending_ | _pending_ | _pending_ |
| ALB and LCU | $0.28 | _pending_ | _pending_ | _pending_ | _pending_ |
| Public IPv4 | $0.16 | _pending_ | _pending_ | _pending_ | _pending_ |
| EBS | $0.04 | _pending_ | _pending_ | _pending_ | _pending_ |
| CloudWatch Logs | $0.30 | _pending_ | _pending_ | _pending_ | _pending_ |
| **Total** | **about $2.98** | _pending_ | _pending_ | _pending_ | _pending_ |

Also record while measuring: the real node volume size, the real ALB LCU and public IPv4 count, the control plane log volume per session, and NAT bytes per rebuild. Replace each assumption above with the measured value.

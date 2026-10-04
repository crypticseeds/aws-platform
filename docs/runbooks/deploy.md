# Runbook: deploy the dev environment

Creates the shared platform for dev (`envs/dev`): VPC, single NAT gateway, S3 gateway endpoint, EKS cluster and a managed node group. Later sections (Argo CD, add-ons, apps) are added as those issues land.

Prerequisite: the state bucket exists ([bootstrap.md](bootstrap.md)).

## 1. Allow your IP to reach the Kubernetes API

The cluster's API endpoint is public so the owner can run `kubectl`, but only from the CIDRs in `endpoint_public_access_cidrs`. The variable has no default on purpose, and `0.0.0.0/0` is rejected by validation. If it is not set, Terraform prompts for it.

```
cd envs/dev
curl -s https://checkip.amazonaws.com
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and put your IP with `/32` (exactly one address):

```hcl
endpoint_public_access_cidrs = ["<your-ip>/32"]
```

`terraform.tfvars` is git-ignored, so the IP never reaches the public repo.

If your home IP changes later, `kubectl` times out. Update `terraform.tfvars` and run plan/apply again (an in-place change, about a minute).

## 2. Plan and apply (owner)

```
aws sso login --profile platform-admin        # shortcut: aws-admin-login
export AWS_PROFILE=platform-admin
aws sts get-caller-identity                   # shortcut: aws-admin-identity

terraform init
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
terraform plan
```

Check the first plan before applying: only additions, **0 to change, 0 to destroy**, and exactly one `aws_nat_gateway`. The apply takes about 15-20 minutes, most of it the EKS control plane. The last `terraform plan` must print `No changes.`

Delete the saved plan afterwards. It is git-ignored, but plan files can contain sensitive values:

```
rm dev.tfplan
```

## 3. Connect kubectl (owner)

```
terraform output -raw configure_kubectl
```

Run the command it prints, then:

```
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Expect 2 nodes `Ready` (t3.medium, no external IP) and every kube-system pod `Running`.

## 4. End of session

The environment costs roughly $6-7 a day while it runs, so destroy it when you finish. Review the destroy plan first:

```
terraform plan -destroy
terraform destroy
```

Then log out the admin (see [bootstrap.md](bootstrap.md#step-2-move-bootstrap-state-into-the-bucket-owner) for the standard and shortcut commands).

The full teardown order, needed once Argo CD and the Load Balancer Controller create resources outside Terraform, is in `teardown.md` (DEV-145).

## Verification (agent, read-only MCP)

- `DescribeNatGateways`: exactly 1 available NAT in the VPC.
- `DescribeSubnets`: 3 private and 3 public subnets with the `kubernetes.io/role/*elb` tags.
- `DescribeVpcEndpoints`: the S3 gateway endpoint on the private route tables.
- `DescribeCluster`: version 1.36, `authenticationMode=API`, public endpoint limited to your CIDR, audit + authenticator logging.
- `ListAccessEntries`: only the PlatformAdmin role (plus the node role EKS adds itself).
- Resource Groups Tagging: every resource tagged `Project=aws-platform`, `Application=platform`.

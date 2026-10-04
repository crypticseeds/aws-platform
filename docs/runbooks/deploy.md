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

## 4. Install Argo CD and the root app (owner)

Argo CD is installed once per cluster with Helm, then manages everything else from git ([ADR 0011](../decisions/0011-argocd-install-by-helm.md)). Run from the repo root with `kubectl` pointed at the dev cluster.

**Before the first install:** create a Slack app with a bot token (`xoxb-...`, scope `chat:write`), invite it to `#alerts`, and store the token in Doppler as `SLACK_ARGOCD_BOT_TOKEN`.

1. Create the namespace and the Slack secret. The token goes from Doppler to `kubectl` through a pipe, so it never appears in your terminal, shell history or the process list. Run it from a directory whose `doppler setup` points at the config that holds the token (or add `-p <project> -c <config>`):

   ```
   kubectl create namespace argocd
   doppler run --only-secrets SLACK_ARGOCD_BOT_TOKEN -- sh -c 'printf %s "$SLACK_ARGOCD_BOT_TOKEN" | kubectl -n argocd create secret generic argocd-notifications-secret --from-file=slack-token=/dev/stdin'
   ```

2. Install the pinned chart:

   ```
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd --version 10.9.6 -n argocd -f argocd/values.yaml
   kubectl -n argocd get pods
   ```

   Expect every pod `Running` (no Dex pod: SSO is off).

3. Confirm nothing is exposed. Both must show no `LoadBalancer` or `NodePort` service and no Ingress:

   ```
   kubectl -n argocd get svc
   kubectl -n argocd get ingress
   ```

4. Log in. The initial admin password goes straight to your clipboard and is never printed (macOS shown; on Linux use `wl-copy` or `xclip -selection clipboard`). Don't paste it anywhere but the login form:

   ```
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | pbcopy
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

   Open https://localhost:8080 (accept the self-signed certificate) and log in as `admin`.

5. Rotate the password: in the UI, User Info > Update Password, and keep the new one in Doppler. Then delete the initial secret, which Argo CD no longer needs:

   ```
   kubectl -n argocd delete secret argocd-initial-admin-secret
   ```

6. Bootstrap the app-of-apps. The `bootstrap` project limits the root app to creating Applications and AppProjects in `argocd`:

   ```
   kubectl apply -f argocd/bootstrap-project.yaml -f argocd/root.yaml
   kubectl -n argocd get applications
   kubectl -n argocd get appprojects
   ```

   Expect `root` as `Synced` and `Healthy`, and the projects `bootstrap`, `aws-platform` and `default`.

## 5. End of session

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

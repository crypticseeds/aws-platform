# Runbook: tear down the dev environment

Destroys `envs/dev` at the end of a session. Argo CD and the AWS Load Balancer Controller create AWS resources Terraform doesn't know about (the ALB, its target groups and security groups, [ADR 0011](../decisions/0011-argocd-install-by-helm.md)). If `terraform destroy` runs first, the VPC deletion hangs on their network interfaces and security groups, and the ALB keeps billing. So the order is the reverse of [deploy.md](deploy.md) steps 4-5: apps and Ingresses, the ALB, add-ons and Argo CD, then Terraform.

Run it from the repo root with `kubectl` pointed at the dev cluster and the admin logged in (same commands as [deploy.md](deploy.md#2-plan-and-apply-owner)):

```
aws sso login --profile platform-admin        # shortcut: aws-admin-login
export AWS_PROFILE=platform-admin
```

## Why the order matters

Two tools created things in AWS. Terraform created the VPC, NAT gateway, EKS cluster, nodes, budget and the ALB security group, and it remembers them in its state. The AWS Load Balancer Controller, running inside the cluster, created the ALB, its target group and two security groups of its own when the gateway's Ingress appeared. Terraform has never heard of those, and only the controller deletes them. So the controller must clean up first, while it still runs, and Terraform goes last.

**What happens if you run only `terraform destroy`:** Terraform deletes what it knows, in dependency order. The cluster and nodes go, and the controller goes with them, so nothing is left that would delete the ALB. Then Terraform reaches the network and gets stuck:

- `aws-platform-dev-gateway-alb` (Terraform's security group) is still attached to the ALB, so AWS refuses to delete it (`DependencyViolation`).
- The ALB has network interfaces and public addresses in the public subnets, so the subnets, the internet gateway and the VPC can't be deleted either.
- Terraform retries for a while, then exits with errors. The cluster, nodes and IAM are gone, but the ALB keeps running and billing (in eu-west-2 $0.02646 an hour, about $0.64 a day, plus traffic and its public IPv4 addresses), along with the VPC pieces it pins.

The fix afterwards is manual: delete the ALB, its target group and the controller's `k8s-*` security groups in the console or CLI, then run `terraform destroy` again. The steps below avoid all of that.

## 1. Delete the Ingresses and stop Argo CD recreating them (owner)

**What this does and why:** Argo CD's job is to undo any change that doesn't match git, so deleting the Ingress straight away would only see it put back. First take away Argo CD's power to repair things, then delete the Ingress. The controller notices the Ingress is gone and deletes the ALB in AWS.

Two things would undo a plain `kubectl delete ingress`: the `root` app prunes and self-heals, and every child app self-heals (all have `selfHeal: true`), so Argo CD would put the Ingresses straight back. The workloads (`sre-inference-gateway`, `promscope`) are not children of `root`: you applied them by hand from `argocd/workloads/` (DEV-167), so deleting `root` does not touch them, and they self-heal too. The order that avoids it:

1. **Delete the `root` Application first.** While it exists it reverts any change to the child Applications, including step 2 below. Deleting it must not delete the children, so check it has no deletion finalizer (none today, see `argocd/root.yaml`). If the first command prints anything, stop: with `resources-finalizer.argocd.argoproj.io` the delete cascades to every child and removes the Load Balancer Controller before the ALB is gone.

   ```
   kubectl -n argocd get application root -o jsonpath='{.metadata.finalizers}'
   kubectl -n argocd delete application root
   ```

   Expect no output from the first command. Without a finalizer the child Applications and everything they deployed stay in place. Nothing is pruned: prune only runs during a sync of a live app. The hand-applied workload Applications are unaffected either way.

2. **Turn off auto-sync on every remaining Application**, so nothing is recreated or re-synced. The loop lists every Application in the `argocd` namespace, whoever created it, so it covers the platform children of `root` and the hand-applied workloads alike; nothing extra is needed for them:

   ```
   for app in $(kubectl -n argocd get applications -o name); do
     kubectl -n argocd patch "$app" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   done
   ```

   `kubectl -n argocd get applications` should now list each one with no automated sync; check that the gateway and Promscope are there if you applied them.

3. **Delete every Ingress.** The Load Balancer Controller is still running, so it removes the ALB, listeners, target groups and its security groups. Also make sure no Service creates a load balancer of its own (the controller's Service webhook is off, so a `type: LoadBalancer` Service would create a classic load balancer outside the controller):

   ```
   kubectl delete ingress -A --all
   kubectl get svc -A | grep LoadBalancer
   ```

   The second command must print nothing. Delete any Service it lists.

## 2. Wait until the ALB is really gone (owner)

**What this does and why:** the controller deletes the ALB in the background, which takes 1-3 minutes. Removing the controller before it finishes would strand the ALB, exactly the failure described above. This step only reads AWS, so the agent can run it with its read-only profile.

Don't continue until AWS says so. The controller tags everything it creates with `elbv2.k8s.aws/cluster=aws-platform-dev` (plus `ingress.k8s.aws/stack`, here the ALB group `aws-platform-dev`). The tag keys are from the controller's v3.5.0 sources: [pkg/deploy/tracking/provider.go](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/pkg/deploy/tracking/provider.go) and [docs/guide/ingress/annotations.md](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/docs/guide/ingress/annotations.md). This loop checks load balancers, target groups and security groups by that tag and ends when all three counts are 0, or gives up after 10 minutes:

```
for i in $(seq 1 60); do
  lb=$(aws resourcegroupstaggingapi get-resources --region eu-west-2 --resource-type-filters elasticloadbalancing:loadbalancer --tag-filters Key=elbv2.k8s.aws/cluster,Values=aws-platform-dev --query 'length(ResourceTagMappingList)')
  tg=$(aws resourcegroupstaggingapi get-resources --region eu-west-2 --resource-type-filters elasticloadbalancing:targetgroup --tag-filters Key=elbv2.k8s.aws/cluster,Values=aws-platform-dev --query 'length(ResourceTagMappingList)')
  sg=$(aws ec2 describe-security-groups --region eu-west-2 --filters Name=tag:elbv2.k8s.aws/cluster,Values=aws-platform-dev --query 'length(SecurityGroups)')
  echo "load balancers=$lb target groups=$tg security groups=$sg"
  [ "$lb$tg$sg" = "000" ] && break
  sleep 10
done
[ "$lb$tg$sg" = "000" ] && echo "ALB gone" || echo "TIMEOUT: still there"
```

On `TIMEOUT`, don't go on. Check the controller logs (`kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50`) and that no Ingress is left (`kubectl get ingress -A`). Never delete the security group by hand while the controller is still running.

Classic load balancers (from a `type: LoadBalancer` Service) are not covered by the tag above. Step 1 already ruled them out, and the leak check in step 5 catches the VPC they would block.

## 3. Remove Argo CD and the add-ons (owner)

**What this does and why:** with the ALB gone, nothing inside the cluster owns anything in AWS any more. Removing Argo CD and the add-ons now is tidy rather than essential: the cluster destroy would remove them anyway. Doing it explicitly means nothing can recreate an Ingress during the destroy.

The ALB is gone, so the controller is no longer needed.

```
kubectl -n argocd delete applications --all
helm uninstall argocd -n argocd
kubectl delete namespace monitoring cert-manager argocd
```

Deleting the Applications leaves the add-on resources in place (no finalizer). Deleting the `monitoring` namespace removes Prometheus, Alertmanager and Grafana (all on emptyDir, so no volumes to leak). cert-manager creates nothing in AWS. The Load Balancer Controller in `kube-system` is not removed on its own: it has no AWS resources left, and the cluster destroy in step 4 removes it with the nodes. Its IAM role and Pod Identity association are in `envs/dev`, so Terraform removes those too.

## 4. Terraform destroy (owner)

**What this does and why:** Terraform deletes everything it created in `envs/dev`, in reverse dependency order. Plan first and read it: it must only delete, and only in `envs/dev`.

Review the plan first, as in [deploy.md](deploy.md#6-end-of-session):

```
cd envs/dev
doppler run --name-transformer tf-var -- terraform plan -destroy
doppler run --name-transformer tf-var -- terraform destroy
```

Expect only deletions, all in `envs/dev`: `Plan: 0 to add, 0 to change, 69 to destroy.` on the 2026-10-10 code (the same 69 the apply created: VPC, NAT gateway, EKS cluster and node group, add-on IAM role, budget, gateway ALB security group and their parts). It takes about 10-15 minutes. If the VPC deletion hangs on `DependencyViolation`, something from step 1 or 2 is left: run the leak check below and look at the network interfaces.

## 5. Leak check (agent, read-only MCP)

**What this does and why:** a destroy can report success and still leave something billing. This independent check reads AWS and counts what is left under the project's tags and names.

Run `scripts/leak-check.py` through the AWS MCP Server's `run_script` tool (agent profile, read-only): pass the file's content as the `code` argument. It uses only `Describe*` calls, in `eu-west-2`, and counts what is left:

- load balancers and target groups tagged `Project=aws-platform` or `elbv2.k8s.aws/cluster=aws-platform-dev`
- NAT gateways and network interfaces in the VPC tagged `Name=aws-platform-dev`, or tagged `Project=aws-platform` and `Environment=dev`
- Elastic IPs tagged `Project=aws-platform` and `Environment=dev`, or named `aws-platform-dev*`
- unattached (`available`) EBS volumes with the project tags
- whether the VPC itself still exists

It prints one line per resource type and ends with `PASS: nothing left` or `FAIL: ...` and a non-zero exit. A clean destroy prints `0` on every line. A NAT gateway stays visible as deleted for about an hour after destroy; the script ignores that state.

On `FAIL`, don't just re-run destroy: find what holds the resource (a network interface's description names its owner), delete the owner, then re-run the check.

## 6. Log out the admin (owner)

See [bootstrap.md](bootstrap.md#step-2-move-bootstrap-state-into-the-bucket-owner) for the standard and shortcut commands.

## Never destroy

- **`bootstrap/`** ([bootstrap.md](bootstrap.md)): the Terraform state bucket. It has `prevent_destroy`, and it holds the state of every root. Losing it loses track of everything.
- **`account/`** ([account.md](account.md)): the GitHub OIDC provider and the CI role. They cost nothing, and CI plans stop working without them.

Run `terraform destroy` only in `envs/dev`.

## Timing

To be measured on the first drill: apps and ALB gone (steps 1-2), Argo CD removal (step 3), `terraform destroy` (step 4).

## Gotchas

To be filled after the first drill.

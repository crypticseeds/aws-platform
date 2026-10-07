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

## 5. Platform add-ons (owner)

The root app creates two add-on Applications from `argocd/apps/`: the AWS Load Balancer Controller (`kube-system`, sync wave -2) and kube-prometheus-stack (`monitoring`, wave -1). Apps come after them (wave 0).

The controller's IAM role and its Pod Identity association are part of `envs/dev`, so step 2's apply already created them. Nothing to do for the controller.

**Before the first install:** store the Grafana admin login in Doppler as `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD`.

1. Create the Grafana admin Secret before Argo CD syncs kube-prometheus-stack (otherwise Grafana waits in `CreateContainerConfigError` until it exists). Both values go from Doppler to `kubectl` through stdin, so they never appear in your terminal, shell history or the process list. Run it where `doppler setup` points at the config with the secrets (or add `-p <project> -c <config>`):

   ```
   kubectl create namespace monitoring
   doppler run --only-secrets GRAFANA_ADMIN_USER,GRAFANA_ADMIN_PASSWORD -- sh -c 'printf "admin-user=%s\nadmin-password=%s\n" "$GRAFANA_ADMIN_USER" "$GRAFANA_ADMIN_PASSWORD" | kubectl -n monitoring create secret generic grafana-admin --from-env-file=/dev/stdin'
   ```

   `printf` is a shell builtin, so the values are not in any process's arguments either. `describe` shows only the key names and sizes:

   ```
   kubectl -n monitoring describe secret grafana-admin
   ```

   Expect the keys `admin-user` and `admin-password`.

2. Watch both add-ons sync:

   ```
   kubectl -n argocd get applications
   ```

   Expect `aws-load-balancer-controller` and `kube-prometheus-stack` both `Synced` and `Healthy`.

3. The controller must have its AWS permissions. Both pods `Running`, and no AccessDenied in its first 5 minutes of logs:

   ```
   kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
   kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller --since=5m --tail=-1 | grep -ci accessdenied
   ```

   Expect `0`.

4. Nothing in monitoring is exposed:

   ```
   kubectl get svc -A | grep -E 'grafana|prometheus|alertmanager'
   ```

   Every line must be `ClusterIP`, none `LoadBalancer` or `NodePort`.

5. Log in to Grafana over port-forward with the Doppler credentials:

   ```
   kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
   ```

   Open http://localhost:3000. Prometheus and Alertmanager work the same way when needed (`svc/kube-prometheus-stack-prometheus 9090:9090`, `svc/kube-prometheus-stack-alertmanager 9093:9093`).

6. Record node headroom with both add-ons running (the "before" number for P4):

   ```
   kubectl top nodes
   ```

Prometheus keeps 2 days of data on an emptyDir, and Grafana has no volume either: both start empty after a pod restart or a rebuild. Dashboards come from ConfigMaps labelled `grafana_dashboard: "1"` in any namespace.

## 6. Gateway and Promscope (owner)

The root app also creates `sre-inference-gateway` (namespace `gateway`) and `promscope` (namespace `promscope`) from `argocd/apps/`, sync wave 0, after the controller (-2) and kube-prometheus-stack (-1). The gateway's Ingress joins the ALB group `aws-platform-dev`, so the controller builds one internet-facing ALB on port 80. Promscope has no Ingress (ClusterIP only, no authentication). Both images are pinned to a git SHA in the Application's `valuesObject`.

Both Docker Hub repositories are public. The Secret `dockerhub-pull` only lifts anonymous pull rate limits. Both charts reference it through `imagePullSecrets`. If it does not exist, the pods still start: the kubelet logs a warning event on the pod and pulls anonymously. Create it before the first sync anyway.

**Before the first sync:** store a Docker Hub username and an access token (read-only scope) in Doppler as `DOCKERHUB_PULL_USERNAME` and `DOCKERHUB_PULL_TOKEN` (the pull credentials; the `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` pair is the push credential used by the image workflows in GitHub Actions).

1. Create the namespaces and the pull Secret in each. The values go from Doppler to `kubectl` through stdin, so they never appear in your terminal, shell history or the process list (`printf` is a builtin). Run it where `doppler setup` points at the config with the secrets (or add `-p <project> -c <config>`):

   ```
   kubectl create namespace gateway
   kubectl create namespace promscope
   doppler run --only-secrets DOCKERHUB_PULL_USERNAME,DOCKERHUB_PULL_TOKEN -- sh -c 'printf "{\"auths\":{\"https://index.docker.io/v1/\":{\"username\":\"%s\",\"password\":\"%s\"}}}" "$DOCKERHUB_PULL_USERNAME" "$DOCKERHUB_PULL_TOKEN" | kubectl -n gateway create secret generic dockerhub-pull --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin'
   doppler run --only-secrets DOCKERHUB_PULL_USERNAME,DOCKERHUB_PULL_TOKEN -- sh -c 'printf "{\"auths\":{\"https://index.docker.io/v1/\":{\"username\":\"%s\",\"password\":\"%s\"}}}" "$DOCKERHUB_PULL_USERNAME" "$DOCKERHUB_PULL_TOKEN" | kubectl -n promscope create secret generic dockerhub-pull --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin'
   ```

   `describe` shows only the key name and size. Expect type `kubernetes.io/dockerconfigjson` and the key `.dockerconfigjson`:

   ```
   kubectl -n gateway describe secret dockerhub-pull
   kubectl -n promscope describe secret dockerhub-pull
   ```

   The Applications set `CreateNamespace=true`, which does nothing when the namespace already exists.

2. Watch both sync. The two Applications appear only after the root app has created them, which waits for the Load Balancer Controller (wave -2) and kube-prometheus-stack (wave -1) to be Healthy. Wait until the first command lists both, then run the rollout commands:

   ```
   kubectl -n argocd get applications
   kubectl -n gateway rollout status deployment/sre-inference-gateway
   kubectl -n promscope rollout status deployment/promscope
   ```

   The controller needs about 2-3 minutes to create the ALB after the Ingress appears.

### Release a new image (tag bump)

1. Find the new SHA: the run of the `Image` workflow in the app's GitHub repository (Actions tab, the run for the commit; the tag is the full 40-character commit SHA), or the tag list on Docker Hub (`crypticseeds/sre-inference-gateway`, `crypticseeds/promscope`). Never use `latest`.
2. Open a PR that changes only `image.tag` (keep the quotes) in `argocd/apps/sre-inference-gateway.yaml` or `argocd/apps/promscope.yaml`. CI lints and renders the charts with test values but does not check the tag, so a mistyped or non-existent SHA still passes and only fails as `ImagePullBackOff` after the sync (the rolling update keeps the old pods running). Before merging, confirm the tag exists on Docker Hub (the Tags page, or `docker manifest inspect crypticseeds/<repo>:<sha>` from the Mac); review and merge.
3. Argo CD syncs `main` by itself (automated sync, about 3 minutes, or press Refresh in the UI). Check the rollout and the running image:

   ```
   kubectl -n gateway rollout status deployment/sre-inference-gateway
   kubectl -n gateway get deployment sre-inference-gateway -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   ```

   Use `-n promscope` and `deployment/promscope` for Promscope. The PodDisruptionBudget keeps one replica serving during the rollout.

To roll back, revert the PR.

### Verification (owner, with the agent's read-only MCP)

(a) Both Applications are `Synced` and `Healthy`:

```
kubectl -n argocd get applications
```

(b) Pods reference the pull Secret and run the pinned SHA:

```
kubectl -n gateway get pod -l app.kubernetes.io/name=sre-inference-gateway -o jsonpath='{.items[*].spec.imagePullSecrets}{"\n"}'
kubectl -n gateway get pod -l app.kubernetes.io/name=sre-inference-gateway -o jsonpath='{.items[*].spec.containers[0].image}{"\n"}'
kubectl -n promscope get pod -l app.kubernetes.io/name=promscope -o jsonpath='{.items[*].spec.imagePullSecrets}{"\n"}'
kubectl -n promscope get pod -l app.kubernetes.io/name=promscope -o jsonpath='{.items[*].spec.containers[0].image}{"\n"}'
```

Expect `[{"name":"dockerhub-pull"}]` per pod, and the image tags equal to the `image.tag` in the two Applications.

(c) Agent, MCP (`eu-west-2`): `DescribeLoadBalancers` shows exactly one internet-facing `application` load balancer for this cluster. `DescribeTags` (or Resource Groups Tagging `GetResources`) on its ARN shows the `defaultTags` (`Project=aws-platform`, `Application=platform`, `Environment=dev`, `ManagedBy=aws-load-balancer-controller`); `DescribeLoadBalancers` itself returns no tags. `DescribeTargetHealth` on its target group shows every target `healthy`, one per gateway pod. A second ALB means an Ingress is missing `group.name`.

(d) Health through the ALB (the DNS name is in `kubectl -n gateway get ingress`, column ADDRESS):

```
curl -s -o /dev/null -w '%{http_code}\n' http://<alb-dns>/v1/health
```

Expect `200`.

(e) Streaming. Dev has only the mock model `mock-model` (3 content chunks, 0.05 s apart). Expect several `data:` lines and a last `data: [DONE]`:

```
curl -N -H 'Content-Type: application/json' -d '{"model":"mock-model","messages":[{"role":"user","content":"hello"}],"stream":true}' http://<alb-dns>/v1/chat/completions
```

(f) One tag bump done through a PR, as in "Release a new image" above. Record the PR and the old and new tag in the journal.

Promscope is reached only with a port-forward: `kubectl -n promscope port-forward svc/promscope 8090:8090`, then `http://localhost:8090/mcp`. Prometheus targets for both ServiceMonitors can be checked with the port-forward in section 5 (Status, Targets).

## 7. End of session

The environment costs roughly $6-7 a day while it runs, so destroy it when you finish. Review the destroy plan first:

```
terraform plan -destroy
terraform destroy
```

Then log out the admin (see [bootstrap.md](bootstrap.md#step-2-move-bootstrap-state-into-the-bucket-owner) for the standard and shortcut commands).

The full teardown order, needed once Argo CD and the Load Balancer Controller create resources outside Terraform, is in [teardown.md](teardown.md).

## Verification (agent, read-only MCP)

- `DescribeNatGateways`: exactly 1 available NAT in the VPC.
- `DescribeSubnets`: 3 private and 3 public subnets with the `kubernetes.io/role/*elb` tags.
- `DescribeVpcEndpoints`: the S3 gateway endpoint on the private route tables.
- `DescribeCluster`: version 1.36, `authenticationMode=API`, public endpoint limited to your CIDR, audit + authenticator logging.
- `ListAccessEntries`: only the PlatformAdmin role (plus the node role EKS adds itself).
- Resource Groups Tagging: every resource tagged `Project=aws-platform`, `Application=platform`.
- `ListPodIdentityAssociations`: one association, `kube-system`/`aws-load-balancer-controller`, with the `aws-platform-dev-aws-load-balancer-controller` role.
- Resource Groups Tagging, once an Ingress exists: the ALB and its target groups carry the controller's `defaultTags` (`Project`, `Application`, `Environment`, `ManagedBy`, `Repository`).

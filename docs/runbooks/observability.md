# Observability

Evidence that the gateway and Promscope are scraped by Prometheus, that the gateway dashboard is in Grafana, and that Promscope answers over MCP. Run it after the apps are synced (`docs/runbooks/deploy.md`). Everything is reached by port-forward; nothing is exposed.

How it is wired:

- Both charts ship a `ServiceMonitor` (`serviceMonitor.enabled: true` in the Argo Applications). It selects the chart's own Service by `app.kubernetes.io/name` and `app.kubernetes.io/instance`, and scrapes `/metrics` on the Service port named `http` for both: the gateway serves `/metrics` from its API app on port 8000 (the chart's separate `metrics` port, 9090, has no listener), and Promscope serves it on 8090.
- Prometheus selects every ServiceMonitor in every namespace: the rendered `Prometheus` object has `serviceMonitorSelector: {}` and `serviceMonitorNamespaceSelector: {}` (from `serviceMonitorSelectorNilUsesHelmValues: false` in `argocd/apps/kube-prometheus-stack.yaml`). No `release` label is needed.
- The gateway dashboard is the ConfigMap `gateway-dashboard` in `monitoring`, labelled `grafana_dashboard: "1"`, built by the Argo Application `grafana-dashboards` from `platform/grafana-dashboards/`. The Grafana sidecar loads it within about a minute. Its panels use the stack's default datasource, uid `prometheus`.

Use one terminal per port-forward, or add `&` and `kill %1` when done.

## 0. Check the Applications

```
kubectl -n argocd get applications
kubectl -n monitoring get configmap gateway-dashboard --show-labels
```

Expect `grafana-dashboards`, `sre-inference-gateway`, `promscope` and `kube-prometheus-stack` `Synced` and `Healthy`, and the label `grafana_dashboard=1` on the ConfigMap.

## 1. Prometheus targets are up

```
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

In another terminal:

```
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test("gateway|promscope")) | {job: .labels.job, namespace: .labels.namespace, health, lastError}'
```

Expect one target per gateway pod (2, namespace `gateway`) and one per Promscope pod (2, namespace `promscope`), all `"health": "up"` with an empty `lastError`. The ServiceMonitor makes one target per ready pod, and both charts run 2 replicas.

PromQL: every target reports 1.

```
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=up{job=~".*gateway.*|.*promscope.*"}' | jq '.data.result[] | {job: .metric.job, value: .value[1]}'
```

Pass/fail in one command (exit 0 only if both the gateway and Promscope jobs are present and every series is 1):

```
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=up{job=~".*gateway.*|.*promscope.*"}' | jq -e '([.data.result[].metric.job] | unique | map(select(test("gateway|promscope"))) | length) == 2 and all(.data.result[]; .value[1] == "1")'
```

If a target is missing, check in this order:

```
kubectl get servicemonitor -A
kubectl -n gateway get svc --show-labels
kubectl -n promscope get svc --show-labels
```

The ServiceMonitor's `spec.selector.matchLabels` must be a subset of the Service labels, and the endpoint `port` must be a Service port name (`http` for both charts). A target listed with `health="down"` and a `lastError` means the selection worked but the pod does not serve `/metrics` on that port.

## 2. Grafana lists the dashboard and a panel returns data

```
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

The Grafana admin login lives in the Secret `grafana-admin` (see deploy.md step 5). To call the API without the password appearing in your terminal, history or a process argument list, define this function. It gives curl the login on stdin as a curl config (`-K -`), which is not an argument:

```
grafana() {
  kubectl -n monitoring get secret grafana-admin -o go-template='user = "{{index .data "admin-user" | base64decode}}:{{index .data "admin-password" | base64decode}}"' | curl -sS -K - "$@"
}
```

The dashboard is listed:

```
grafana 'http://localhost:3000/api/search?query=gateway' | jq '.[] | {title, uid, type}'
```

Expect `SRE Inference Gateway`, uid `sre-inference-gateway`.

Generate traffic through the gateway (second port-forward, the request path is from the gateway's README; the dev config has a `mock-model` provider):

```
kubectl -n gateway port-forward svc/sre-inference-gateway 8000:8000
```

If the Service has another name (it follows the Argo release name), find it with `kubectl -n gateway get svc`.

```
for i in $(seq 1 30); do curl -s localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"mock-model","messages":[{"role":"user","content":"hello"}]}' -o /dev/null; done
```

Wait two scrape intervals (about a minute), then run the query of the first panel through Grafana's datasource proxy:

```
cat > /tmp/ds-query.json <<'EOF'
{"queries":[{"refId":"A","datasource":{"type":"prometheus","uid":"prometheus"},"expr":"sum by (provider, stream) (rate(gateway_requests_total[5m]))","instant":true}],"from":"now-15m","to":"now"}
EOF
grafana -X POST -H 'Content-Type: application/json' -d @/tmp/ds-query.json http://localhost:3000/api/ds/query | jq '.results.A.frames | map({fields: (.schema.fields | map(.name)), values: (.data.values | map(length))})'
```

Expect at least one frame whose `values` lengths are above 0. An empty `frames` array means no gateway series yet: re-check section 1 and the traffic step. A `datasource ... not found` error means the datasource uid is not `prometheus`: read the right one with `grafana http://localhost:3000/api/datasources | jq '.[] | {name, uid}'` and fix the uid in `platform/grafana-dashboards/gateway-dashboard.json`.

Then open http://localhost:3000, dashboard `SRE Inference Gateway`, to see the panels fill.

## 3. Promscope answers over MCP

Promscope serves MCP over streamable HTTP on `POST /mcp` (stateless), plus `/healthz` and `/metrics`, all on port 8090. It has no authentication, so it is only reached by port-forward.

```
kubectl -n promscope port-forward svc/promscope 8090:8090
```

If the Service has another name, find it with `kubectl -n promscope get svc`. Then:

```
scripts/promscope-mcp-check.sh http://localhost:8090
```

The script sends `initialize`, `tools/list` and one `tools/call` of `query_metrics` with the query `up` (pass another PromQL as the second argument), prints each response trimmed to 600 characters, and exits non-zero on an HTTP error, a JSON-RPC error, a tool error, or a missing `query_metrics` tool. Expect the three tools `list_metrics`, `get_alerts`, `query_metrics`, and a last line `OK: ... succeeded, N series` with N at least the number of targets from section 1.

If the call returns a tool error such as `query failed`, Promscope reached no Prometheus: it queries `http://kube-prometheus-stack-prometheus.monitoring:9090` (`prometheusURL` in `charts/promscope/values.yaml`).

## Evidence to keep

For the issue: the output of section 1 (targets and the `jq -e` result), section 2 (dashboard search and a non-empty frame) and section 3 (the script output). Paste text, not screenshots, and never paste anything from the Grafana Secret.

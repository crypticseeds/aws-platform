#!/usr/bin/env bash
# Promscope MCP smoke check: initialize -> tools/list -> one query_metrics call.
#
# Promscope speaks MCP over streamable HTTP on POST /mcp (stateless by
# default). Reach it through a port-forward and pass the base URL:
#
#   kubectl -n promscope port-forward svc/promscope 8090:8090
#   scripts/promscope-mcp-check.sh http://localhost:8090
#
# Prints a trimmed JSON-RPC response per step; exits non-zero on the first
# HTTP error, JSON-RPC error, tool error or missing expected field.
# Needs: bash, curl, jq. Optional second argument: the PromQL (default: up).
set -euo pipefail

base="${1:?usage: $0 BASE_URL [PROMQL]}"
query="${2:-up}"
url="${base%/}/mcp"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

session=""
version="2025-06-18"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# rpc LABEL JSON: POST one JSON-RPC message, leave the JSON-RPC response in
# $tmp/resp.json. The server answers with plain JSON or a one-event SSE
# stream; both are reduced to the JSON payload.
rpc() {
  local label="$1" body="$2" code
  local args=(-sS --max-time 20 -o "$tmp/raw" -D "$tmp/hdr" -w '%{http_code}'
    -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream'
    -H "MCP-Protocol-Version: $version")
  [ -n "$session" ] && args+=(-H "Mcp-Session-Id: $session")
  code="$(curl "${args[@]}" -d "$body" "$url")" || fail "$label: cannot reach $url"
  [[ "$code" =~ ^2 ]] || fail "$label: HTTP $code: $(head -c 300 "$tmp/raw")"
  if [ ! -s "$tmp/raw" ]; then
    : >"$tmp/resp.json"
    return
  fi
  if grep -q '^data:' "$tmp/raw"; then
    grep '^data:' "$tmp/raw" | tail -n 1 | sed 's/^data: *//' >"$tmp/resp.json"
  else
    cp "$tmp/raw" "$tmp/resp.json"
  fi
  jq -e . "$tmp/resp.json" >/dev/null 2>&1 || fail "$label: response is not JSON: $(head -c 300 "$tmp/raw")"
  jq -e '.error' "$tmp/resp.json" >/dev/null 2>&1 && fail "$label: JSON-RPC error: $(jq -c .error "$tmp/resp.json")"
  jq -e '.result' "$tmp/resp.json" >/dev/null 2>&1 || fail "$label: no result in response"
  echo "== $label"
  jq -c '.' "$tmp/resp.json" | cut -c 1-600
}

rpc initialize "$(jq -nc --arg v "$version" \
  '{jsonrpc:"2.0",id:1,method:"initialize",params:{protocolVersion:$v,capabilities:{},clientInfo:{name:"promscope-mcp-check",version:"0.1.0"}}}')"
jq -e '.result.serverInfo.name' "$tmp/resp.json" >/dev/null || fail "initialize: no serverInfo.name"
version="$(jq -r '.result.protocolVersion // empty' "$tmp/resp.json")"
version="${version:-2025-06-18}"
session="$(awk 'tolower($1)=="mcp-session-id:" {gsub("\r","",$2); print $2}' "$tmp/hdr")"

# Notification: no response body expected (202).
note_args=(-sS --max-time 20 -o /dev/null
  -H 'Content-Type: application/json'
  -H 'Accept: application/json, text/event-stream'
  -H "MCP-Protocol-Version: $version")
[ -n "$session" ] && note_args+=(-H "Mcp-Session-Id: $session")
curl "${note_args[@]}" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$url" \
  || fail "notifications/initialized: cannot reach $url"

rpc tools/list '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
jq -e '[.result.tools[].name] | index("query_metrics")' "$tmp/resp.json" >/dev/null \
  || fail "tools/list: query_metrics not offered: $(jq -c '[.result.tools[].name]' "$tmp/resp.json")"

rpc "tools/call query_metrics($query)" "$(jq -nc --arg q "$query" \
  '{jsonrpc:"2.0",id:3,method:"tools/call",params:{name:"query_metrics",arguments:{query:$q}}}')"
if jq -e '.result.isError == true' "$tmp/resp.json" >/dev/null; then
  fail "tools/call: tool reported an error: $(jq -c '.result.content' "$tmp/resp.json" | cut -c 1-300)"
fi
series="$(jq -r '.result.structuredContent.totalSeries // empty' "$tmp/resp.json")"
[ -n "$series" ] || fail "tools/call: no structuredContent.totalSeries in the result"

echo "OK: initialize, tools/list and query_metrics($query) succeeded, $series series"

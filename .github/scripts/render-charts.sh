#!/usr/bin/env bash
# Lint and render every chart under charts/ into OUTDIR/<chart>.yaml, with the
# same values the offline checks use: values-dev.yaml, then ci/test-values.yaml.
# Used by .github/workflows/checks.yml and runnable locally:
#   .github/scripts/render-charts.sh rendered
set -euo pipefail

outdir=${1:?usage: render-charts.sh OUTDIR}
mkdir -p "$outdir"

for chart in charts/*/; do
  chart=${chart%/}
  name=$(basename "$chart")
  for f in values-dev.yaml ci/test-values.yaml; do
    if [[ ! -f "$chart/$f" ]]; then
      echo "::error file=$chart/$f::$name: missing $f (every chart needs values-dev.yaml and ci/test-values.yaml)"
      exit 1
    fi
  done
  values=(-f "$chart/values-dev.yaml" -f "$chart/ci/test-values.yaml")

  echo "== helm lint $chart"
  helm lint --strict "$chart" "${values[@]}"

  echo "== helm template $chart > $outdir/$name.yaml"
  helm template "$name" "$chart" "${values[@]}" > "$outdir/$name.yaml"
done

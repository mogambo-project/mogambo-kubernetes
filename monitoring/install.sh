#!/usr/bin/env bash
# Prometheus + Grafana via kube-prometheus-stack (trimmed for a memory-limited kind/WSL cluster).
# Idempotent. After this, apply the Grafana route:  kubectl apply -f monitoring/grafana-route.yaml
set -euo pipefail

CHART_VERSION="88.2.0"     # app: prometheus-operator v0.93.0 / Grafana + Prometheus bundled
HERE="$(cd "$(dirname "$0")" && pwd)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" \
  --namespace monitoring --create-namespace \
  -f "$HERE/values.yaml" \
  --wait --timeout 8m

kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=180s
echo "Monitoring ready. Apply the route:  kubectl apply -f monitoring/grafana-route.yaml"
echo "Grafana: http://grafana.localtest.me:8090/  (admin / admin)"

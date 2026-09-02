#!/usr/bin/env bash
# Observability pillars 2 & 3 for mogambo: LOGS (Loki) and TRACES (Tempo).
# Metrics already live in the `monitoring` namespace (kube-prometheus-stack).
#
# What this installs, all in the `observability` namespace:
#   Loki          - log store (SingleBinary, small local-path PVC)
#   Alloy         - single Deployment that tails every pod's logs -> Loki   (no app changes)
#   Tempo         - trace store (monolithic) with an OTLP receiver
#   OTel Operator - injects language auto-instrumentation agents into carts/frontend via a pod
#                   annotation -> in-service traces to Tempo (no code changes; WSL2-friendly).
#                   (Beyla eBPF was tried first but the WSL2 kernel lacks the kprobes it needs.)
#
# It also registers Loki + Tempo as Grafana datasources (labelled ConfigMaps the Grafana
# sidecar auto-loads) and — separately — Envoy edge tracing is enabled in gateway/05-envoyproxy.yaml.
#
# Idempotent. Safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

LOKI_VERSION="7.3.0"
TEMPO_VERSION="1.24.4"
ALLOY_VERSION="1.12.1"
OTEL_OPERATOR_VERSION="0.122.0"

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

kubectl apply -f "$HERE/00-namespace.yaml"

echo "=== Loki (logs store) ==="
helm upgrade --install loki grafana/loki --version "$LOKI_VERSION" \
  --namespace observability -f "$HERE/loki-values.yaml" --timeout 6m
kubectl -n observability rollout status statefulset/loki --timeout=240s

echo "=== Alloy (log collector DaemonSet) ==="
helm upgrade --install alloy grafana/alloy --version "$ALLOY_VERSION" \
  --namespace observability -f "$HERE/alloy-values.yaml" --timeout 4m

echo "=== Tempo (trace store, OTLP receiver) ==="
helm upgrade --install tempo grafana/tempo --version "$TEMPO_VERSION" \
  --namespace observability -f "$HERE/tempo-values.yaml" --timeout 4m

echo "=== OpenTelemetry Operator (auto-instrumentation injector) ==="
helm upgrade --install otel-operator open-telemetry/opentelemetry-operator --version "$OTEL_OPERATOR_VERSION" \
  --namespace observability -f "$HERE/otel-operator-values.yaml" --wait --timeout 4m

echo "=== Instrumentation CR (injected agents export traces -> Tempo) ==="
kubectl apply -f "$HERE/instrumentation.yaml"

echo "=== Grafana datasources (Loki + Tempo) ==="
kubectl apply -f "$HERE/grafana-datasources.yaml"

echo
echo "Done."
echo "Enable Envoy edge tracing (if not already):  kubectl apply -f gateway/05-envoyproxy.yaml"
echo "carts (Java) + frontend (Node) are annotated for auto-instrumentation in their manifests;"
echo "apply + roll them to inject the agents:"
echo "  kubectl apply -f manifests/30-carts.yaml -f manifests/40-frontend.yaml"
echo "  kubectl -n mogambo rollout restart deploy/carts deploy/frontend"
echo "Then open Grafana (http://grafana.localtest.me:8090/) -> Explore -> pick Loki or Tempo."
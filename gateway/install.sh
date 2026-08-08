#!/usr/bin/env bash
set -euo pipefail

CHART_VERSION="1.8.3"     # Envoy Gateway app v1.8.3

helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$CHART_VERSION" \
  --namespace envoy-gateway-system --create-namespace \
  --wait --timeout 5m

kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s
echo "Envoy Gateway $CHART_VERSION ready. Now apply the Gateway API resources:  kubectl apply -f gateway/"

# Reproducible install of the Envoy Gateway controller (the Gateway API implementation).
# Idempotent: helm upgrade --install. Gateway API CRDs are a prerequisite and are bundled by
# this chart (Helm leaves any newer CRDs already present untouched).
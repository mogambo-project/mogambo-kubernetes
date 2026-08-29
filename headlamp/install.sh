#!/usr/bin/env bash
# Headlamp — lightweight web UI for the cluster (view/edit/logs/exec). Free, CNCF (kubernetes-sigs).
# Idempotent: helm upgrade --install. After this, apply the RBAC + route:  kubectl apply -f headlamp/
set -euo pipefail

CHART_VERSION="0.44.0"

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null 2>&1 || true
helm repo update headlamp
helm upgrade --install headlamp headlamp/headlamp --version "$CHART_VERSION" \
  --namespace headlamp --create-namespace --wait --timeout 5m

kubectl -n headlamp rollout status deploy/headlamp --timeout=120s
echo "Headlamp $CHART_VERSION ready. Now:  kubectl apply -f headlamp/   (RBAC + HTTPRoute)"

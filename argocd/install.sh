#!/usr/bin/env bash
# Argo CD — GitOps controller + UI for mogambo.
# Installs Argo CD (trimmed), exposes the UI via the shared gateway, and registers the
# `mogambo-apps` Application that keeps the `manifests/` app layer in sync with Git.
# Idempotent.
set -euo pipefail
CHART_VERSION="10.8.4"          # Argo CD v3.5.x
HERE="$(cd "$(dirname "$0")" && pwd)"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo

echo "=== install Argo CD ==="
helm upgrade --install argocd argo/argo-cd --version "$CHART_VERSION" \
  --namespace argocd --create-namespace -f "$HERE/values.yaml" --wait --timeout 8m

echo "=== allow the argocd namespace on the gateway, then expose the UI ==="
kubectl apply -f "$HERE/../gateway/10-gateway.yaml"
kubectl apply -f "$HERE/10-route.yaml"

echo "=== register the GitOps Application (manual sync to start) ==="
kubectl apply -f "$HERE/20-app-mogambo.yaml"

echo
echo "Argo CD UI:  http://argocd.localtest.me:8090/"
echo -n "admin password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo "(user: admin)"
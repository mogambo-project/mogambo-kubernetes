#!/usr/bin/env bash
set -euo pipefail

CHART_VERSION="4.15.1"    # controller app v1.15.1 — pinned for reproducibility
HERE="$(cd "$(dirname "$0")" && pwd)"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version "$CHART_VERSION" \
  -f "$HERE/values.yaml" \
  --wait

kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller

# Print the REAL host port the controller is reachable on (derived from the kind node's
# published port mapping), instead of hardcoding it. Host is app-defined, so left as a placeholder.
NODE="$(kubectl -n ingress-nginx get pod -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.nodeName}')"
HTTP_PORT="$(docker port "$NODE" 80/tcp 2>/dev/null | head -1 | sed 's/.*://')"
echo "ingress-nginx $CHART_VERSION ready. Test:  curl -H 'Host: <your-ingress-host>' http://localhost:${HTTP_PORT:-8090}/"
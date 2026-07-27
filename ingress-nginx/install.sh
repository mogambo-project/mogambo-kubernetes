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
echo "ingress-nginx $CHART_VERSION ready. Test:  curl -H 'Host: mogambo.localtest.me' http://localhost:8090/"
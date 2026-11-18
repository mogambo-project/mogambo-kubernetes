#!/usr/bin/env bash
# Calico CNI via the Tigera operator HELM CHART (replaces the old kubectl-apply of the operator
# manifest + installation.yaml). Installs the operator and renders the Installation + APIServer CRs
# from values.yaml.
#
# This stays a DAY-0 step on purpose: with kind's disableDefaultCNI the nodes are NotReady until a
# CNI is installed, so Calico must exist BEFORE Argo CD can run. Run it right after
# `kind create cluster`. Idempotent (helm upgrade --install).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHART_VERSION="v3.29.1"   # tigera-operator chart == Calico v3.29.1

helm repo add projectcalico https://docs.tigera.io/calico/charts >/dev/null 2>&1 || true
helm repo update projectcalico

echo "=== install Calico (Tigera operator $CHART_VERSION) ==="
helm upgrade --install calico projectcalico/tigera-operator \
  --version "$CHART_VERSION" \
  --namespace tigera-operator --create-namespace \
  -f "$HERE/values.yaml" --wait --timeout 5m

echo "=== wait for Calico + nodes Ready ==="
for i in $(seq 1 60); do
  kubectl get ns calico-system >/dev/null 2>&1 && break; sleep 3
done
kubectl -n calico-system rollout status ds/calico-node --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo "Calico $CHART_VERSION ready — NetworkPolicy is now enforced."

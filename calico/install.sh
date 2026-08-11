#!/usr/bin/env bash
set -euo pipefail

CALICO_VERSION="v3.29.1"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "=== Tigera operator ($CALICO_VERSION) ==="
kubectl apply --server-side -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
kubectl -n tigera-operator rollout status deploy/tigera-operator --timeout=180s
kubectl wait --for=condition=established crd/installations.operator.tigera.io --timeout=90s

echo "=== Installation (pod CIDR 10.244.0.0/16 to match kind) ==="
kubectl apply -f "$HERE/installation.yaml"

echo "=== wait for Calico + nodes Ready ==="
for i in $(seq 1 60); do
  kubectl get ns calico-system >/dev/null 2>&1 && break; sleep 3
done
kubectl -n calico-system rollout status ds/calico-node --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo "Calico $CALICO_VERSION ready — NetworkPolicy is now enforced."

# Install Calico as the cluster CNI (replaces kindnet) so NetworkPolicy is ENFORCED.
# Run this right after `kind create cluster` — with disableDefaultCNI the nodes stay NotReady
# until a CNI is installed. Idempotent.

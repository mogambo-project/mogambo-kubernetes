#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mogambo cluster recovery
# ---------------------------------------------------------------------------
# Run this after the machine sleeps / WSL restarts / a WSL crash. It fixes the
# recurring cascade on this kind-on-WSL2 cluster:
#   1. wedged apiserver port-proxy   -> restart the kind node containers
#   2. stale Calico token / Typha    -> restart calico-typha + calico-node
#   3. Envoy data-plane lost its xDS  -> restart it so it reconnects
#
# NOTE: if WSL itself crashed (Windows error 0x8007274c), first run this on the
# Windows side, THEN run this script:   wsl --shutdown   (wait ~8s, reopen WSL)
#
# Usage:  bash mogambo-kubernetes/cluster/recover.sh
# Idempotent and safe to re-run.
# ---------------------------------------------------------------------------
set -uo pipefail

say() { echo; echo "=== $* ==="; }

say "1/5  restart kind node containers (fixes wedged apiserver port-proxy)"
if docker ps >/dev/null 2>&1; then
  docker restart mogambo-control-plane mogambo-worker mogambo-worker2 2>&1 || true
else
  echo "docker not reachable yet — if WSL just started, wait a few seconds and re-run."
fi

say "2/5  wait for the apiserver"
for i in $(seq 1 30); do
  if timeout 10 kubectl get --raw='/readyz' >/dev/null 2>&1 || timeout 10 kubectl get nodes >/dev/null 2>&1; then
    echo "apiserver up after ~$((i*5))s"; break
  fi
  sleep 5
done

say "3/5  refresh Calico (Typha endpoints + node token)"
kubectl -n calico-system rollout restart deploy/calico-typha 2>&1 | head -1 || true
kubectl -n calico-system rollout restart ds/calico-node   2>&1 | head -1 || true
echo "waiting up to 4 min for ALL calico-node pods to be Ready..."
for i in $(seq 1 48); do
  READY=$(kubectl get pods -n calico-system -l k8s-app=calico-node \
    -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c true)
  TOTAL=$(kubectl get pods -n calico-system -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l)
  echo "  t=$((i*5))s  calico-node ready=$READY/$TOTAL"
  if [ "$TOTAL" -ge 3 ] && [ "$READY" = "$TOTAL" ]; then echo "  ALL calico-node READY"; break; fi
  # a single stuck node (usually control-plane) recovers faster with a kick
  if [ "$i" = "24" ]; then
    STUCK=$(kubectl get pods -n calico-system -l k8s-app=calico-node \
      -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
    [ -n "$STUCK" ] && { echo "  kicking stuck calico-node $STUCK"; kubectl delete pod "$STUCK" -n calico-system --grace-period=5 2>/dev/null || true; }
  fi
  sleep 5
done

say "4/5  clear stuck Terminating/Pending pods + restart Envoy data-plane"
# force-delete any pods stuck from the outage (sandbox couldn't be created/destroyed)
kubectl get pods -A 2>/dev/null | awk '/Terminating|Pending/{print $1" "$2}' | while read -r ns pod; do
  [ -n "$pod" ] && kubectl delete pod "$pod" -n "$ns" --grace-period=0 --force 2>/dev/null | head -1
done
kubectl delete pod -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=mogambo --grace-period=5 2>&1 | head -1 || true
echo "waiting up to 2 min for Envoy data-plane Ready..."
for i in $(seq 1 24); do
  R=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=mogambo \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  echo "  t=$((i*5))s  envoy ready=$R"
  [ "$R" = "true" ] && break
  sleep 5
done

say "5/5  verify gateway routing (host :8090)"
timeout 12 curl -s -o /dev/null -w "  frontend: %{http_code}\n" -H "Host: mogambo.localtest.me"  http://localhost:8090/          2>&1 || true
timeout 12 curl -s -o /dev/null -w "  grafana:  %{http_code}\n" -H "Host: grafana.localtest.me"  http://localhost:8090/api/health 2>&1 || true

say "done"
echo "If both returned 200, the cluster is back. (000/503 => re-run once; still failing => check 'kubectl get pods -A'.)"
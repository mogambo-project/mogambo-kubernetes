# Monitoring — Prometheus + Grafana (kube-prometheus-stack)

The real monitoring stack runs **in the cluster** (Prometheus scrapes & stores metrics; Grafana
visualises them). Grafana is the dashboard UI — a Headlamp "Prometheus plugin" is only an optional
*viewer* on top of this same Prometheus, not a replacement.

Installed via `kube-prometheus-stack` (Prometheus + Grafana + node-exporter + kube-state-metrics +
prometheus-operator), **trimmed** for this memory-limited kind/WSL cluster — see [values.yaml](./values.yaml)
(no Alertmanager, 6h retention, single replicas, capped RAM).

## Install

```bash
./monitoring/install.sh                         # Helm, pinned chart 88.2.0, namespace `monitoring`
kubectl apply -f monitoring/grafana-route.yaml  # expose Grafana via the shared Gateway
```

Prerequisite: the Gateway allow-lists the `monitoring` namespace
(`allowedRoutes` selector in [../gateway/10-gateway.yaml](../gateway/10-gateway.yaml)).

## Use it

**Grafana:** http://grafana.localtest.me:8090/  — login `admin` / `admin`.
Ships prebuilt Kubernetes dashboards (nodes, pods, workloads, API server, etc.). Explore under
Dashboards → Browse.

**Prometheus** (query/debug) — no route by default; port-forward when needed:
```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
# then http://localhost:9090  (try a query: sum(rate(container_cpu_usage_seconds_total[5m])) by (pod))
```

## Notes

- Storage is **ephemeral** (emptyDir, 6h retention) — metrics reset on Prometheus restart. Fine for
  a local dev cluster; add a PVC + longer retention if you want history.
- To monitor the mogambo apps specifically, add a `ServiceMonitor` (carts already exposes Prometheus
  metrics; catalogue/frontend expose `/metrics`).
- Optional next step: the **Headlamp Prometheus plugin** points at
  `monitoring-kube-prometheus-prometheus:9090` to show inline charts inside Headlamp.

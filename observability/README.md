# Observability — Logs & Traces (pillars 2 & 3)

mogambo already has **metrics** (Prometheus + Grafana in the `monitoring` namespace).
This directory adds the other two observability pillars, everything living in the
`observability` namespace and surfacing in the **same Grafana UI**:

| Pillar | Backend | Collector / Source | App changes |
|--------|---------|--------------------|-------------|
| Logs   | **Loki**  | **Alloy** (Deployment, tails pod stdout/stderr via the k8s API) | none |
| Traces | **Tempo** | **OTel Operator** auto-instrumentation (carts, frontend) + **Envoy** edge tracing | none (pod annotation) |

## Why these choices
- **Stay in the Grafana/LGTM stack** → one UI, and metrics⇄logs⇄traces correlation for free.
- **No application code changes**: Alloy reads logs at the node level; the OpenTelemetry Operator
  injects language agents (Java/Node) via a pod annotation; Envoy traces the edge.
- **Tiny footprint** for a memory-limited kind/WSL cluster: single-binary/monolithic modes,
  local-path/emptyDir storage, short (72h) retention. Agents and Envoy push OTLP straight into
  Tempo's built-in receiver (no separate collector).

> **Why not Beyla (eBPF)?** We tried it first — it's the zero-annotation option and covers Go —
> but the **WSL2 kernel lacks the `security_socket_accept` kprobe** it needs, so it attaches but
> exports nothing. The OTel Operator (userspace agents) is the WSL2-friendly path. Trade-off:
> it covers **carts (Java)** and **frontend (Node)** with rich in-service spans; **catalogue (Go)**
> can't be auto-instrumented without a code change, but still appears as a call target in the tree.

## Install
```bash
cd mogambo-kubernetes
bash observability/install.sh
kubectl apply -f gateway/05-envoyproxy.yaml   # enables Envoy edge tracing
```
`install.sh` installs Loki, Alloy, Tempo, Beyla, and registers the Grafana datasources.

## Use it (in Grafana → Explore)
- **Logs**: pick the **Loki** datasource, query e.g. `{namespace="mogambo", app="carts"}`.
- **Traces**: pick the **Tempo** datasource, search by service; open a trace to see the span tree.
- **Correlation**: a trace span has a "Logs for this span" link (Tempo→Loki); a log line with a
  trace id becomes a clickable link to the trace (Loki→Tempo).

## Files
| File | What |
|------|------|
| `00-namespace.yaml`       | the `observability` namespace |
| `loki-values.yaml`        | Loki, SingleBinary + small local-path PVC, 72h retention |
| `alloy-values.yaml`       | Alloy DaemonSet + River pipeline (pods → labels → Loki) |
| `tempo-values.yaml`       | Tempo monolithic + OTLP receivers (:4317 gRPC / :4318 HTTP) |
| `otel-operator-values.yaml`| OpenTelemetry Operator (self-signed webhook certs, no cert-manager) |
| `instrumentation.yaml`    | Instrumentation CR — agents export to Tempo, W3C context propagation |
| `grafana-datasources.yaml`| Loki + Tempo datasources (sidecar-loaded ConfigMaps, `monitoring` ns) |
| `install.sh`              | installs all of the above, idempotent |

Envoy edge tracing lives in `../gateway/05-envoyproxy.yaml` (a `telemetry.tracing` block).

## Notes / good-practice next steps (optional, need app changes)
- **Structured JSON logs** per service → richer, queryable log fields in Loki.
- **catalogue (Go)** has no auto-instrumentation agent (Beyla's eBPF path can't run on the WSL2
  kernel) — add the OTel Go SDK in code for its own spans; today it appears as a call target.
- In production you'd front Tempo with an **OpenTelemetry Collector** (buffering/processing)
  and use object storage with longer retention instead of local disk.
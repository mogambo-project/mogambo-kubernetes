# Gateway API (Envoy Gateway) — frontend edge

The frontend is exposed with the **Gateway API**, implemented by **Envoy Gateway**. This replaces the
old NGINX **Ingress** (which lived in `../ingress/`, now removed). Same job — get external HTTP to the
`frontend` Service — but expressed as typed, role-separated resources instead of annotation-laden Ingress.

## The three resources (and who owns them)

| File | Kind | Role | Analogue in Ingress world |
|------|------|------|---------------------------|
| `00-gatewayclass.yaml` | `GatewayClass eg` | which controller (Envoy Gateway) | `IngressClass nginx` |
| `05-envoyproxy.yaml`   | `EnvoyProxy custom-proxy` | data-plane customisation (kind hostPort) | — (controller install flags) |
| `10-gateway.yaml`      | `Gateway mogambo` | the listener (port/proto/TLS) — platform role | the ingress-nginx *controller* |
| `20-frontend-route.yaml` | `HTTPRoute frontend` | routing rules host/path→Service — app role | the `Ingress` object |

Creating the **Gateway** makes Envoy Gateway provision a dedicated **Envoy data plane**
(a Deployment + Service named `envoy-mogambo-mogambo-*`) in the `envoy-gateway-system` namespace.

## Install + apply

```bash
./gateway/install.sh                 # Envoy Gateway controller (Helm, pinned v1.8.3)
kubectl apply -f gateway/            # GatewayClass + Gateway + HTTPRoute
```

Prerequisite: the **Gateway API CRDs** must be present (`kubectl get crd | grep gateway.networking.k8s.io`).
They're bundled by the Envoy Gateway chart, so `install.sh` covers a from-scratch cluster.

## Reach it — stable `http://mogambo.localtest.me:8090/`

`*.localtest.me` resolves to `127.0.0.1`, and the kind cluster maps host **`:8090` → control-plane
node `:80`** (see [../cluster/kind-config.yaml](../cluster/kind-config.yaml)). The `EnvoyProxy` in
`05-envoyproxy.yaml` pins the Envoy data plane onto the control-plane node and binds **`hostPort 80`**,
so that mapping reaches Envoy directly:

```
browser :8090 → node :80 (hostPort) → Envoy :10080 → HTTPRoute → frontend
```

No cloud-provider-kind, no port-forward, no ephemeral ports:

```bash
curl http://mogambo.localtest.me:8090/            # -> 200, Mogambo HTML
# browser: http://mogambo.localtest.me:8090/
```

Because the Envoy Service is `ClusterIP` (not `LoadBalancer`), a LB provider isn't needed — this is
why `05-envoyproxy.yaml` sets `envoyService.type: ClusterIP`.

## Verify / inspect

```bash
kubectl get gateway,httproute -n mogambo                     # Gateway PROGRAMMED=True
kubectl describe httproute frontend -n mogambo               # conditions: Accepted, ResolvedRefs
kubectl get pod -n envoy-gateway-system -o wide \
  -l gateway.envoyproxy.io/owning-gateway-name=mogambo       # should be on mogambo-control-plane
```

If `:8090` stops working: check the Envoy pod is `Running` **on the control-plane node** (only that
node has the `ingress-ready` label + the `8090→80` mapping). `PROGRAMMED=False` here would mean the
`EnvoyProxy`/GatewayClass `parametersRef` isn't resolving.

## Why Gateway API over Ingress (the point of the migration)

- **Typed fields, not annotations** — header/path matching, redirects, and **traffic weights** (canary)
  are validated spec fields, not `nginx.ingress.kubernetes.io/...` strings.
- **Role separation** — platform owns the `Gateway` (ports/TLS), app owns the `HTTPRoute`.
- **Portability** — the `Gateway` + `HTTPRoute` are implementation-agnostic; switching from Envoy
  Gateway to NGINX Gateway Fabric / Istio means changing only `GatewayClass.spec.controllerName`.
- **Future-proof** — `ingress-nginx` is retiring; Gateway API is the project's chosen successor.

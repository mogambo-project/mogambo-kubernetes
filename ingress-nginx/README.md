# ingress-nginx controller

The single external entry point for the cluster. It is **shared infrastructure** (like CoreDNS),
lives in its own `ingress-nginx` namespace, and serves Ingress objects in **all** namespaces —
not just `mogambo`. There is **one controller per cluster**, not one per app or namespace.

It is installed with **Helm**, which is why it never appeared in `manifests/` before: Helm applies
objects straight into the cluster, it doesn't write files into the repo. This directory closes that
gap so the controller is reproducible from source.

## Install / update

```bash
./install.sh          # helm upgrade --install, pinned chart 4.15.1, values.yaml overrides
```

Prerequisite: the cluster must expose host ports and label a node — both come from
[../cluster/kind-config.yaml](../cluster/kind-config.yaml):
- node label `ingress-ready=true` (control-plane)
- `extraPortMappings`: containerPort `80 -> hostPort 8090`, `443 -> 8443`

## How it connects (the 5 links)

1. **Helm -> API server** renders the chart and applies: controller Deployment, Services,
   ServiceAccount + ClusterRole/Binding, the `nginx` **IngressClass**, and an admission webhook.
2. **Controller -> node**: `nodeSelector: ingress-ready=true` + control-plane toleration pin the
   pod onto the control-plane node.
3. **Controller -> node ports**: `hostPort.enabled` binds the node's `:80` / `:443` directly.
4. **Node -> host**: kind's `extraPortMappings` map node `:80 -> host :8090`, `:443 -> :8443`.
   This is the bridge from Windows/WSL into the cluster.
5. **Controller -> API (ongoing)**: via its ServiceAccount RBAC it watches Ingress objects
   cluster-wide and rewrites NGINX config on every change; the admission webhook validates them.

Request path:

```
browser :8090  ->  (kind mapping) node :80  ->  controller hostPort 80
              ->  NGINX matches Host header  ->  Service  ->  pod :8079
```

An Ingress object is tied to this controller by `ingressClassName: nginx`
(see [../ingress/frontend-ingress.yaml](../ingress/frontend-ingress.yaml)).

## Note

`ingress-nginx` is entering retirement (community direction: **Gateway API**), and had the 2025
"IngressNightmare" CVEs — keep the chart version patched, and treat this as the stepping stone
before migrating to Gateway API.

# Headlamp — local web console

A free, open-source (CNCF) web UI to browse/edit/manage the cluster — the lightweight stand-in for a
cloud console. Served through the shared Envoy Gateway at **http://headlamp.localtest.me:8090/**.

## Install

```bash
./headlamp/install.sh          # Helm, pinned chart 0.44.0, namespace `headlamp`
kubectl apply -f headlamp/     # admin ServiceAccount + token + HTTPRoute
```

Prerequisite: the shared `mogambo` Gateway must allow this namespace to attach routes — its
`allowedRoutes.namespaces` uses a `Selector` allow-listing `mogambo` + `headlamp`
(see [../gateway/10-gateway.yaml](../gateway/10-gateway.yaml)). To expose another UI, add its
namespace to that list.

## Log in

Headlamp asks for a bearer token and then acts in the API **as that token** (so RBAC = what you can
edit). Get the stable cluster-admin token:

```bash
kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d; echo
```

Open **http://headlamp.localtest.me:8090/**, choose the cluster, paste the token.

## Notes

- The token is **cluster-admin** — fine for a local single-user cluster reachable only on localhost;
  don't expose the Gateway externally with this in place.
- Footprint is small (~150 MB), unlike Rancher — chosen deliberately for this memory-limited kind/WSL cluster.
- Same edit/logs/exec capabilities as `k9s`, but in a browser.

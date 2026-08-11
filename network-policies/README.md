# NetworkPolicies — zero-trust pod networking

Default-deny ingress for the `mogambo` namespace, then each service re-opens only the traffic it needs.
This is the network-layer complement to the per-app ServiceAccounts and least-privilege RBAC already in
the project.

## ⚠️ Requires a policy-enforcing CNI (Calico)

NetworkPolicy objects are **inert** unless the CNI enforces them. kind's default **kindnet does NOT
enforce** them (it silently accepts the objects). This project therefore runs **Calico** — see
[../calico/](../calico/) and `disableDefaultCNI: true` in [../cluster/kind-config.yaml](../cluster/kind-config.yaml).
On plain kindnet these files apply cleanly but block nothing.

## The rules

| Policy | Target | Allows ingress from | Port |
|--------|--------|---------------------|------|
| `default-deny-ingress` | all pods | (nothing) | — |
| `allow-frontend`    | frontend    | `envoy-gateway-system` namespace (the Gateway) | 8079 |
| `allow-catalogue`   | catalogue   | `app=frontend` | 8081 |
| `allow-carts`       | carts       | `app=frontend` | 80 |
| `allow-catalogue-db`| catalogue-db| `app=catalogue` | 3306 |
| `allow-carts-db`    | carts-db    | `app=carts` | 27017 |

Net effect: the DBs are reachable **only** from their own app, the app tier only from the frontend,
and the frontend only from the Gateway. Everything else is denied.

**Egress is intentionally left open** — so DNS (to kube-dns) and outbound calls keep working without
an egress allow-list. Access is controlled at each destination's *ingress* instead, which is enough to
enforce "only catalogue can call catalogue-db" (the block happens at catalogue-db's ingress).

## Probes

Only `frontend`, `catalogue`, `carts`, and `carts-db` have **network** probes (kubelet → pod);
`catalogue-db` uses an exec probe (unaffected). Under default-deny these could break if the CNI
dropped kubelet traffic — but **Calico permits host/kubelet health checks by default**, so no extra
"allow from node" rule is needed. Verified: all pods stayed `1/1 Ready` after applying.

## Verify

```bash
# BLOCKED: a pod that isn't catalogue cannot reach catalogue-db
kubectl run t --rm -i --image=busybox -n mogambo --labels app=nettest -- \
  sh -c 'nc -w5 catalogue-db 3306; echo exit=$?'      # exit=1 (blocked)

# ALLOWED: the real path still works (frontend -> catalogue -> catalogue-db)
kubectl run t --rm -i --image=curlimages/curl -n mogambo --labels app=frontend -- \
  sh -c 'curl -s http://catalogue/catalogue | grep -o "\"id\"" | wc -l'   # 9
```

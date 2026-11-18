# mogambo — app delivery & cluster bootstrap

The **application-CD** and **cluster-bootstrap** repo for mogambo (a sock-shop-style microservices
demo on a local **kind** cluster in WSL). Everything is GitOps: Argo CD watches Git and reconciles
the cluster — no hand-run `kubectl apply`.

The project spans three repos, stitched together at runtime by Argo CD:

| Repo | Role | Argo CD reads it as |
|---|---|---|
| **this repo** (`mogambo-kubernetes`) | app units + Argo CD core + the bootstrap | Git (`master`) |
| [`mogambo-platform`](https://github.com/mogambo-project/mogambo-platform) | the shared platform tools (gateway, monitoring, observability, Headlamp, network policies) | Git (`master`) |
| [`mogambo-charts`](https://github.com/mogambo-project/mogambo-charts) | the one shared Helm chart for every app/DB | **OCI artifact** (`app:0.1.0-N`, pinned by `CHART_VERSION`) |

## What's in this repo

| Path | What |
|---|---|
| `values-*/` | one folder per app/DB **unit** — the deployable units. The ApplicationSet turns each into an Argo CD Application; the CMP renders it from the OCI chart (decrypting its `secrets.yaml`). |
| `bootstrap/` | the **umbrella chart** — one `helm install` brings up Argo CD + the root app-of-apps + the infra app-of-apps + Argo CD self-management. |
| `argocd/` | Argo CD core: the **ApplicationSet** (app units), the **CMP** config (OCI chart + SOPS → `helm template`), the UI route. |
| `calico/` | the **CNI** (Tigera operator, Helm) — day-0, since the cluster needs a CNI before Argo CD can run. |
| `cluster/`, `namespaces/` | kind config, recovery script, namespaces. |

## Bring it all up (clean cluster)

```bash
# 1) cluster — Calico CNI (disableDefaultCNI), host ports 8090/8443 -> 80/443
kind create cluster --config cluster/kind-config.yaml

# 2) CNI — nodes stay NotReady until this runs
./calico/install.sh

# 3) the age key that DECRYPTS the SOPS secrets (NOT in Git — it's the key to the Git secrets)
kubectl create namespace argocd
kubectl -n argocd create secret generic sops-age --from-file=keys.txt=<path-to-your-age-key>

# 4) THE one door — installs Argo CD and plants everything
helm dependency build bootstrap/
helm install mogambo bootstrap/ -n argocd --create-namespace
```

From here **Argo CD takes over**: it generates the app units (this repo, rendered from the OCI chart
with SOPS secrets decrypted) and pulls the platform tools (`mogambo-platform`). Nothing else is run
by hand. Watch it fill in at **http://argocd.localtest.me:8090/** — see
[argocd/README.md](./argocd/README.md) for the login and the self-management details.

## The GitOps loop (everyday use)

1. **An app change** → edit a `values-*/values.yaml` (image tag, env, scaling), or bump
   `CHART_VERSION` in [argocd/applicationset.yaml](./argocd/applicationset.yaml) to roll onto a new
   chart. Push.
2. **A platform change** → edit the tool in `mogambo-platform` (bump an upstream chart version, tweak
   values). Push.
3. Argo CD auto-syncs either one. `git revert` = rollback.

## Reach the app

**http://mogambo.localtest.me:8090/** — stable hostPort binding through the Envoy gateway (no
cloud-provider-kind, no port-forward). The gateway itself lives in `mogambo-platform/gateway/`.

## Notes

- **Day-0 prerequisite** (not GitOps-managed): the CNI (**Calico**) — intentionally, since it must
  precede Argo CD. **metrics-server** and the **VPA controller** are now GitOps-managed in
  `mogambo-platform` (`metrics-server/`, `vpa/`), so they come up with everything else — no hand-install.
- **Migrating a cluster that already has these installed** the old way: the Applications adopt the
  existing Helm releases (names are matched), but a clean rebuild is simplest on a disposable kind
  cluster.
- Recurring kind/WSL **CNI token staleness** (pods `Pending`, `calico ... Unauthorized`) →
  `bash cluster/recover.sh`.

## Daily commands

```bash
kubectl get nodes                 # 3 nodes Ready
kubectl get applications -n argocd # what Argo CD is managing (apps + platform tools)
kubectl get pods -A               # everything, everywhere
kubectl top nodes                 # needs metrics-server
```

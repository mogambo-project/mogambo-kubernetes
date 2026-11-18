# Argo CD — the mogambo control plane

Git is the source of truth. Argo CD watches this repo and keeps the cluster matching it — no
hand-run `kubectl apply`, no remembering a script order. Served through the shared Envoy gateway
at **http://argocd.localtest.me:8090/**.

## Bring the whole platform up (the only thing a human runs)

```bash
# 1. The decryption key — once, and NOT in Git (it's the key that decrypts the Git secrets).
kubectl create namespace argocd
kubectl -n argocd create secret generic sops-age --from-file=keys.txt=<path-to-your-age-key>

# 2. The one door: installs Argo CD + plants everything else.
helm dependency build bootstrap/
helm install mogambo bootstrap/ -n argocd --create-namespace
```

That's it. `helm install` creates Argo CD, then Argo CD pulls the rest from Git on its own.

## What one install sets in motion

```
helm install bootstrap/            ← the only imperative step (plus the age secret)
   ├─ Argo CD                      ← the argo-cd subchart (config: bootstrap/values.yaml, argo-cd: key)
   ├─ Application "argocd"         ← Argo CD MANAGES ITSELF from here on (bootstrap/templates/argocd-selfmanage.yaml)
   └─ Application "mogambo-root"   ← app-of-apps (bootstrap/templates/root-app.yaml), which applies:
         ├─ applicationset.yaml    ← one Application per values-*/ unit (the apps + DBs)
         ├─ cmp-plugin.yaml        ← how units render (pull OCI chart → sops-decrypt → helm template)
         ├─ 10-route.yaml          ← this UI's HTTPRoute
         └─ 21-app-netpol.yaml     ← the NetworkPolicies app
```

Everything in this `argocd/` folder is now **reconciled by `mogambo-root`** — edit a file, push, it
auto-applies. The only place the control plane itself is configured is **`bootstrap/values.yaml`**.

## Argo CD manages itself

The `argocd` Application points back at the `bootstrap/` chart (same chart, same values), so after the
one-time install you **never run `helm upgrade` by hand again**. To upgrade or re-tune Argo CD: bump
the `argo-cd` version in [`bootstrap/Chart.yaml`](../bootstrap/Chart.yaml) or edit
[`bootstrap/values.yaml`](../bootstrap/values.yaml), push, and Argo CD rolls the change onto itself.

> The first sync "adopts" the objects `helm install` created (a one-time, harmless re-label), after
> which Argo CD is the sole owner.

## Log in

- URL: **http://argocd.localtest.me:8090/**  ·  user: **admin**
- Password:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```

## Everyday use (the GitOps loop)

1. Edit a unit's `values-*/values.yaml` (or a core file here), commit, **push to `origin/master`**.
2. Argo CD detects it and **auto-syncs** (or click **Sync** in the UI). `git revert` = rollback.

## Infra tools — the separate `mogambo-platform` repo

A second app-of-apps, **`mogambo-infra`** (planted by the bootstrap), watches the **separate
[mogambo-platform](https://github.com/mogambo-project/mogambo-platform) repo** and applies every
Application it discovers by the convention `<tool>/app/*.yaml`. The platform tools are owned apart
from this app-CD repo (the platform-team model); Argo CD stitches the two repos together at runtime.

| Tool | Where |
|---|---|
| Gateway · Monitoring · Observability · Headlamp · NetworkPolicies | **`mogambo-platform`** → `<tool>/app/*.yaml` |
| **Calico** — cluster CNI | stays **here**, day-0: the cluster needs a CNI *before* ArgoCD can run (`calico/install.sh`) |

## Gotchas specific to this cluster

- **Migrating a cluster that already has Argo CD** (installed by the old `install.sh`, release
  `argocd`): a fresh `helm install mogambo bootstrap/` will collide with the existing release. Either
  bring the bootstrap up on the next clean cluster, or migrate deliberately
  (`helm upgrade argocd bootstrap/ -n argocd` adopting the existing objects). On a disposable
  kind/WSL cluster the clean-rebuild path is simplest.
- If Argo CD pods are stuck `Pending` with `calico ... Unauthorized`, it's the recurring CNI-token
  staleness — run `bash cluster/recover.sh` (or `kubectl -n calico-system rollout restart ds/calico-node`).

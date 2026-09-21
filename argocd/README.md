# Argo CD — GitOps for mogambo

Git is the source of truth. Argo CD watches this repo and keeps the cluster matching it —
no more hand-running `kubectl apply`. Served through the shared Envoy gateway at
**http://argocd.localtest.me:8090/**.

## What Argo manages here
The **`mogambo-apps`** Application ([20-app-mogambo.yaml](20-app-mogambo.yaml)) tracks the
**`manifests/`** path on `origin/master` and reconciles it into the `mogambo` namespace:
- `automated.selfHeal: true` — a manual `kubectl` edit to a managed resource is reverted to Git.
- `automated.prune: false` — Argo won't *delete* resources you remove from Git (safe default;
  flip to `true` for full GitOps once trusted).
- `ignoreDifferences: /spec/replicas` on Deployments — the **HPAs** own replica counts, so Argo
  never fights them.

> Only the plain-YAML **app layer** (`manifests/`) is under GitOps. The Helm-installed infra
> (monitoring, observability, gateway, calico, headlamp, argocd itself) stays on its `install.sh`
> scripts — wrap each as its own Argo `Application` later if you want everything GitOps-managed.

## Install
```bash
bash argocd/install.sh
```
Installs Argo CD (trimmed: no Dex/SSO, ApplicationSet, notifications; server runs `--insecure`
behind the gateway), allow-lists the `argocd` namespace on the gateway, exposes the UI, and
registers the Application. Prints the admin password at the end.

## Log in
- URL: **http://argocd.localtest.me:8090/**  ·  user: **admin**
- Password:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```

## Everyday use (the GitOps loop)
1. Edit a manifest under `manifests/`, commit, **push to `origin/master`**.
2. Argo detects the change and **auto-syncs** it to the cluster (or click **Sync** in the UI).
3. `git revert` = rollback.

Try self-heal: `kubectl -n mogambo set env deploy/session-db DEMO=drift` → Argo reverts it within
a minute (it's not in Git). 

## Gotchas specific to this cluster
- If Argo pods are stuck `Pending` with `calico ... Unauthorized`, it's the recurring CNI-token
  staleness — run `bash cluster/recover.sh` (or `kubectl -n calico-system rollout restart ds/calico-node`).
- Because resources were first created by hand, the first sync **adopts** them (adds Argo's
  tracking label) — a one-time rollout, harmless.
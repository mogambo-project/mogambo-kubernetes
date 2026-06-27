# Mogambo on Kubernetes — iteration 1

The Mogambo app reimplemented as plain Kubernetes manifests. Goal of this iteration: **make it run**. No Helm, no HPA, no PVC, no probes yet — those come later.

## Architecture

```
                        ┌─────────────────────┐
                  ┌────►│ catalogue (ClusterIP)├──────► catalogue-db (ClusterIP, MySQL)
                  │     └─────────────────────┘
   ExternalIP     │
   ─────────► frontend (LoadBalancer)
                  │     ┌─────────────────────┐
                  └────►│  carts (ClusterIP)  ├──────► carts-db   (ClusterIP, MongoDB)
                        └─────────────────────┘
```

All five services live in the `mogambo` namespace. Frontend is the only externally reachable one.

## Apply

```bash
cd ~/mogambo-project/mogambo-kubernetes
kubectl apply -f namespaces/
kubectl apply -f manifests/
kubectl apply -f hpa/
kubectl apply -f vpa/
kubectl apply -f rbac/
for f in secrets/*-secret.yaml; do
  sops -d "$f" | kubectl apply -f -
done
kubectl get pods,svc -n mogambo

# verify the RBAC took effect (acts AS the jenkins-deployer ServiceAccount):
kubectl auth can-i patch deployments -n mogambo \
  --as=system:serviceaccount:mogambo:jenkins-deployer   # -> yes
kubectl auth can-i get secrets -n mogambo \
  --as=system:serviceaccount:mogambo:jenkins-deployer   # -> no
```

Expect:
- All 4 Deployments at `1/1 Ready`
- `catalogue-db`, `catalogue`, `carts`, and `carts-db` Services as `ClusterIP`
- `frontend` Service with `EXTERNAL-IP` set (filled in by cloud-provider-kind within ~30s)

## Pod identity & least privilege (ServiceAccounts)

Each app runs under its **own ServiceAccount** with **zero API permissions** and **no API token
mounted** — the `ServiceAccount` is defined at the bottom of each app's own `*.yaml` (after its
Service) and wired into the Deployment via `serviceAccountName` + `automountServiceAccountToken: false`.

- The apps (Go/Node/Java/MySQL/Mongo) never call the Kubernetes API, so the auto-mounted token under
  `/var/run/secrets/kubernetes.io/serviceaccount` is only attack surface — removing it means a
  compromised pod holds **no cluster credential**.
- A dedicated identity per app means any *future* permission is granted precisely to that app's SA
  (not the shared `default`, which would leak to **every** pod), and audit logs show which app acted.

Verify the token is gone:
```bash
POD=$(kubectl -n mogambo get pod -l app=catalogue -o jsonpath='{.items[0].metadata.name}')
kubectl -n mogambo get pod "$POD" \
  -o jsonpath='SA={.spec.serviceAccountName} volumes={.spec.volumes[*].name}{"\n"}'
# SA=catalogue volumes=          <-- no "kube-api-access-*" volume = no token mounted
```

Defense in depth: the "automountServiceAccountToken: false" is also set on each pod template 
(the pod-level setting is authoritative; the SA-level setting keeps the SA safe-by-default
for any future pod).

## Reach the frontend

The Service shows an ExternalIP from the kind docker network (e.g. `172.21.0.5`). On WSL2 that IP isn't directly routable — instead, use the **host port** that cloud-provider-kind's envoy proxy publishes:

```bash
# Find the LB's host port (ephemeral, e.g. 61832)
docker ps --filter "ancestor=envoyproxy/envoy:v1.33.2" --format '{{.Names}}\t{{.Ports}}'

# Then:
curl http://localhost:<that-port>/
# Or in your Windows browser:  http://localhost:<that-port>/
```

One-liner that grabs the port and curls:
```bash
PORT=$(docker ps --filter "ancestor=envoyproxy/envoy:v1.33.2" --format '{{.Ports}}' | grep -oE '0\.0\.0\.0:[0-9]+->80/tcp' | head -1 | cut -d: -f2 | cut -d- -f1)
echo "frontend at http://localhost:$PORT/" && curl -sS http://localhost:$PORT/ | head -5
```

If `EXTERNAL-IP` stays `<pending>`, cloud-provider-kind isn't running. Start it:
```bash
nohup ~/.local/bin/cloud-provider-kind > ~/.cpk.log 2>&1 &
disown
```

## Service-to-service DNS (inside the cluster)

| Caller | Target | URL |
|---|---|---|
| frontend  | catalogue    | `http://catalogue` |
| frontend  | carts        | `http://carts` |
| catalogue | catalogue-db | `catalogue-db:3306` (MySQL) |
| carts     | carts-db     | `mongodb://root:admin123@carts-db:27017/data?authSource=admin` |

(Full FQDN is `<svc>.mogambo.svc.cluster.local` but the short name works inside the same namespace.)

## Troubleshooting

```bash
kubectl get pods -n mogambo                     # status, restart count
kubectl describe pod <pod> -n mogambo           # READ the Events section at the bottom
kubectl logs deploy/<name> -n mogambo
kubectl logs deploy/<name> -n mogambo -f        # tail
stern -n mogambo .                              # tail every pod at once

# DNS check from inside the cluster:
kubectl run -it --rm dnstest -n mogambo --image=busybox --restart=Never -- \
  nslookup catalogue

# What MySQL sees (creds may need to come from your image's docs):
kubectl exec -it deploy/catalogue-db -n mogambo -- mysql -uroot -p
```

## Likely first failures and fixes

| Symptom | Probable cause | Fix |
|---|---|---|
| `ImagePullBackOff` | Image name wrong, e.g. `front-end` vs `frontend` | Edit the `image:` field in [40-frontend.yaml](./40-frontend.yaml) (or the file for the failing service) |
| Pod up but `curl` fails | App's bind address is `127.0.0.1`, not `0.0.0.0` | App must listen on all interfaces — fix in app code |
| catalogue `CrashLoopBackOff`, "can't connect to DB" | App expects a config env var | Uncomment the `env:` block in [20-catalogue.yaml](./20-catalogue.yaml) |
| catalogue-db `CrashLoopBackOff`, "Database not initialized" | Custom image needs `MYSQL_ROOT_PASSWORD` | Uncomment the `env:` block in [10-catalogue-db.yaml](./10-catalogue-db.yaml) |
| `EXTERNAL-IP <pending>` forever | cloud-provider-kind not running | See "Reach the frontend" above |
| `EXTERNAL-IP` set but `curl` hangs | cloud-provider-kind LB container can't bind host port 80 (taken by `setup-frontend-1`) | Curl the LB container's mapped port (`docker ps` shows it) — see below |

If host port 80 is taken, cloud-provider-kind picks a free host port. Find it with:
```bash
docker ps --filter "ancestor=envoyproxy/envoy" --format "table {{.Names}}\t{{.Ports}}"
```

## What's next (don't do yet — wait for the prompt)

- **Helm chart** — replace these 5 nearly-identical YAMLs with one templated chart in `../charts/mogambo/`
- **Image tag pinning** — replace `:latest` with `:v1.0.0`, set `imagePullPolicy: IfNotPresent`
- **Probes** — readiness/liveness so k8s knows when each service is ready
- **Resource tuning** — adjust requests/limits based on `kubectl top pods -n mogambo`
- **Secrets and RBAC** — move DB passwords from `value:` literal to `valueFrom: secretKeyRef`
- **PVC and StatefulSet for databases** — currently data resets on pod restart
- **HPA** — auto-scale frontend, catalogue, carts based on CPU
- **NetworkPolicy** — e.g: only catalogue should be able to reach catalogue-db
- **Ingress** — add `mogambo.localtest.me:8090` as an alternative entry point and instead of LoadBalancer
- **Add GitOps**
- **Add Jenkins Jobs**

## Tear down

```bash
kubectl delete ns mogambo                       # cascades to all 4 deployments + LB
```
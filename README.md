# Local Kubernetes practice — crib sheet

Local k8s playground using **kind** (Kubernetes-in-Docker) on WSL Ubuntu. All binaries live in `~/.local/bin` (no sudo required).

## Cluster lifecycle

```bash
# create the multi-node cluster (1 control-plane + 2 workers, host ports 8090/8443 → cluster 80/443)
kind create cluster --config cluster/kind-config.yaml

# tear down
kind delete cluster --name practice

# list clusters
kind get clusters
```

## Daily commands

```bash
kubectl get nodes                       # 3 nodes Ready
kubectl get pods -A                     # everything everywhere
kubectl top nodes                       # needs metrics-server
kubectl config current-context          # which cluster am I on?

k9s                                     # TUI — ":pods", ":deploy", ":svc", ":ing", ":nodes"
kubens kube-system                      # switch default namespace
kubectx                                 # switch context (when you have multiple)
stern -n ingress-nginx ingress-nginx    # multi-pod log tail
```

## NGINX Ingress (already installed via Helm in `ingress-nginx` namespace)

```bash
helm list -n ingress-nginx
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller
```

Test it:
```bash
kubectl create deployment hello --image=nginx
kubectl expose deployment hello --port=80
kubectl create ingress hello --class=nginx --rule="hello.localtest.me/*=hello:80"
curl http://hello.localtest.me:8090         # browser also works
```
`*.localtest.me` resolves to `127.0.0.1` automatically — no `/etc/hosts` edits.

## Node management practice

```bash
kubectl get nodes -o wide
kubectl cordon practice-worker          # mark unschedulable
kubectl drain practice-worker --ignore-daemonsets --delete-emptydir-data
kubectl uncordon practice-worker
kubectl taint nodes practice-worker dedicated=team-a:NoSchedule
kubectl label nodes practice-worker tier=frontend
```

## Helm

```bash
helm repo list
helm search repo <name>
helm install <release> <chart> -n <ns> --create-namespace
helm upgrade <release> <chart> -n <ns>
helm uninstall <release> -n <ns>
helm list -A
```

Your own charts go in [charts/](./charts/), raw manifests in [manifests/](./manifests/).

## Reset everything

```bash
kind delete cluster --name practice && docker system prune -f
```

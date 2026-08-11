# Local Kubernetes practice — crib sheet

Local k8s playground using **kind** (Kubernetes-in-Docker) on WSL Ubuntu. All binaries live in `~/.local/bin` (no sudo required).

## Cluster lifecycle

```bash
# create the multi-node cluster (1 control-plane + 2 workers, host ports 8090/8443 → cluster 80/443)
kind create cluster --config cluster/kind-config.yaml

# tear down
kind delete cluster --name mogambo

# list clusters
kind get clusters
```

## Rebuild from scratch (ordered)

The whole stack is version-controlled, so a clean rebuild is these steps in order:

```bash
# 1) cluster — disableDefaultCNI (Calico instead of kindnet), host ports 8090/8443, ingress-ready label
kind create cluster --config cluster/kind-config.yaml

# 2) CNI — Calico (enforces NetworkPolicy). Nodes are NotReady until this runs.  (calico/)
./calico/install.sh

# 3) controllers (installed via Helm / manifests, not from this repo's kubectl apply):
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deploy metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
helm upgrade --install vpa fairwinds-stable/vpa --version 4.11.0 -n vpa --create-namespace --wait   # needs `helm repo add fairwinds-stable https://charts.fairwinds.com/stable`
./gateway/install.sh          # Envoy Gateway (Gateway API edge)

# 4) app — secrets BEFORE manifests (DB pods need their envFrom creds)
kubectl apply -f namespaces/
for f in secrets/*-secret.yaml; do sops -d "$f" | kubectl apply -f -; done
kubectl apply -f manifests/
kubectl apply -f gateway/
kubectl apply -f hpa/ -f vpa/ -f rbac/
kubectl apply -f network-policies/          # zero-trust ingress (enforced by Calico)
```

Then reach the app through the Gateway at **http://mogambo.localtest.me:8090/**
(stable hostPort binding — no cloud-provider-kind needed; see **[gateway/README.md](./gateway/README.md)**).

> **Note:** metrics-server + VPA are installed imperatively above (not yet folded into a single script).
> The CNI is now **Calico** (see [calico/](./calico/)) so **[network-policies/](./network-policies/)** are enforced.

## Daily commands

```bash
kubectl get nodes                       # 3 nodes Ready
kubectl get pods -A                     # everything everywhere
kubectl top nodes                       # needs metrics-server
kubectl config current-context          # which cluster am I on?

k9s                                     # TUI — ":pods", ":deploy", ":svc", ":ing", ":nodes"
kubens kube-system                      # switch default namespace
kubectx                                 # switch context (when you have multiple)
stern -n envoy-gateway-system .         # multi-pod log tail (gateway controller + data plane)
```

## Edge routing: Gateway API (Envoy Gateway)

The mogambo frontend is served via **Gateway API / Envoy Gateway** — see
**[gateway/README.md](./gateway/README.md)** for the full wiring and how to reach it.
(The earlier NGINX Ingress was migrated away and `ingress-nginx` uninstalled.)

```bash
helm list -n envoy-gateway-system
kubectl get gatewayclass,gateway,httproute -A
kubectl -n envoy-gateway-system get pods
```

`*.localtest.me` resolves to `127.0.0.1` automatically — no `/etc/hosts` edits.

## Node management practice

```bash
kubectl get nodes -o wide
kubectl cordon mogambo-worker          # mark unschedulable
kubectl drain mogambo-worker --ignore-daemonsets --delete-emptydir-data
kubectl uncordon mogambo-worker
kubectl taint nodes mogambo-worker dedicated=team-a:NoSchedule
kubectl label nodes mogambo-worker tier=frontend
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

## Secrets (SOPS + age) & Jenkins jobs

Encrypted Kubernetes Secrets live in [secrets/](./secrets/) and are managed with **SOPS + age**
(rules in [.sops.yaml](./.sops.yaml)). Two Jenkins jobs (`sops-encrypt`, `sops-decrypt`) wrap the
encrypt/decrypt workflow. Everything needed to reproduce them on another machine is version-controlled
under [jenkins/](./jenkins/) — see **[jenkins/README.md](./jenkins/README.md)** for the full walkthrough.

New developer, quick start:

```bash
# 1) install the CLI tools (Ubuntu/WSL)
sudo apt-get update && sudo apt-get install -y age
SOPS_VER=3.9.4
sudo curl -fsSL -o /usr/local/bin/sops \
  "https://github.com/getsops/sops/releases/download/v${SOPS_VER}/sops-v${SOPS_VER}.linux.$(dpkg --print-architecture)"
sudo chmod +x /usr/local/bin/sops

# 2) get/generate your age key (decryption key)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt        # then add the printed public key to .sops.yaml recipients

# 3) start Jenkins + the stack (Jenkins image has sops/age baked in)
cd ../bootcamp/setup && docker compose up -d --build      # http://localhost:8080

# 4) add Jenkins credentials: github-token (Secret text), sops-age-key (Secret file)  [see jenkins/README.md]
# 5) create the jobs
cd ../../mogambo-kubernetes && ./jenkins/install-jobs.sh
```

Encrypt / decrypt by hand:
```bash
sops --encrypt --in-place secrets/<name>-secret.yaml      # encrypt (needs only the public recipient)
sops -d secrets/<name>-secret.yaml | kubectl apply -f -    # decrypt straight into the cluster (needs the age key)
```

## Reset everything

```bash
kind delete cluster --name mogambo && docker system prune -f
```

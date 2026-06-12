# Homelab k3s Platform

This repository bootstraps and manages the `optiplex5060` k3s homelab platform.
It includes Argo CD, global Dex authentication, Traefik ingress, GlusterFS-backed
JuiceFS storage, Kyverno policy automation, Gitea with Actions, Kubeflow, and
OpenSandbox.

See [DESIGN.md](DESIGN.md) for the architecture and operational model.

## What Is Included

- Argo CD GitOps root application.
- k3s Traefik ingress for `auth`, `argo`, and `kubeflow` hostnames.
- Global Dex in the `identity` namespace with local users and GitHub OAuth.
- Kyverno syncing the wildcard TLS Secret to Ingress namespaces.
- Kubeflow using the global Dex through `oauth2-proxy`.
- Gitea using the global Dex as an OpenID Connect login source.
- Gitea Actions runner with Docker-in-Docker for CI jobs.
- OpenSandbox controller/server for creating Kubernetes-backed sandboxes.
- `/dev/sda` host storage mounted at `/srv/k3s-data`.
- GlusterFS volume `gv0` as the local storage backend.
- Host Valkey/Redis metadata for JuiceFS.
- JuiceFS CSI `juicefs-sc` StorageClass.

## Repository Layout

```text
clusters/optiplex5060/bootstrap  One-time Argo CD bootstrap manifests
clusters/optiplex5060/apps       Argo CD root application children
platform/auth                    Global Dex
platform/ingress                 Edge ingress resources
platform/network                 Tailscale and Cilium host-network guard
platform/storage                 JuiceFS CSI and StorageClass
platform/kyverno-policies        TLS Secret sync policy
platform/kubeflow                Kubeflow upstream Application and auth patches
clusters/optiplex5060/apps       Includes Gitea and Gitea Actions Helm apps
scripts                          Host prep, rendering, and bootstrap scripts
docs                             Operational notes
```

## Prerequisites

- Arch Linux host with k3s installed with flannel disabled.
- Cilium installed as the k3s CNI.
- `/dev/sda` available as disposable data disk.
- DNS records for:
  - `auth.<BASE_DOMAIN>`
  - `argo.<BASE_DOMAIN>`
  - `git.<BASE_DOMAIN>`
  - `kubeflow.<BASE_DOMAIN>`
  - `opensandbox.<BASE_DOMAIN>`
- GitHub OAuth app:
  - Homepage URL: `https://auth.<BASE_DOMAIN>`
  - Authorization callback URL: `https://auth.<BASE_DOMAIN>/callback`

## Quick Start

1. Install host tools:

   ```sh
   scripts/install-host-tools-arch.sh
   ```

   If you are doing a full cluster rebuild, you can run:

```sh
sudo scripts/redeploy-k3s.sh
```

Or run full sequence (single entrypoint):

```sh
sudo scripts/deploy-homelab-full.sh
```

If host disk prep is already done:

```sh
SKIP_HOST_STORAGE_PREP=1 sudo scripts/deploy-homelab-full.sh
```

2. Prepare `/dev/sda` and GlusterFS:

   ```sh
   sudo scripts/prepare-host-storage.sh --device /dev/sda --yes
   ```

3. Install the control-plane k3s server without flannel, then install Cilium:

   ```sh
   curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --node-ip 100.118.192.86 --node-external-ip 100.118.192.86 --advertise-address 100.118.192.86 --tls-san 100.118.192.86 --flannel-backend=none --disable-network-policy --disable local-storage --write-kubeconfig-mode 0644' sh -
   helm upgrade --install cilium cilium --repo https://helm.cilium.io --namespace kube-system --set k8sServiceHost=100.118.192.86 --set k8sServicePort=6443 --set ipam.mode=kubernetes --set operator.replicas=1 --set cni.confPath=/etc/cni/net.d --set cni.binPath=/opt/cni/bin
   cilium status --wait
   scripts/patch-metrics-server-tailscale.sh
   ```

   The k3s server must keep `--flannel-backend=none`; Cilium is the only CNI
   for this cluster.

4. Join the worker nodes. Agents inherit the server-side CNI choice, so do not
   install or enable flannel on the agents:

   ```sh
   sudo cat /var/lib/rancher/k3s/server/node-token

   ssh 100.121.31.95 "curl -sfL https://get.k3s.io | K3S_URL=https://100.118.192.86:6443 K3S_TOKEN='<node-token>' INSTALL_K3S_EXEC='agent --node-ip 100.121.31.95 --node-external-ip 100.121.31.95' sh -"
   ssh 100.85.172.81 "curl -sfL https://get.k3s.io | K3S_URL=https://100.118.192.86:6443 K3S_TOKEN='<node-token>' INSTALL_K3S_EXEC='agent --node-ip 100.85.172.81 --node-external-ip 100.85.172.81' sh -"
   ```

5. Start the host Redis-compatible metadata service:

   ```sh
   sudo scripts/prepare-host-redis.sh 100.118.192.86
   ```

6. Apply the source wildcard TLS Secret for Kyverno to clone:

   ```sh
   scripts/apply-erotica-tls-source.sh
   ```

   By default this reads:

   - `/home/terenceliu/acme/ssl/erotica.icu.full.pem`
   - `/home/terenceliu/acme/ssl/erotica.icu.key`

7. Create `.env`:

   ```sh
   cp .env.example .env
   ```

   Fill the domain, GitOps repo, GitHub OAuth values, Dex local user hash,
   Gitea admin password, Gitea OIDC secret, Gitea runner token, and generated
   client/metadata secrets.

8. Materialize placeholders before committing the GitOps repo:

   ```sh
   scripts/materialize-config.sh --in-place
   ```

9. Commit and push the repository to `GITOPS_REPO_URL`.

10. Bootstrap Argo CD and the root app:

   ```sh
   scripts/bootstrap.sh
   ```

## Optional Storage Bootstrap

If JuiceFS storage should be deployed before Argo CD has reconciled all apps:

```sh
sudo scripts/apply-storage-now.sh
```

## Verification

```sh
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium
sudo k3s kubectl get pods -A
sudo k3s kubectl get ingress -A
sudo k3s kubectl get storageclass
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n gitea get pods,ingress,pvc
sudo k3s kubectl -n storage get pods
sudo k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=juicefs-csi-driver
sudo k3s kubectl get storageclass juicefs-sc -o wide
sudo k3s kubectl -n opensandbox-system get pods,svc,ingress
sudo k3s kubectl get crd | grep sandbox.opensandbox.io
sudo k3s kubectl get secret -A | grep erotica-icu-tls
sudo k3s kubectl -n istio-system get requestauthentication dex-jwt -o yaml
```

Or run:

```sh
scripts/verify-k3s-juicefs.sh
```

If `local-path` exists, it must not be the default:

```sh
sudo k3s kubectl get storageclass
sudo k3s kubectl get sc local-path -o yaml
```

Before deployment, you can run static checks locally:

```sh
scripts/storage-audit.sh
```

Then run one of:

```sh
./scripts/deploy-checklist.sh
./scripts/deploy-checklist.sh --skip-storage
./scripts/deploy-checklist.sh --verify-only
./scripts/deploy-checklist.sh --deploy-only
```

`deploy-checklist.sh` runs the full path: storage audit, bootstrap/deploy, node list, and juicefs verification.

The Kubeflow JWT issuer should be `https://auth.<BASE_DOMAIN>`, not the disabled
Kubeflow internal Dex service.

Kubeflow user Profiles are not pre-created in Git. Central Dashboard
registration flow is enabled, and users create their Profile/workspace from the
Kubeflow UI after authenticating through the global Dex.

Gitea is available at `https://git.<BASE_DOMAIN>`. The Dex callback URL rendered
for Gitea is `https://git.<BASE_DOMAIN>/user/oauth2/dex/callback`.

OpenSandbox is available at `https://opensandbox.<BASE_DOMAIN>`. It is deployed
from the upstream controller and server Helm charts and configured for
Kubernetes BatchSandbox workloads in the `opensandbox` namespace. The server
expects the `OPEN-SANDBOX-API-KEY` header from the
`opensandbox-system/opensandbox-api-key` Secret. To create an AIO sandbox, call
the OpenSandbox API/SDK with image `ghcr.io/agent-infra/sandbox:latest`,
entrypoint `/opt/gem/run.sh`, and AIO port `8080`.

## Secret Policy

Do not commit `.env` or `rendered/`. They contain OAuth credentials, Dex config,
JuiceFS metadata credentials, and generated Kubernetes Secrets.

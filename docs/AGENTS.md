# Agent Runbook

This file is for agents operating this repository without extra context.
The target environment is a k3s homelab using intranet node IPs and Cilium as
CNI. Changes should remain compatible with the pure-intranet setup.

## Cluster Facts

- Repository path on the server: `/home/terenceliu/development/homelab`
- k3s server intranet IP: `192.168.2.153`
- k3s server hostname: `optiplex5060`
- Known worker IP: `192.168.2.148`
- Default SSH user for workers: `terenceliu`
- k3s must not run flannel on workers in this repo (server policy applies to agent
  networking as inherited CNI)

## Core assumptions

Run these procedures from the k3s control-plane host or another host that has direct
access to `https://192.168.2.153:6443` using a valid kubeconfig. Some sandboxed
executions cannot contact localhost API (`socket: operation not permitted`) and are
not representative of real host behavior.

You do not need to SSH into the master when adding a worker; you do need SSH to
workers.

## One-shot deployment sequence (recommended)

### 1) Prepare repo and env

```sh
cd /home/terenceliu/development/homelab
git pull
cp .env.example .env
```

Fill all required variables in `.env`, including at least:

- `BASE_DOMAIN`
- `GITOPS_REPO_URL`
- `GITOPS_TARGET_REVISION`
- `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`
- `GITHUB_ALLOWED_LOGIN`, `GITHUB_ALLOWED_EMAIL`
- `ARGO_DEX_CLIENT_SECRET`
- `KUBEFLOW_OIDC_CLIENT_SECRET`
- `GITEA_OIDC_CLIENT_SECRET`
- `GITEA_ADMIN_USERNAME`, `GITEA_ADMIN_PASSWORD`
- `GITEA_RUNNER_REGISTRATION_TOKEN`
- `OPENSANDBOX_API_KEY`
- `DEX_LOCAL_ADMIN_EMAIL`, `DEX_LOCAL_ADMIN_USERNAME`, `DEX_LOCAL_ADMIN_BCRYPT_HASH`
- `JUICEFS_NAME`, `JUICEFS_META_PASSWORD`, `JUICEFS_META_HOST`, `JUICEFS_BUCKET`

### 2) Prepare host (optional)

On a fresh machine:

```sh
cd /home/terenceliu/development/homelab
sudo scripts/install-host-tools-arch.sh
sudo scripts/deploy-homelab-full.sh
```

If storage/layout already exists:

```sh
SKIP_HOST_STORAGE_PREP=1
```

### 3) Render GitOps manifests for this env

```sh
cd /home/terenceliu/development/homelab
scripts/materialize-config.sh --in-place
```

Commit if this repo is also used as GitOps source:

```sh
git add clusters platform docs README.md
git commit -m "Render GitOps templates for this environment"
git push
```

### 4) Bootstrap Argo CD (GitOps master bootstrap)

```sh
cd /home/terenceliu/development/homelab
./scripts/deploy-gitops-master.sh
```

Script does:

- materializes and applies `rendered/secrets.yaml`
- applies `rendered/argocd-helmchart.yaml`
- waits for `applications.argoproj.io` CRD to appear
- patches `argocd-secret` with OIDC client secret
- applies `rendered/root-application.yaml`

Verify:

```sh
sudo k3s kubectl get ns argocd
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n argocd get pods
sudo k3s kubectl get ingress -A
```

Expected: `argocd` namespace exists and the root app moves toward healthy sync.

## Add a worker node (192.168.2.148)

Run from master host:

```sh
cd /home/terenceliu/development/homelab
WORKER_IPS="192.168.2.148" \
  MASTER_IP="192.168.2.153" \
  REMOTE_USER="terenceliu" \
  SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10" \
  scripts/join-workers.sh
```

The helper script defaults `SSH_OPTS` to `-F /dev/null ...`; if your SSH agent
config is required, pass this explicit option set.

If `node-token` is unreadable, force it through sudo or environment:

```sh
NODE_TOKEN="$(sudo cat /var/lib/rancher/k3s/server/node-token)"
WORKER_IPS="192.168.2.148" \
  NODE_TOKEN="$NODE_TOKEN" \
  MASTER_IP="192.168.2.153" \
  REMOTE_USER="terenceliu" \
  SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10" \
  scripts/join-workers.sh
```

Manual fallback when helper is not usable:

```sh
NODE_TOKEN="$(sudo cat /var/lib/rancher/k3s/server/node-token)"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 terenceliu@192.168.2.148 \
  "curl -sfL https://get.k3s.io | \
   K3S_URL=https://192.168.2.153:6443 \
   K3S_TOKEN='$NODE_TOKEN' \
   INSTALL_K3S_EXEC='agent --node-ip 192.168.2.148 --node-external-ip 192.168.2.148' sh -"
```

If worker was previously misconfigured:

```sh
ssh terenceliu@192.168.2.148 'sudo /usr/local/bin/k3s-agent-uninstall.sh'
```

## Validate cluster after worker join

```sh
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl describe node thinkpadx13-2022
sudo k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium-agent -o wide
```

Healthy signs:

- Node is `Ready`
- no `node.kubernetes.io/unreachable`
- Argo/CD pods eventually all `Running` with ready probes passing

## Troubleshooting

SSH to worker fails:

```sh
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 terenceliu@192.168.2.148 'echo ok'
```

Deploy script cannot reach API (local sandbox error such as `socket: operation not permitted`):

1. rerun from real master host shell (not isolated tool sandbox)
2. confirm `k3s kubectl` works there
3. only then rerun `./scripts/deploy-gitops-master.sh`

If `deploy-gitops` hangs waiting for CRD:

```sh
sudo k3s kubectl -n argocd get pods
sudo k3s kubectl -n argocd logs deploy/argocd-server --tail=100
sudo k3s kubectl -n argocd logs deploy/argocd-repo-server --tail=100
```

If you see controller timeouts to `10.43.0.1:443`, verify Cilium replacement mode
and API service reachability on nodes.

## One-shot command summary

```sh
cd /home/terenceliu/development/homelab
scripts/materialize-config.sh --in-place
./scripts/deploy-gitops-master.sh
scripts/join-workers.sh
```

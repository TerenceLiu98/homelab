# Operations

## Required GitHub OAuth app

Create a GitHub OAuth app with:

- Homepage URL: `https://auth.${BASE_DOMAIN}`
- Authorization callback URL: `https://auth.${BASE_DOMAIN}/callback`

Use the resulting client ID and secret in `.env`.

## DNS

Create DNS records pointing to the intranet IP `192.168.2.153`:

- `auth.${BASE_DOMAIN}`
- `argo.${BASE_DOMAIN}`
- `kubeflow.${BASE_DOMAIN}`
- `git.${BASE_DOMAIN}`
- `opensandbox.${BASE_DOMAIN}`
- `platform.${BASE_DOMAIN}`

## Full Redeploy

```sh
sudo scripts/redeploy-k3s.sh
```

Or one-command bootstrap:

```sh
sudo scripts/deploy-homelab-full.sh
```

If host disk prep is already done:

```sh
SKIP_HOST_STORAGE_PREP=1 sudo scripts/deploy-homelab-full.sh
```

## Verification commands

```sh
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A
sudo k3s kubectl get storageclass
sudo k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium
sudo k3s kubectl get ingress -A
sudo k3s kubectl get secret -A | grep initio-cc-tls
sudo k3s kubectl -n argocd get applications
```

## TLS Secret renewal

After renewing the ACME certificate, update the source Secret:

```sh
scripts/apply-initio-tls-source.sh
```

Kyverno synchronizes `kyverno/initio-cc-tls` into the namespaces that own
Ingress resources.

## Storage smoke test

```sh
sudo k3s kubectl get pods -n storage
sudo k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=juicefs-csi-driver
sudo k3s kubectl get storageclass juicefs-sc
```

```sh
scripts/verify-k3s-juicefs.sh
```

Static repo audit:

```sh
scripts/storage-audit.sh
```

Run full redeploy checks in one shot:

```sh
./scripts/deploy-checklist.sh
./scripts/deploy-checklist.sh --skip-storage
./scripts/deploy-checklist.sh --verify-only
./scripts/deploy-checklist.sh --deploy-only
```

If local-path exists at all, it must not be the default:

```sh
sudo k3s kubectl get sc
sudo k3s kubectl get sc local-path -o yaml
```

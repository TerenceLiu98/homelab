# Operations

## Required GitHub OAuth app

Create a GitHub OAuth app with:

- Homepage URL: `https://auth.${BASE_DOMAIN}`
- Authorization callback URL: `https://auth.${BASE_DOMAIN}/callback`

Use the resulting client ID and secret in `.env`.

## DNS

Create DNS records pointing to the Tailscale IP `100.118.192.87`:

- `auth.${BASE_DOMAIN}`
- `argo.${BASE_DOMAIN}`
- `kubeflow.${BASE_DOMAIN}`

## Verification commands

```sh
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A
sudo k3s kubectl get ingress -A
sudo k3s kubectl get storageclass
sudo k3s kubectl -n argocd get applications
```

## Storage smoke test

```sh
sudo k3s kubectl get pods -n storage
sudo k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=juicefs-csi-driver
sudo k3s kubectl get storageclass juicefs-rwx
```

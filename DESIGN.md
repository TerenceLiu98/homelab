# Homelab k3s Platform Design

## Goals

This repository defines a k3s homelab platform with DELL `optiplex-5060` model.
The design favors a small number of explicit host dependencies and keeps
cluster application delivery under Argo CD.

Primary goals:

- One identity source for all applications.
- GitOps-managed cluster add-ons and Kubeflow configuration.
- Local disk backed storage on `/dev/sda`.
- RWX persistent volumes through JuiceFS CSI.
- Automatic TLS Secret fan-out for Ingress namespaces.
- Minimal secret material in Git; generated secrets stay local.

## Topology

```text
Internet / LAN
    |
    v
Traefik ingress from k3s
    |
    +-- auth.<domain>      -> identity/dex
    +-- argo.<domain>      -> argocd/argocd-server
    +-- kubeflow.<domain>  -> istio-system/istio-ingressgateway

Host services
    |
    +-- /dev/sda -> /srv/k3s-data
    +-- GlusterFS gv0 mounted at /srv/k3s-data/gluster/mounts/gv0
    +-- Valkey/Redis on 100.118.192.87:6379 for JuiceFS metadata

k3s cluster
    |
    +-- argocd             GitOps controller
    +-- identity           global Dex identity provider
    +-- storage            JuiceFS CSI and format job
    +-- kyverno            policy automation and TLS Secret sync
    +-- oauth2-proxy       Kubeflow OIDC gateway
    +-- istio-system       Kubeflow ingress and JWT validation
    +-- kubeflow           Kubeflow applications
```

## GitOps Layout

`clusters/optiplex5060/bootstrap` contains the initial resources applied by
`scripts/bootstrap.sh`:

- `argocd-helmchart.yaml` installs Argo CD through k3s HelmChart.
- `root-application.yaml` points Argo CD at this repository.

`clusters/optiplex5060/apps` contains the root kustomization for platform
applications:

- `storage.yaml`
- `kyverno.yaml`
- `kyverno-policies.yaml`
- `auth.yaml`
- `ingress.yaml`
- `kubeflow.yaml`

Each app points at a folder under `platform/`.

## Identity

The cluster uses one global Dex deployment in the `identity` namespace.
Dex is the identity provider for:

- Argo CD, using client ID `argo-cd`.
- Kubeflow, using client ID `kubeflow-oidc`.
- Future applications, by adding another Dex static client and configuring the
  application to use `https://auth.<domain>`.

Dex supports:

- Local password database for a bootstrap/admin user.
- GitHub OAuth as an external connector.

Generated Dex configuration and OAuth secrets are rendered from `.env` by
`scripts/render-secrets.sh` into `rendered/secrets.yaml`. The rendered output is
not intended for Git.

Kubeflow's bundled Dex deployment is scaled to zero. Kubeflow authentication
uses `oauth2-proxy` against the global Dex issuer:

```text
Browser -> kubeflow.<domain> -> Istio ingressgateway -> oauth2-proxy
oauth2-proxy -> Dex at auth.<domain> -> GitHub or local password login
Dex token -> oauth2-proxy cookie/session -> Kubeflow services
```

Istio validates JWTs with `RequestAuthentication/istio-system/dex-jwt`. The
issuer must be `https://auth.<domain>` and JWKS must point at the in-cluster Dex
service. This prevents Kubeflow from depending on its disabled internal Dex.

## Storage

The storage stack intentionally uses `/dev/sda` as disposable local capacity.
`scripts/prepare-host-storage.sh` repartitions the device and mounts it at
`/srv/k3s-data`.

Host layout:

- `/srv/k3s-data/local-path` for the k3s local-path provisioner.
- `/srv/k3s-data/gluster/bricks/gv0` for the GlusterFS brick.
- `/srv/k3s-data/gluster/mounts/gv0` for the mounted GlusterFS volume.
- `/srv/k3s-data/redis` for Valkey/Redis metadata persistence.
- `/srv/k3s-data/backups` reserved for backups.

JuiceFS uses:

- Metadata: host Valkey/Redis at `100.118.192.87:6379`, database `1`.
- Object storage: JuiceFS `gluster` backend at
  `100.118.192.87/storage/gluster`.
- Kubernetes access: `juicefs-sc` StorageClass through JuiceFS CSI, with
  dynamic PV paths rendered as `<namespace>/<pvc-name>`.

This gives cluster workloads RWX PVCs without running MinIO or Redis inside the
cluster.

## Ingress

k3s Traefik is the public ingress controller. It terminates HTTP(S) traffic for
the platform hostnames and forwards:

- `auth.<domain>` to global Dex.
- `argo.<domain>` to Argo CD.
- `kubeflow.<domain>` to Kubeflow's Istio ingressgateway.

Kubeflow still uses Istio internally because the upstream manifests expect it.
Traefik is only the edge entrypoint.

All public Ingress resources use the same TLS Secret name:
`erotica-icu-tls`.

The source TLS Secret is stored in the `kyverno` namespace and created from the
host ACME files:

- `/home/terenceliu/acme/ssl/erotica.icu.full.pem`
- `/home/terenceliu/acme/ssl/erotica.icu.key`

`scripts/apply-erotica-tls-source.sh` creates or updates
`kyverno/erotica-icu-tls`. Kyverno then clones that Secret into every namespace
that has an Ingress, currently:

- `argocd`
- `identity`
- `istio-system`

The Kyverno policy uses `synchronize: true`, so renewing the source Secret will
propagate the certificate to the generated namespace copies.

Secret write permissions are scoped to the current Ingress namespaces instead
of cluster-wide. When a new public Ingress namespace is added, add the namespace
to `platform/kyverno-policies/tls-secret-sync.yaml`.

## Kubeflow

Kubeflow is installed from `kubeflow/manifests` at `v1.11.0`, path `example`.
The Argo CD Application applies kustomize patches for this cluster:

- Delete the upstream example `Profile` and enable Central Dashboard
  registration flow, so user Profiles are created through Kubeflow after login
  instead of being managed as fixed GitOps objects.
- Scale down Kubeflow's bundled Dex.
- Point `oauth2-proxy` at the global Dex Secret and ConfigMap.
- Patch Istio `RequestAuthentication` to trust the global Dex issuer.
- Keep mTLS enabled for `jupyter-web-app`, because its Istio
  `AuthorizationPolicy` checks the ingressgateway source principal before the
  request reaches the Jupyter backend.

Kubeflow on k3s is treated as a pragmatic homelab deployment. Upstream manifests
install Istio, Knative, KServe, Katib, Pipelines, Spark, Training Operator, and
related components.

## Bootstrap Flow

1. Install host packages with `scripts/install-host-tools-arch.sh`.
2. Prepare `/dev/sda` and GlusterFS with `scripts/prepare-host-storage.sh`.
3. Start host Valkey/Redis metadata with `scripts/prepare-host-redis.sh`.
4. Apply the source TLS Secret with `scripts/apply-erotica-tls-source.sh`.
5. Fill `.env` from `.env.example`.
6. Render and apply storage secrets if storage is needed before Argo CD:
   `scripts/apply-storage-now.sh`.
7. Materialize placeholders with `scripts/materialize-config.sh --in-place`.
8. Commit and push the repo to `GITOPS_REPO_URL`.
9. Bootstrap Argo CD with `scripts/bootstrap.sh`.

## Secret Handling

`.env` and `rendered/` are ignored by Git. `.env.example` documents required
inputs. The generated manifests contain:

- Dex config and OAuth client secrets.
- Kubeflow oauth2-proxy client secret.
- JuiceFS metadata password and Redis URL.

Do not commit generated secret manifests.

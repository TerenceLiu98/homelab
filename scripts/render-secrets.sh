#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
. scripts/load-env.sh

JUICEFS_SECRET_NAME="${JUICEFS_SECRET_NAME:-juicefs-sc-secret}"
JUICEFS_SECRET_NAMESPACE="${JUICEFS_SECRET_NAMESPACE:-kube-system}"
JUICEFS_STORAGE="${JUICEFS_STORAGE:-gluster}"
JUICEFS_BUCKET="${JUICEFS_BUCKET:-${JUICEFS_OBJECT_PATH:-100.118.192.86/gv0/juicefs-objects}}"
JUICEFS_ENVS="${JUICEFS_ENVS:-{JFS_DROP_OSCACHE: 1}}"

require_env \
  BASE_DOMAIN \
  GITHUB_CLIENT_ID \
  GITHUB_CLIENT_SECRET \
  GITHUB_ALLOWED_LOGIN \
  GITHUB_ALLOWED_EMAIL \
  ARGO_DEX_CLIENT_SECRET \
  KUBEFLOW_OIDC_CLIENT_SECRET \
  GITEA_OIDC_CLIENT_SECRET \
  GITEA_ADMIN_USERNAME \
  GITEA_ADMIN_PASSWORD \
  GITEA_RUNNER_REGISTRATION_TOKEN \
  OPENSANDBOX_API_KEY \
  DEX_LOCAL_ADMIN_EMAIL \
  DEX_LOCAL_ADMIN_USERNAME \
  DEX_LOCAL_ADMIN_BCRYPT_HASH \
  JUICEFS_NAME \
  JUICEFS_META_PASSWORD \
  JUICEFS_META_HOST \
  JUICEFS_BUCKET

mkdir -p rendered

cat > rendered/secrets.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: identity
---
apiVersion: v1
kind: Namespace
metadata:
  name: storage
---
apiVersion: v1
kind: Namespace
metadata:
  name: gitea
---
apiVersion: v1
kind: Namespace
metadata:
  name: oauth2-proxy
---
apiVersion: v1
kind: Secret
metadata:
  name: dex-runtime
  namespace: identity
type: Opaque
stringData:
  github-client-id: "${GITHUB_CLIENT_ID}"
  github-client-secret: "${GITHUB_CLIENT_SECRET}"
  argo-client-secret: "${ARGO_DEX_CLIENT_SECRET}"
  kubeflow-client-secret: "${KUBEFLOW_OIDC_CLIENT_SECRET}"
  gitea-client-secret: "${GITEA_OIDC_CLIENT_SECRET}"
  local-admin-bcrypt-hash: "${DEX_LOCAL_ADMIN_BCRYPT_HASH}"
---
apiVersion: v1
kind: Secret
metadata:
  name: dex-config
  namespace: identity
type: Opaque
stringData:
  config.yaml: |
    issuer: https://auth.${BASE_DOMAIN}
    storage:
      type: sqlite3
      config:
        file: /var/dex/dex.db
    web:
      http: 0.0.0.0:5556
    oauth2:
      skipApprovalScreen: true
    enablePasswordDB: true
    staticPasswords:
      - email: "${DEX_LOCAL_ADMIN_EMAIL}"
        username: "${DEX_LOCAL_ADMIN_USERNAME}"
        userID: "local-admin"
        hash: "${DEX_LOCAL_ADMIN_BCRYPT_HASH}"
    staticClients:
      - id: argo-cd
        name: Argo CD
        secret: "${ARGO_DEX_CLIENT_SECRET}"
        redirectURIs:
          - https://argo.${BASE_DOMAIN}/auth/callback
      - id: kubeflow-oidc
        name: Kubeflow
        secret: "${KUBEFLOW_OIDC_CLIENT_SECRET}"
        redirectURIs:
          - https://kubeflow.${BASE_DOMAIN}/oauth2/callback
      - id: gitea
        name: Gitea
        secret: "${GITEA_OIDC_CLIENT_SECRET}"
        redirectURIs:
          - https://git.${BASE_DOMAIN}/user/oauth2/dex/callback
    connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: "${GITHUB_CLIENT_ID}"
          clientSecret: "${GITHUB_CLIENT_SECRET}"
          redirectURI: https://auth.${BASE_DOMAIN}/callback
          useLoginAsID: true
          loadAllGroups: false
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex-allowed-users
  namespace: identity
data:
  github-login: "${GITHUB_ALLOWED_LOGIN}"
  github-email: "${GITHUB_ALLOWED_EMAIL}"
---
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-global-dex
  namespace: oauth2-proxy
type: Opaque
stringData:
  client-id: "kubeflow-oidc"
  client-secret: "${KUBEFLOW_OIDC_CLIENT_SECRET}"
---
apiVersion: v1
kind: Secret
metadata:
  name: gitea-admin
  namespace: gitea
type: Opaque
stringData:
  username: "${GITEA_ADMIN_USERNAME}"
  password: "${GITEA_ADMIN_PASSWORD}"
---
apiVersion: v1
kind: Secret
metadata:
  name: gitea-oauth-dex
  namespace: gitea
type: Opaque
stringData:
  key: "gitea"
  secret: "${GITEA_OIDC_CLIENT_SECRET}"
---
apiVersion: v1
kind: Secret
metadata:
  name: gitea-actions-token
  namespace: gitea
type: Opaque
stringData:
  token: "${GITEA_RUNNER_REGISTRATION_TOKEN}"
---
apiVersion: v1
kind: Namespace
metadata:
  name: opensandbox-system
---
apiVersion: v1
kind: Secret
metadata:
  name: opensandbox-api-key
  namespace: opensandbox-system
type: Opaque
stringData:
  api-key: "${OPENSANDBOX_API_KEY}"
---
apiVersion: v1
kind: Secret
metadata:
  name: ${JUICEFS_SECRET_NAME}
  namespace: ${JUICEFS_SECRET_NAMESPACE}
type: Opaque
stringData:
  name: "${JUICEFS_NAME}"
  metaurl: "redis://:${JUICEFS_META_PASSWORD}@${JUICEFS_META_HOST}:6379/1"
  storage: "${JUICEFS_STORAGE}"
  bucket: "${JUICEFS_BUCKET}"
  envs: "${JUICEFS_ENVS}"
EOF

echo "Rendered rendered/secrets.yaml"

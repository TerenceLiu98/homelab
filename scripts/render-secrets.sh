#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
. scripts/load-env.sh

require_env \
  BASE_DOMAIN \
  GITHUB_CLIENT_ID \
  GITHUB_CLIENT_SECRET \
  GITHUB_ALLOWED_LOGIN \
  GITHUB_ALLOWED_EMAIL \
  ARGO_DEX_CLIENT_SECRET \
  KUBEFLOW_OIDC_CLIENT_SECRET \
  DEX_LOCAL_ADMIN_EMAIL \
  DEX_LOCAL_ADMIN_USERNAME \
  DEX_LOCAL_ADMIN_BCRYPT_HASH \
  JUICEFS_NAME \
  JUICEFS_META_PASSWORD \
  JUICEFS_META_HOST \
  JUICEFS_OBJECT_PATH

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
  name: juicefs-secret
  namespace: storage
type: Opaque
stringData:
  name: "${JUICEFS_NAME}"
  redis-password: "${JUICEFS_META_PASSWORD}"
  metaurl: "redis://:${JUICEFS_META_PASSWORD}@${JUICEFS_META_HOST}:6379/1"
  storage: "file"
  bucket: "${JUICEFS_OBJECT_PATH}"
EOF

echo "Rendered rendered/secrets.yaml"

#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
. scripts/load-env.sh

export MASTER_IP="${MASTER_IP:-100.118.192.86}"

require_env \
  BASE_DOMAIN \
  GITOPS_REPO_URL \
  GITOPS_TARGET_REVISION \
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

if ! command -v k3s >/dev/null 2>&1; then
  echo "k3s binary not found. Run with sudo, or install k3s and re-run." >&2
  exit 1
fi

KUBECTL() {
  k3s kubectl "$@"
}

scripts/materialize-config.sh --in-place
scripts/render-secrets.sh

KUBECTL apply -f rendered/secrets.yaml
KUBECTL apply -f rendered/argocd-helmchart.yaml

echo "Waiting for applications.argoproj.io CRD..."
for i in $(seq 1 120); do
  if KUBECTL get crd applications.argoproj.io >/dev/null 2>&1; then
    break
  fi
  sleep 5
  if [ "$i" -eq 120 ]; then
    echo "Timed out waiting for Argo CD CRD." >&2
    exit 1
  fi
done

KUBECTL -n argocd rollout status deploy/argocd-server --timeout=600s

OIDC_SECRET_B64="$(printf '%s' "$ARGO_DEX_CLIENT_SECRET" | base64 | tr -d '\n')"
KUBECTL -n argocd patch secret argocd-secret --type merge \
  -p "{\"data\":{\"oidc.dex.clientSecret\":\"${OIDC_SECRET_B64}\"}}"

KUBECTL apply -f rendered/root-application.yaml

echo "GitOps bootstrap steps completed on ${MASTER_IP}."

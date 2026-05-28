#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
. scripts/load-env.sh

require_env BASE_DOMAIN GITOPS_REPO_URL GITOPS_TARGET_REVISION ARGO_DEX_CLIENT_SECRET

mkdir -p rendered
render_template clusters/optiplex5060/bootstrap/argocd-helmchart.yaml rendered/argocd-helmchart.yaml
render_template clusters/optiplex5060/bootstrap/root-application.yaml rendered/root-application.yaml

scripts/render-secrets.sh

if grep -R "__BASE_DOMAIN__\\|__GITOPS_REPO_URL__\\|__GITOPS_TARGET_REVISION__" clusters platform >/dev/null 2>&1; then
  echo "GitOps manifests still contain placeholders." >&2
  echo "Run scripts/materialize-config.sh --in-place, commit/push, then rerun bootstrap." >&2
  exit 1
fi

sudo k3s kubectl apply -f rendered/secrets.yaml
sudo k3s kubectl apply -f rendered/argocd-helmchart.yaml

echo "Waiting for Argo CD CRDs and server..."
until sudo k3s kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  sleep 5
done
sudo k3s kubectl -n argocd rollout status deploy/argocd-server --timeout=600s

OIDC_SECRET_B64="$(printf '%s' "$ARGO_DEX_CLIENT_SECRET" | base64 | tr -d '\n')"
sudo k3s kubectl -n argocd patch secret argocd-secret --type merge \
  -p "{\"data\":{\"oidc.dex.clientSecret\":\"${OIDC_SECRET_B64}\"}}"

sudo k3s kubectl apply -f rendered/root-application.yaml

echo "Bootstrap applied. Argo CD should sync from ${GITOPS_REPO_URL}."

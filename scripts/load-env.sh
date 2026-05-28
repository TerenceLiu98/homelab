#!/usr/bin/env sh
set -eu

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

require_env() {
  missing=""
  for name in "$@"; do
    eval "value=\${$name:-}"
    if [ -z "$value" ]; then
      missing="$missing $name"
    fi
  done

  if [ -n "$missing" ]; then
    echo "Missing required environment variables:$missing" >&2
    exit 1
  fi
}

render_template() {
  src="$1"
  dst="$2"
  sed \
    -e "s#__BASE_DOMAIN__#${BASE_DOMAIN}#g" \
    -e "s#__GITOPS_REPO_URL__#${GITOPS_REPO_URL}#g" \
    -e "s#__GITOPS_TARGET_REVISION__#${GITOPS_TARGET_REVISION}#g" \
    -e "s#__GITHUB_ALLOWED_EMAIL__#${GITHUB_ALLOWED_EMAIL}#g" \
    -e "s#__GITHUB_ALLOWED_LOGIN__#${GITHUB_ALLOWED_LOGIN}#g" \
    "$src" > "$dst"
}


#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
. scripts/load-env.sh

require_env BASE_DOMAIN GITOPS_REPO_URL GITOPS_TARGET_REVISION GITHUB_ALLOWED_EMAIL GITHUB_ALLOWED_LOGIN

MODE=rendered
if [ "${1:-}" = "--in-place" ]; then
  MODE=in-place
fi

if [ "$MODE" = rendered ]; then
  mkdir -p rendered/gitops
  for dir in clusters platform docs; do
    rm -rf "rendered/gitops/$dir"
    cp -R "$dir" "rendered/gitops/$dir"
  done
  cp README.md DESIGN.md .gitignore .env.example rendered/gitops/
  TARGET=rendered/gitops
else
  TARGET="clusters platform docs README.md"
fi

find $TARGET -type f | while read -r file; do
  render_template "$file" "$file.tmp"
  mv "$file.tmp" "$file"
done

if [ "$MODE" = rendered ]; then
  echo "Rendered GitOps tree at rendered/gitops"
else
  echo "Materialized placeholders in place. Commit and push these changes before bootstrapping Argo."
fi

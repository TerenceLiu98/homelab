#!/usr/bin/env sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if command -v kubectl >/dev/null 2>&1; then
  KUSTOMIZE_CMD="kubectl kustomize"
elif command -v kustomize >/dev/null 2>&1; then
  KUSTOMIZE_CMD="kustomize build"
else
  fail "kubectl or kustomize is required for manifest rendering"
fi

echo "[1/4] Check StorageClass defaults declaration"
grep -R "storageclass.kubernetes.io/is-default-class" -n platform/storage/juicefs-storageclass.yaml >/dev/null || fail "juicefs-sc default annotation missing"

echo "[2/4] Check local-path references in repo"
if rg -n "local-path|local_path|localpath" -S platform clusters --glob '*.yaml' --glob '*.yml' >/tmp/localpath-hits.txt; then
  if [ -s /tmp/localpath-hits.txt ]; then
    echo "local-path references found in manifests (non-default allowed only if explicitly intentional)."
    cat /tmp/localpath-hits.txt
  fi
fi

echo "[3/4] Check app storageClass assignments"
rg -n "storageClassName:|storageClass:" -S platform/ clusters/optiplex5060 >/tmp/storageclass-refs.txt
if rg -n "local-path" -S /tmp/storageclass-refs.txt >/tmp/storageclass-localpath.txt; then
  echo "Found local-path storageClass references in manifests:"
  cat /tmp/storageclass-localpath.txt
  echo "These are not allowed for this objective (juicefs-only)."
  exit 1
fi
if ! rg -n "juicefs-sc" -S /tmp/storageclass-refs.txt >/dev/null; then
  echo "No explicit juicefs-sc storageClass references found in rendered manifest set."
  exit 1
fi

echo "[4/4] Render manifests to ensure kustomize paths valid"
$KUSTOMIZE_CMD platform/storage >/tmp/storage-kustomize.yaml
$KUSTOMIZE_CMD platform/kubeflow >/tmp/kubeflow-kustomize.yaml
$KUSTOMIZE_CMD platform/auth >/tmp/auth-kustomize.yaml
$KUSTOMIZE_CMD clusters/optiplex5060/apps >/tmp/apps-kustomize.yaml

grep -q "juicefs-sc" /tmp/storage-kustomize.yaml || fail "juicefs-sc missing from rendered storage"
grep -q "kind: StorageClass" /tmp/storage-kustomize.yaml || fail "storage class resource missing"

echo "Storage audit passed."

#!/usr/bin/env sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_AUDIT=1
RUN_DEPLOY=1
RUN_VERIFY=1
SKIP_HOST_STORAGE_PREP=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    skip-storage|--skip-storage)
      SKIP_HOST_STORAGE_PREP=1
      ;;
    --audit-only)
      RUN_DEPLOY=0
      RUN_VERIFY=0
      ;;
    --deploy-only)
      RUN_VERIFY=0
      ;;
    --verify-only)
      RUN_AUDIT=0
      RUN_DEPLOY=0
      ;;
    -h|--help)
      echo "Usage: $0 [skip-storage|--skip-storage] [--audit-only|--deploy-only|--verify-only]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [skip-storage|--skip-storage] [--audit-only|--deploy-only|--verify-only]"
      exit 1
      ;;
  esac
  shift

done

export SKIP_HOST_STORAGE_PREP

if [ "$RUN_AUDIT" = "1" ]; then
  printf '\n=== 0) repository static checks ===\n'
  ./scripts/storage-audit.sh
fi

if [ "$RUN_DEPLOY" = "1" ]; then
  printf '\n=== 1) deploy homelab ===\n'
  if [ "$SKIP_HOST_STORAGE_PREP" = "1" ]; then
    echo "[INFO] Running with SKIP_HOST_STORAGE_PREP=1"
    sudo --preserve-env=SKIP_HOST_STORAGE_PREP ./scripts/deploy-homelab-full.sh
  else
    sudo ./scripts/deploy-homelab-full.sh
  fi
fi

if [ "$RUN_VERIFY" = "1" ]; then
  printf '\n=== 2) cluster state ===\n'
  sudo k3s kubectl -n argocd get applications -o wide
  sudo k3s kubectl get nodes -o wide

  printf '\n=== 3) storage checks ===\n'
  ./scripts/verify-k3s-juicefs.sh
  printf '\n=== done ===\n'
fi

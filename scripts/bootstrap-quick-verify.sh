#!/usr/bin/env sh
set -eu

K3S_BIN="${K3S_BIN:-k3s}"
if [ "$K3S_BIN" = "k3s" ] && command -v k3s >/dev/null 2>&1; then
  KUBECTL="k3s kubectl"
  USE_SUDO=1
else
  KUBECTL="kubectl"
  USE_SUDO=0
fi
if [ "$(id -u)" -eq 0 ]; then
  USE_SUDO=0
fi

kubectl_cmd() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo $KUBECTL "$@"
  else
    $KUBECTL "$@"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/bootstrap-quick-verify.sh --all
  ./scripts/bootstrap-quick-verify.sh --nodes
  ./scripts/bootstrap-quick-verify.sh --pvc
  ./scripts/bootstrap-quick-verify.sh --apps

Verifies JuiceFS-class defaults and PVC storage usage.
USAGE
  exit 1
}

RUN_NODES=0
RUN_APPS=0
RUN_PVC=0
RUN_STORAGE=0

if [ "$#" -eq 0 ]; then
  usage
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      RUN_NODES=1
      RUN_APPS=1
      RUN_PVC=1
      RUN_STORAGE=1
      ;;
    --nodes)
      RUN_NODES=1
      ;;
    --apps)
      RUN_APPS=1
      ;;
    --pvc)
      RUN_PVC=1
      ;;
    --storage)
      RUN_STORAGE=1
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if [ "$RUN_NODES" = "1" ]; then
  echo "== Nodes =="
  kubectl_cmd get nodes -o wide
  echo
fi

if [ "$RUN_APPS" = "1" ]; then
  echo "== Argo Applications =="
  kubectl_cmd -n argocd get applications -o wide
  echo
fi

if [ "$RUN_STORAGE" = "1" ]; then
  echo "== Storage Classes =="
  kubectl_cmd get storageclass
  DEFAULT_SC="$(kubectl_cmd get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')"
  echo "Default SC: ${DEFAULT_SC}"
  echo
fi

if [ "$RUN_PVC" = "1" ]; then
  echo "== PVC storageClass audit =="
  echo "Non-empty PVC storageClass not juicefs-sc:"
  BAD_PVCS="$(kubectl_cmd get pvc -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName' --no-headers \
    | awk '$3 != "" && $3 != "juicefs-sc" {print $0}')"
  if [ -n "$BAD_PVCS" ]; then
    echo "$BAD_PVCS"
  fi
  echo

  echo "PVC summary (first 20):"
  kubectl_cmd get pvc -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName' --no-headers | head -n 20
  echo

  if [ -n "$BAD_PVCS" ]; then
    echo "PVC audit failed: found PVC using non-juicefs-sc storageClass."
    exit 1
  fi
fi

echo "Verify check completed."

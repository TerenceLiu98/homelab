#!/usr/bin/env sh
set -eu

KUBECTL="kubectl"
if command -v k3s >/dev/null 2>&1; then
  KUBECTL="k3s kubectl"
fi

echo "== Nodes"
$KUBECTL get nodes -o wide

echo "== Cilium"
$KUBECTL -n kube-system get pods -l app.kubernetes.io/name=cilium-agent
$KUBECTL -n kube-system get pods -l app.kubernetes.io/name=cilium-operator --no-headers 2>/dev/null || true

echo "== Storage classes"
$KUBECTL get storageclass

LOCAL_PATH_SC="$($KUBECTL get storageclass -o jsonpath='{.items[?(@.metadata.name=="local-path")].metadata.name}')"
if [ -n "$LOCAL_PATH_SC" ]; then
  echo "Found local-path StorageClass in cluster: $LOCAL_PATH_SC"
  if $KUBECTL get sc local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -qi '^true$'; then
    echo "local-path is still default; this violates juicefs-only storage requirement." >&2
    echo "To fix: kubectl patch storageclass local-path -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' --type=merge" >&2
    exit 1
  fi
fi

DEFAULT_SC="$($KUBECTL get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')"
if [ "$DEFAULT_SC" != "juicefs-sc" ]; then
  echo "Default storageclass is not juicefs-sc: ${DEFAULT_SC}" >&2
  echo "Patch or set: kubectl patch storageclass juicefs-sc -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}' --type=merge" >&2
  exit 1
fi

echo "== JuiceFS CSI"
$KUBECTL -n kube-system get pods -l app.kubernetes.io/name=juicefs-csi-driver
$KUBECTL get storageclass juicefs-sc -o yaml | sed -n '1,200p'

echo "== Argo applications"
$KUBECTL -n argocd get applications -o wide

echo "== PVC storage classes (non-empty, non-juicefs-sc)"
BAD_PVCS="$($KUBECTL get pvc -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STORAGECLASS:.spec.storageClassName' --no-headers | awk '$3 != "" && $3 != "juicefs-sc" {print $0}')"
if [ -n "$BAD_PVCS" ]; then
  echo "$BAD_PVCS"
  echo "Found PVCs not using juicefs-sc." >&2
  exit 1
fi

echo "Done"

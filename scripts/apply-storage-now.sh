#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

if [ "$(id -u)" -eq 0 ]; then
  KUBECTL="k3s kubectl"
else
  KUBECTL="sudo k3s kubectl"
fi

rand() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '\n'
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

$KUBECTL create namespace storage --dry-run=client -o yaml | $KUBECTL apply -f -

if ! $KUBECTL -n storage get secret juicefs-secret >/dev/null 2>&1; then
  NODE_IP="10.42.0.1"
  if [ -f /etc/valkey/k3s-juicefs.pass ]; then
    REDIS_PASSWORD="$(cat /etc/valkey/k3s-juicefs.pass)"
  else
    REDIS_PASSWORD="$(rand)"
  fi
  $KUBECTL -n storage create secret generic juicefs-secret \
    --from-literal=name=k3s-jfs \
    --from-literal=redis-password="$REDIS_PASSWORD" \
    --from-literal=metaurl="redis://:${REDIS_PASSWORD}@${NODE_IP}:6379/1" \
    --from-literal=storage=file \
    --from-literal=bucket=/srv/k3s-data/gluster/mounts/gv0/juicefs-objects
fi

$KUBECTL apply -k platform/storage

echo "Storage manifests applied. Watch with: sudo k3s kubectl -n storage get pods -w"

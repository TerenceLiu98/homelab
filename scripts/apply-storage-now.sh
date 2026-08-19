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

NODE_IP="$(ip -4 addr show eno1 2>/dev/null | awk '/ inet / { sub("/.*", "", $2); print $2; exit }')"
NODE_IP="${NODE_IP:-192.168.2.153}"

if [ -f /etc/valkey/k3s-juicefs.pass ]; then
  REDIS_PASSWORD="$(cat /etc/valkey/k3s-juicefs.pass)"
else
  REDIS_PASSWORD="$(rand)"
fi

$KUBECTL -n kube-system create secret generic juicefs-sc-secret \
  --from-literal=name=juicefs \
  --from-literal=metaurl="redis://:${REDIS_PASSWORD}@${NODE_IP}:6379/1" \
  --from-literal=storage=gluster \
  --from-literal=bucket="${NODE_IP}/gv0/juicefs-objects" \
  --from-literal='envs={JFS_DROP_OSCACHE: 1}' \
  --dry-run=client -o yaml | $KUBECTL apply -f -

$KUBECTL apply -k platform/storage

echo "Storage manifests applied. Watch with: sudo k3s kubectl -n storage get pods -w"

#!/usr/bin/env sh
set -eu

# Full homelab bring-up entrypoint.
# Run on optiplex5060 as root after pulling repo changes.

: "${MASTER_IP:=100.118.192.86}"
: "${WORKER_IPS-100.121.31.95 100.85.172.81}"
: "${REMOTE_USER:=terenceliu}"
: "${SKIP_HOST_STORAGE_PREP:=0}"
: "${BASE_DOMAIN:=erotica.icu}"
: "${CERT_FILE:=/home/terenceliu/acme/ssl/${BASE_DOMAIN}.full.pem}"
: "${KEY_FILE:=/home/terenceliu/acme/ssl/${BASE_DOMAIN}.key}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root on the master node ${MASTER_IP}." >&2
  exit 1
fi

if [ "$SKIP_HOST_STORAGE_PREP" = "1" ]; then
  echo "[1/6] Skip host storage prepare (SKIP_HOST_STORAGE_PREP=1)"
else
  echo "[1/6] Prepare host storage on ${MASTER_IP}"
  scripts/prepare-host-storage.sh --device /dev/sda --yes
fi

echo "[2/6] Deploy k3s + Cilium + join workers"
if [ "$SKIP_HOST_STORAGE_PREP" = "1" ]; then
  SKIP_HOST_STORAGE_CHECK=1
else
  SKIP_HOST_STORAGE_CHECK=0
fi
WORKER_IPS="$WORKER_IPS" REMOTE_USER="$REMOTE_USER" MASTER_IP="$MASTER_IP" \
  SKIP_HOST_STORAGE_CHECK="$SKIP_HOST_STORAGE_CHECK" scripts/redeploy-k3s.sh

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
  echo "[3/6] Apply TLS source secret"
  scripts/apply-erotica-tls-source.sh "$CERT_FILE" "$KEY_FILE"
else
  echo "[3/6] TLS cert/key not found, skipping. Place them at ${CERT_FILE} and ${KEY_FILE} before running Kyverno policy."
fi

echo "[4/6] Materialize repo placeholders"
scripts/materialize-config.sh --in-place

echo "[5/6] Bootstrap Argo CD + root application"
scripts/bootstrap.sh

echo "[6/6] Verify juicefs storage and cluster readiness"
scripts/verify-k3s-juicefs.sh

echo "Done."

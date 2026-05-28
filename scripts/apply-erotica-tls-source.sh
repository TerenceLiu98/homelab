#!/usr/bin/env sh
set -eu

CERT_FILE="${1:-/home/terenceliu/acme/ssl/erotica.icu.full.pem}"
KEY_FILE="${2:-/home/terenceliu/acme/ssl/erotica.icu.key}"
NAMESPACE=kyverno
SECRET_NAME=erotica-icu-tls

if [ ! -f "$CERT_FILE" ]; then
  echo "Certificate file not found: $CERT_FILE" >&2
  exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "Private key file not found: $KEY_FILE" >&2
  exit 1
fi

sudo k3s kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | sudo k3s kubectl apply -f -
sudo k3s kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
  --cert="$CERT_FILE" \
  --key="$KEY_FILE" \
  --dry-run=client \
  -o yaml | sudo k3s kubectl apply -f -

echo "Applied source TLS secret ${NAMESPACE}/${SECRET_NAME}"

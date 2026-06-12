#!/usr/bin/env sh
set -eu

MASTER_IP="${MASTER_IP:-100.118.192.86}"
WORKER_IPS="${WORKER_IPS:-100.121.31.95 100.85.172.81}"
REMOTE_USER="${REMOTE_USER:-terenceliu}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10}"
SSH_BIN="${SSH_BIN:-ssh}"
NODE_TOKEN="${NODE_TOKEN:-}"

if [ ! -x "$(command -v "$SSH_BIN" )" ]; then
  echo "ssh client not found: $SSH_BIN" >&2
  exit 1
fi

if [ -z "${NODE_TOKEN}" ]; then
  if [ -f /var/lib/rancher/k3s/server/node-token ]; then
    NODE_TOKEN="$(cat /var/lib/rancher/k3s/server/node-token)"
  elif command -v sudo >/dev/null 2>&1; then
    NODE_TOKEN="$(sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || true)"
  fi
fi

if [ -z "${NODE_TOKEN}" ] && [ -f /tmp/k3s-node-token ]; then
  NODE_TOKEN="$(cat /tmp/k3s-node-token)"
fi

if [ -z "${NODE_TOKEN}" ]; then
  echo "Could not determine k3s node token. Ensure this is run on the k3s server." >&2
  exit 1
fi

echo "Joining workers into https://$MASTER_IP:6443"
echo "Token: ${NODE_TOKEN}" | sed 's/.\{20\}/& /g' | sed 's/\(.*\) .*/\1.../'

for ip in $WORKER_IPS; do
  echo "---"
  echo "[$ip] checking SSH reachability"
  if ! $SSH_BIN $SSH_OPTS ${REMOTE_USER}@${ip} 'true' >/dev/null 2>&1; then
    echo "[$ip] SSH unreachable. Run manually on that host:"
    cat <<EOF
curl -sfL https://get.k3s.io | \
  K3S_URL=https://$MASTER_IP:6443 \
  K3S_TOKEN='$NODE_TOKEN' \
  INSTALL_K3S_EXEC='agent --node-ip $ip --node-external-ip $ip' sh -
EOF
    continue
  fi

  echo "[$ip] installing k3s agent"
  if $SSH_BIN $SSH_OPTS ${REMOTE_USER}@${ip} \
    "curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN='${NODE_TOKEN}' INSTALL_K3S_EXEC='agent --node-ip ${ip} --node-external-ip ${ip}' sh -"; then
    echo "[$ip] joined."
  else
    echo "[$ip] join command failed." >&2
  fi

done

echo "Done. Verify:"
echo "  k3s kubectl get nodes -o wide"

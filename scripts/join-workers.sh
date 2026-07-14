#!/usr/bin/env sh
set -eu

MASTER_IP="${MASTER_IP:-100.118.192.86}"
WORKER_IPS="${WORKER_IPS:-100.91.121.121}"
REMOTE_USER="${REMOTE_USER:-terenceliu}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10}"
SSH_BIN="${SSH_BIN:-ssh}"
KUBECTL="${KUBECTL:-sudo k3s kubectl}"
NODE_TOKEN="${NODE_TOKEN:-}"
AGENT_DATA_DIR="${AGENT_DATA_DIR:-/srv/k3s-agent}"
K3S_VERSION="${K3S_VERSION:-}"

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

if [ -z "${K3S_VERSION}" ] && command -v k3s >/dev/null 2>&1; then
  K3S_VERSION="$(k3s --version | awk 'NR == 1 { print $3 }')"
fi

if [ -z "${K3S_VERSION}" ]; then
  echo "Could not determine the k3s server version. Set K3S_VERSION explicitly." >&2
  exit 1
fi

echo "Joining workers into https://$MASTER_IP:6443 with k3s $K3S_VERSION"
echo "Token: ${NODE_TOKEN}" | sed 's/.\{20\}/& /g' | sed 's/\(.*\) .*/\1.../'

for ip in $WORKER_IPS; do
  AGENT_EXEC="agent --node-ip ${ip} --node-external-ip ${ip} --data-dir ${AGENT_DATA_DIR} --node-label kubeflow-compute=true --node-taint workload=kubeflow:NoSchedule --kubelet-arg image-gc-high-threshold=75 --kubelet-arg image-gc-low-threshold=65 --kubelet-arg eviction-hard=memory.available<1Gi,nodefs.available<10%,imagefs.available<15%"
  echo "---"
  echo "[$ip] checking SSH reachability"
  if ! $SSH_BIN $SSH_OPTS ${REMOTE_USER}@${ip} 'true' >/dev/null 2>&1; then
    echo "[$ip] SSH unreachable. Run manually on that host:"
    cat <<EOF
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION='$K3S_VERSION' \
  K3S_URL=https://$MASTER_IP:6443 \
  K3S_TOKEN='$NODE_TOKEN' \
  INSTALL_K3S_EXEC='$AGENT_EXEC' sh -
EOF
    continue
  fi

  echo "[$ip] cleaning old Cilium iptables backup chains"
  $SSH_BIN $SSH_OPTS ${REMOTE_USER}@${ip} \
    'for table in nat filter mangle raw; do for chain in OLD_CILIUM_PRE_nat OLD_CILIUM_POST_nat OLD_CILIUM_OUTPUT_nat OLD_CILIUM_INPUT OLD_CILIUM_OUTPUT OLD_CILIUM_FORWARD; do if sudo iptables -t "$table" -S "$chain" >/dev/null 2>&1; then sudo iptables -t "$table" -F "$chain" || true; sudo iptables -t "$table" -X "$chain" || true; fi; done; done' || true

  echo "[$ip] installing k3s agent"
  if $SSH_BIN $SSH_OPTS ${REMOTE_USER}@${ip} \
    "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${K3S_VERSION}' K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN='${NODE_TOKEN}' INSTALL_K3S_EXEC='${AGENT_EXEC}' sh -"; then
    echo "[$ip] joined."
    node_name="$(${KUBECTL} get nodes -o wide --no-headers | awk -v ip="$ip" '$0 ~ ip { print $1; exit }')"
    if [ -n "$node_name" ]; then
      echo "[$ip] labeling node $node_name as kubeflow-compute=true"
      ${KUBECTL} label node "$node_name" kubeflow-compute=true --overwrite
      ${KUBECTL} taint node "$node_name" workload=kubeflow:NoSchedule --overwrite
    else
      echo "[$ip] node not visible yet; label it later with: ${KUBECTL} label node <node-name> kubeflow-compute=true --overwrite" >&2
    fi
  else
    echo "[$ip] join command failed." >&2
  fi

done

echo "Done. Verify:"
echo "  k3s kubectl get nodes -o wide"
echo "  k3s kubectl get nodes -l kubeflow-compute=true"

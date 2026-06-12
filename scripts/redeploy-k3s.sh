#!/usr/bin/env sh
set -eu

MASTER_IP="${MASTER_IP:-100.118.192.87}"
WORKER_IPS="${WORKER_IPS-100.121.31.95 100.85.172.81}"
REMOTE_USER="${REMOTE_USER:-terenceliu}"
[ -z "${REMOTE_SSH:-}" ] && REMOTE_SSH="ssh -F /dev/null -o StrictHostKeyChecking=no"
INSTALL_HELM="${INSTALL_HELM:-1}"
UNINSTALL_PREVIOUS="${UNINSTALL_PREVIOUS:-1}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root on optiplex5060." >&2
  exit 1
fi

KUBECTL="kubectl"
if command -v k3s >/dev/null 2>&1; then
  KUBECTL="k3s kubectl"
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required. Install it first (scripts/install-host-tools-arch.sh)." >&2
  exit 1
fi

uninstall_node() {
  ip="$1"
  ${REMOTE_SSH} "${REMOTE_USER}@${ip}" "if command -v k3s >/dev/null 2>&1; then if [ -x /usr/local/bin/k3s-agent-uninstall.sh ]; then /usr/local/bin/k3s-agent-uninstall.sh; else k3s-killall.sh || true; fi; fi"
}

if [ "$UNINSTALL_PREVIOUS" = "1" ]; then
  if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
    /usr/local/bin/k3s-uninstall.sh || true
  fi

  for ip in $WORKER_IPS; do
    uninstall_node "$ip"
  done
fi

if [ "${SKIP_HOST_STORAGE_CHECK:-0}" != "1" ]; then
  if [ ! -d /srv/k3s-data/gluster/mounts/gv0 ]; then
    echo "Host JuiceFS Gluster mount not found: /srv/k3s-data/gluster/mounts/gv0" >&2
    echo "Run scripts/prepare-host-storage.sh --device /dev/sda --yes first, or set SKIP_HOST_STORAGE_CHECK=1 to continue." >&2
    exit 1
  fi
fi

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --node-ip ${MASTER_IP} --node-external-ip ${MASTER_IP} --advertise-address ${MASTER_IP} --tls-san ${MASTER_IP} --flannel-backend=none --disable-network-policy --disable local-storage --write-kubeconfig-mode 0644" \
  sh -

if command -v k3s >/dev/null 2>&1; then
  KUBECTL="k3s kubectl"
fi

if [ "$INSTALL_HELM" = "1" ]; then
  helm upgrade --install cilium cilium --repo https://helm.cilium.io --namespace kube-system --create-namespace \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --set k8sServiceHost="${MASTER_IP}" \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set operator.replicas=1 \
    --set cni.confPath=/etc/cni/net.d \
    --set cni.binPath=/opt/cni/bin
  if command -v cilium >/dev/null 2>&1; then
    cilium status --wait
  else
    echo "cilium CLI not found, waiting for Cilium pods to become Ready."
    ${KUBECTL} -n kube-system wait --for=condition=ready pod -l app.kubernetes.io/name=cilium --timeout=180s
  fi
fi

scripts/patch-metrics-server-tailscale.sh

for ip in $WORKER_IPS; do
  NODE_TOKEN="$(cat /var/lib/rancher/k3s/server/node-token)"
  ${REMOTE_SSH} "${REMOTE_USER}@${ip}" "curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN='${NODE_TOKEN}' INSTALL_K3S_EXEC='agent --node-ip ${ip} --node-external-ip ${ip}' sh -"
done

scripts/prepare-host-redis.sh "${MASTER_IP}"
scripts/apply-storage-now.sh

echo "k3s redeploy complete. Run:"
echo "  sudo k3s kubectl get nodes -o wide"
echo "  sudo k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium"
echo "  sudo k3s kubectl -n kube-system get pods -l app.kubernetes.io/name=juicefs-csi-driver"
echo "  sudo k3s kubectl get storageclass"

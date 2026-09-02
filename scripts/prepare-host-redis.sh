#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

if [ "${1:-}" ]; then
  NODE_IP="$1"
else
  NODE_IP="$(ip -4 addr show eno1 2>/dev/null | awk '/ inet / { sub("/.*", "", $2); print $2; exit }')"
  NODE_IP="${NODE_IP:-192.168.2.153}"
fi
CNI_IP="${CNI_IP:-$(ip -4 addr show cilium_host 2>/dev/null | awk '/ inet / { sub("/.*", "", $2); print $2; exit }')}"
PASS_FILE=/etc/valkey/k3s-juicefs.pass
CONF=/etc/valkey/valkey.conf
DATA_DIR=/var/lib/valkey/juicefs

if [ ! -f "$CONF" ]; then
  echo "$CONF does not exist; install valkey or redis first." >&2
  exit 1
fi

mkdir -p "$DATA_DIR"
# Avoid copy-on-write amplification for Valkey persistence when the system disk
# supports the NoCoW directory attribute (for example, Btrfs).
if command -v chattr >/dev/null 2>&1; then
  chattr +C "$DATA_DIR" 2>/dev/null || true
fi
chown valkey:valkey "$DATA_DIR"
chmod 0750 "$DATA_DIR"

if [ ! -f "$PASS_FILE" ]; then
  umask 077
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 > "$PASS_FILE"
  else
    date +%s%N | sha256sum | awk '{print $1}' > "$PASS_FILE"
  fi
fi
chmod 0600 "$PASS_FILE"

PASSWORD="$(cat "$PASS_FILE")"
cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
sed -i '/^# BEGIN K3S JUICEFS$/,/^# END K3S JUICEFS$/d' "$CONF"
cat >> "$CONF" <<EOF

# BEGIN K3S JUICEFS
bind 127.0.0.1 ${CNI_IP:+${CNI_IP} }${NODE_IP}
protected-mode yes
port 6379
dir ${DATA_DIR}
appendonly yes
save 60 1000
maxmemory-policy noeviction
requirepass ${PASSWORD}
# END K3S JUICEFS
EOF

systemctl enable --now valkey.service
systemctl restart valkey.service

echo "Host Redis-compatible metadata service is running on ${NODE_IP}:6379"
echo "Password is stored in ${PASS_FILE}"

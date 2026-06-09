#!/usr/bin/env sh
set -eu

DEVICE=/dev/sda
CONFIRM=no

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --yes)
      CONFIRM=yes
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

if [ "$CONFIRM" != yes ]; then
  echo "Refusing to continue without --yes because this repartitions $DEVICE." >&2
  exit 1
fi

if findmnt -rn "$DEVICE" >/dev/null 2>&1; then
  echo "$DEVICE is mounted; refusing to repartition." >&2
  exit 1
fi

if ! lsblk "$DEVICE" >/dev/null 2>&1; then
  echo "$DEVICE does not exist." >&2
  exit 1
fi

parted -s "$DEVICE" mklabel gpt
parted -s "$DEVICE" mkpart primary ext4 1MiB 100%
partprobe "$DEVICE"
sleep 2

PART="${DEVICE}1"
if [ ! -b "$PART" ]; then
  echo "$PART was not created." >&2
  exit 1
fi

mkfs.ext4 -F -L k3s-data "$PART"
mkdir -p /srv/k3s-data

UUID="$(blkid -s UUID -o value "$PART")"
if ! grep -q "$UUID" /etc/fstab; then
  printf 'UUID=%s /srv/k3s-data ext4 defaults,noatime 0 2\n' "$UUID" >> /etc/fstab
fi

mount /srv/k3s-data

mkdir -p \
  /srv/k3s-data/gluster/bricks/gv0 \
  /srv/k3s-data/gluster/mounts/gv0 \
  /srv/k3s-data/juicefs-cache \
  /srv/k3s-data/gluster/mounts/gv0/juicefs-objects \
  /srv/k3s-data/backups

chmod 0775 /srv/k3s-data /srv/k3s-data/juicefs-cache /srv/k3s-data/gluster/mounts/gv0/juicefs-objects

if command -v systemctl >/dev/null 2>&1 && command -v glusterd >/dev/null 2>&1; then
  systemctl enable --now glusterd
  gluster volume info gv0 >/dev/null 2>&1 || \
    gluster volume create gv0 "$(hostname)":/srv/k3s-data/gluster/bricks/gv0 force
  gluster volume start gv0 || true
  gluster volume set gv0 storage.owner-uid 0
  gluster volume set gv0 storage.owner-gid 0
  if ! findmnt -rn /srv/k3s-data/gluster/mounts/gv0 >/dev/null 2>&1; then
    mount -t glusterfs "$(hostname)":/gv0 /srv/k3s-data/gluster/mounts/gv0
  fi
  mkdir -p /srv/k3s-data/gluster/mounts/gv0/juicefs-objects
  chmod 0775 /srv/k3s-data/gluster/mounts/gv0/juicefs-objects
  if ! grep -q '/srv/k3s-data/gluster/mounts/gv0' /etc/fstab; then
    printf '%s:/gv0 /srv/k3s-data/gluster/mounts/gv0 glusterfs defaults,_netdev 0 0\n' "$(hostname)" >> /etc/fstab
  fi
else
  echo "glusterd is not installed; install glusterfs and rerun this script to create gv0." >&2
fi

echo "Host storage prepared at /srv/k3s-data"

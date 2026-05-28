#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

pacman -Sy --needed --noconfirm helm kustomize argocd glusterfs redis

if ! command -v juicefs >/dev/null 2>&1; then
  echo "Install JuiceFS from your preferred Arch/AUR source, then rerun verification." >&2
fi


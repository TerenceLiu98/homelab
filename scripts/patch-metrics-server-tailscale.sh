#!/usr/bin/env sh
set -eu

if command -v k3s >/dev/null 2>&1; then
  KUBECTL="k3s kubectl"
else
  KUBECTL="kubectl"
fi

if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && command -v k3s >/dev/null 2>&1; then
  KUBECTL="sudo $KUBECTL"
fi

$KUBECTL -n kube-system patch deployment metrics-server --type=json -p='[
  {"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
  {"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"},
  {"op":"replace","path":"/spec/template/spec/containers/0/args/1","value":"--secure-port=10251"},
  {"op":"replace","path":"/spec/template/spec/containers/0/ports/0/containerPort","value":10251}
]'

$KUBECTL -n kube-system rollout status deployment/metrics-server --timeout=180s

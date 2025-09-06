#!/usr/bin/env bash
set -euo pipefail

# ===============================
# 00-bind-k3s-ip-remote
# Preps the k3s VM to bind on host-only IP and fetches a kubeconfig
# ===============================

# --- Config (override via env if needed) ---
K3S_HOST="${K3S_HOST:-user@192.168.56.102}"   # SSH target for your k3s VM
HOSTONLY_IFACE="${HOSTONLY_IFACE:-enp0s8}"
HOSTONLY_IP="${HOSTONLY_IP:-192.168.56.102}"
KCFG_OUT="${KCFG_OUT:-$(pwd)/k3s-jenkins.yaml}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "[00-bind-k3s-ip-remote] Target: ${K3S_HOST}  iface=${HOSTONLY_IFACE} ip=${HOSTONLY_IP}"

# --- Ask once for sudo password on the k3s VM (or set K3S_SUDO_PASS in env) ---
if [[ -z "${K3S_SUDO_PASS:-}" ]]; then
  read -r -s -p "[00-bind-k3s-ip-remote] Enter sudo password for ${K3S_HOST}: " K3S_SUDO_PASS
  echo
fi

# 1) Verify remote interface/IP
ssh ${SSH_OPTS} "${K3S_HOST}" "ip -br a show ${HOSTONLY_IFACE}"
ssh ${SSH_OPTS} "${K3S_HOST}" "ip -br a show ${HOSTONLY_IFACE} | grep -q '${HOSTONLY_IP}/'"

# 2) Create local temp config and copy to remote
TMP_CFG="$(mktemp)"
cat > "${TMP_CFG}" <<CFG
node-ip: ${HOSTONLY_IP}
advertise-address: ${HOSTONLY_IP}
tls-san:
  - ${HOSTONLY_IP}
flannel-iface: ${HOSTONLY_IFACE}
CFG
scp ${SSH_OPTS} "${TMP_CFG}" "${K3S_HOST}:/tmp/k3s-config.yaml"
rm -f "${TMP_CFG}"

# 3) Install config & restart k3s (sudo on remote)
printf '%s\n' "${K3S_SUDO_PASS}" | ssh ${SSH_OPTS} "${K3S_HOST}" "sudo -S bash -c '
  set -euo pipefail
  mkdir -p /etc/rancher/k3s
  install -m 0644 /tmp/k3s-config.yaml /etc/rancher/k3s/config.yaml
  systemctl daemon-reexec
  systemctl restart k3s
'"

# 4) Wait for node Ready (best-effort) and show status
ssh ${SSH_OPTS} "${K3S_HOST}" "kubectl wait --for=condition=Ready node --all --timeout=180s || true"
ssh ${SSH_OPTS} "${K3S_HOST}" "kubectl get nodes -o wide || true"

# 5) Fetch kubeconfig into this repo & patch server URL
scp ${SSH_OPTS} "${K3S_HOST}:/etc/rancher/k3s/k3s.yaml" "${KCFG_OUT}"
sed -i "s#server: https://[^:]*:6443#server: https://${HOSTONLY_IP}:6443#" "${KCFG_OUT}"

# 6) Local kubectl sanity (avoid Jenkins proxy)
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY="${HOSTONLY_IP}"

KUBECONFIG="${KCFG_OUT}" kubectl cluster-info
KUBECONFIG="${KCFG_OUT}" kubectl get nodes -o wide

echo
echo "[00-bind-k3s-ip-remote] Done. Use this kubeconfig now:"
echo "  export KUBECONFIG=${KCFG_OUT}"
echo


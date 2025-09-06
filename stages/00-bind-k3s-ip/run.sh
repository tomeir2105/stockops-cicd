#!/usr/bin/env bash
set -euo pipefail

# Settings (override via env if needed)
HOSTONLY_IFACE="${HOSTONLY_IFACE:-enp0s8}"
HOSTONLY_IP="${HOSTONLY_IP:-192.168.56.102}"
KCFG_OUT="${KCFG_OUT:-$(pwd)/k3s-jenkins.yaml}"
NODE_NAME="${NODE_NAME:-k3s}"   # change if your node shows a different name

echo "[00-bind-k3s-ip] Target: ${HOSTONLY_IFACE} ${HOSTONLY_IP}"

# 1) Sanity: verify interface/IP present
if ! ip -br a show "${HOSTONLY_IFACE}" | grep -q "${HOSTONLY_IP}/"; then
  echo "ERROR: ${HOSTONLY_IFACE} does not have ${HOSTONLY_IP}. Fix your host-only adapter first."
  ip -br a show "${HOSTONLY_IFACE}" || true
  exit 1
fi

# 2) Prepare k3s config (idempotent)
TMPCONF="$(mktemp)"
cat > "${TMPCONF}" <<YAML
node-ip: ${HOSTONLY_IP}
advertise-address: ${HOSTONLY_IP}
tls-san:
  - ${HOSTONLY_IP}
flannel-iface: ${HOSTONLY_IFACE}
YAML

echo "[00-bind-k3s-ip] Writing /etc/rancher/k3s/config.yaml (sudo)"
sudo mkdir -p /etc/rancher/k3s
if ! sudo test -f /etc/rancher/k3s/config.yaml || ! sudo cmp -s "${TMPCONF}" /etc/rancher/k3s/config.yaml; then
  sudo cp "${TMPCONF}" /etc/rancher/k3s/config.yaml
  echo "[00-bind-k3s-ip] Restarting k3s (sudo)"
  sudo systemctl daemon-reexec
  sudo systemctl restart k3s
else
  echo "[00-bind-k3s-ip] Config unchanged; skipping restart"
fi
rm -f "${TMPCONF}"

# 3) Remove stale duplicate node (best-effort)
kubectl get nodes >/dev/null 2>&1 || true
if kubectl get node userpc >/dev/null 2>&1; then
  echo "[00-bind-k3s-ip] Deleting stale node 'userpc'"
  kubectl delete node userpc || true
fi

# 4) Wait for node Ready on the right IP
echo "[00-bind-k3s-ip] Waiting for node to be Ready…"
kubectl wait --for=condition=Ready node --all --timeout=120s || true
echo
kubectl get nodes -o wide
echo

# 5) Create a kubeconfig INSIDE THE PROJECT and point it to 192.168.56.102
echo "[00-bind-k3s-ip] Exporting kubeconfig to ${KCFG_OUT}"
sudo cp /etc/rancher/k3s/k3s.yaml "${KCFG_OUT}"
sudo chown "$(id -u)":"$(id -g)" "${KCFG_OUT}"
sed -i "s#server: https://[^:]*:6443#server: https://${HOSTONLY_IP}:6443#" "${KCFG_OUT}"

# 6) Smoke test with the local kubeconfig
echo "[00-bind-k3s-ip] Smoke test with ${KCFG_OUT}"
KUBECONFIG="${KCFG_OUT}" kubectl cluster-info
KUBECONFIG="${KCFG_OUT}" kubectl get nodes -o wide

echo
echo "[00-bind-k3s-ip] Done. Use this kubeconfig:"
echo "  export KUBECONFIG=${KCFG_OUT}"
echo

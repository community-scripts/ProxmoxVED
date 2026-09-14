#!/usr/bin/env bash

set -euo pipefail

# Quick homelab bootstrap for a single-node management VM
# - Installs K3s (if missing)
# - Installs Argo CD (optional)
# - Waits for core components to become ready
#
# Usage examples:
#   sudo bash k3s-argocd-bootstrap.sh
#   sudo INSTALL_ARGOCD=false bash k3s-argocd-bootstrap.sh
#   sudo K3S_VERSION="v1.34.1+k3s1" bash k3s-argocd-bootstrap.sh

K3S_VERSION="${K3S_VERSION:-v1.34.1+k3s1}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_MANIFEST_URL="${ARGOCD_MANIFEST_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"

log() {
  echo "[INFO] $*"
}

ok() {
  echo "[OK] $*"
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root (sudo)."
  fi
}

install_k3s_if_missing() {
  if command -v k3s >/dev/null 2>&1; then
    ok "K3s is already installed: $(k3s --version | head -n1)"
    return
  fi

  log "Installing K3s (${K3S_VERSION})"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -
  ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
  ok "K3s installed"
}

wait_for_k3s() {
  log "Waiting for K3s node readiness"
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  for _ in $(seq 1 90); do
    if kubectl get nodes >/dev/null 2>&1; then
      if kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
        ok "K3s node is Ready"
        return
      fi
    fi
    sleep 2
  done
  fail "K3s did not become Ready in time"
}

install_argocd() {
  if [[ "${INSTALL_ARGOCD}" != "true" ]]; then
    log "Skipping ArgoCD installation (INSTALL_ARGOCD=${INSTALL_ARGOCD})"
    return
  fi

  log "Installing ArgoCD into namespace ${ARGOCD_NAMESPACE}"
  kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST_URL}"

  log "Waiting for ArgoCD server deployment"
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deploy/argocd-server --timeout=10m
  ok "ArgoCD installed"
}

print_next_steps() {
  echo
  echo "---"
  echo "KUBECONFIG path: /etc/rancher/k3s/k3s.yaml"
  if [[ "${INSTALL_ARGOCD}" == "true" ]]; then
    echo "ArgoCD initial admin secret:"
    echo "  kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
    echo "Port-forward UI:"
    echo "  kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443"
  fi
  echo "Cluster check:"
  echo "  kubectl get nodes -o wide"
}

main() {
  require_root
  install_k3s_if_missing
  wait_for_k3s
  install_argocd
  print_next_steps
}

main "$@"

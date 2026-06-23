#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_CONFIG="${REPO_ROOT}/clusters/k3d-config.yaml"

CLUSTER_NAME="homelab"
ARGOCD_NAMESPACE="argocd"
ARGOCD_HELM_CHART_VERSION="5.46.8"
ARGOCD_HELM_REPO="https://argoproj.github.io/argo-helm"

log() {
  echo "[bootstrap] $*"
}

log_error() {
  echo "[bootstrap] ERROR: $*" >&2
}

check_requirements() {
  log "Checking requirements..."
  
  if ! command -v k3d &> /dev/null; then
    log_error "k3d not found. Install from https://k3d.io/v5.0.0/#installation"
    exit 1
  fi
  
  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Install from https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi
  
  if ! command -v helm &> /dev/null; then
    log_error "helm not found. Install from https://helm.sh/docs/intro/install/"
    exit 1
  fi
  
  log "All requirements met"
}

create_cluster() {
  log "Creating k3d cluster from ${CLUSTER_CONFIG}..."
  
  if k3d cluster get homelab &> /dev/null 2>&1; then
    log "Cluster ${CLUSTER_NAME} already exists, skipping creation"
  else
    k3d cluster create --config "${CLUSTER_CONFIG}"
    log "Cluster ${CLUSTER_NAME} created successfully"
  fi
  
  log "Waiting for cluster to be ready..."
  kubectl wait --for=condition=ready nodes --all --timeout=300s
  log "Cluster is ready"
}

install_argocd() {
  log "Installing ArgoCD..."
  
  log "Adding ArgoCD Helm repository..."
  helm repo add argo "${ARGOCD_HELM_REPO}"
  helm repo update
  
  log "Creating ${ARGOCD_NAMESPACE} namespace..."
  kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  
  log "Installing ArgoCD Helm chart version ${ARGOCD_HELM_CHART_VERSION}..."
  helm upgrade --install argocd argo/argo-cd \
    --namespace "${ARGOCD_NAMESPACE}" \
    --version "${ARGOCD_HELM_CHART_VERSION}" \
    --wait
  
  log "ArgoCD installed"
}

wait_for_argocd() {
  log "Waiting for ArgoCD to be healthy..."
  
  log "Waiting for ArgoCD deployments to be ready..."
  kubectl wait --for=condition=available \
    --timeout=300s \
    deployment \
    -l app.kubernetes.io/instance=argocd \
    -n "${ARGOCD_NAMESPACE}"
  
  log "ArgoCD is healthy"
}

get_argocd_info() {
  log "ArgoCD is ready!"
  
  ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  
  log "ArgoCD admin password: ${ARGOCD_PASSWORD}"
  log ""
  log "To access ArgoCD UI:"
  log "  kubectl port-forward -n ${ARGOCD_NAMESPACE} svc/argocd-server 8080:443"
  log "  Then open https://localhost:8080 in your browser"
  log "  Username: admin"
  log "  Password: ${ARGOCD_PASSWORD}"
}

cleanup() {
  log "Deleting cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}" || true
  log "Cluster deleted"
}

main() {
  log "Starting bootstrap..."
  
  check_requirements
  create_cluster
  install_argocd
  wait_for_argocd
  get_argocd_info
  
  log "Bootstrap complete!"
}

if [[ "${CLEANUP_ON_EXIT:-false}" == "true" ]]; then
  trap cleanup EXIT
fi

main

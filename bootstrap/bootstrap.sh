#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_CONFIG="${REPO_ROOT}/clusters/k3d-config.yaml"

CLUSTER_NAME="homelab"
ARGOCD_NAMESPACE="argocd"
ARGOCD_HELM_CHART_VERSION="5.46.8"
ARGOCD_HELM_REPO="https://argoproj.github.io/argo-helm"

MONITORING_NAMESPACE="monitoring"
GRAFANA_DEPLOYMENT="monitoring-grafana"
TEMPO_POD_LABEL="app.kubernetes.io/name=tempo"
LOGGING_NAMESPACE="logging"
LOKI_STATEFULSET="loki"

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

# Optional: trust an extra CA, for machines behind a TLS inspecting proxy
# (a company laptop, for example). Without it every image pull and every chart
# download inside the lab fails with "x509: certificate signed by unknown
# authority", even though docker pull works fine on the host.
#   EXTRA_CA_FILE=/path/to/proxy-root-ca.pem ./bootstrap/bootstrap.sh
# The script builds one bundle (system CAs plus the extra one) outside the repo
# and mounts it into the k3d nodes and into the ArgoCD repo server.
CA_BUNDLE="${HOME}/.cache/homelab/ca-bundle.pem"
K3D_EXTRA_ARGS=()
ARGOCD_EXTRA_VALUES=()

prepare_extra_ca() {
  if [[ -z "${EXTRA_CA_FILE:-}" ]]; then
    return
  fi
  if [[ ! -f "${EXTRA_CA_FILE}" ]]; then
    log_error "EXTRA_CA_FILE ${EXTRA_CA_FILE} does not exist"
    exit 1
  fi
  log "Building a CA bundle with ${EXTRA_CA_FILE}..."
  mkdir -p "$(dirname "${CA_BUNDLE}")"
  local system_bundle=/etc/ssl/cert.pem
  [[ -f "${system_bundle}" ]] || system_bundle=/etc/ssl/certs/ca-certificates.crt
  cat "${system_bundle}" "${EXTRA_CA_FILE}" > "${CA_BUNDLE}"
  K3D_EXTRA_ARGS=(--volume "${CA_BUNDLE}:/etc/ssl/certs/ca-certificates.crt@all")
  ARGOCD_EXTRA_VALUES=(--values "${REPO_ROOT}/bootstrap/argocd-extra-ca-values.yaml")
}

create_extra_ca_configmap() {
  if [[ -z "${EXTRA_CA_FILE:-}" ]]; then
    return
  fi
  kubectl create configmap extra-ca -n "${ARGOCD_NAMESPACE}" \
    --from-file=ca-bundle.pem="${CA_BUNDLE}" \
    --dry-run=client -o yaml | kubectl apply --server-side -f -
  # Server-side apply on purpose: the bundle is bigger than the 256 KiB
  # last-applied annotation that a client-side apply would write.
}

create_cluster() {
  log "Creating k3d cluster from ${CLUSTER_CONFIG}..."

  if k3d cluster get homelab &> /dev/null 2>&1; then
    log "Cluster ${CLUSTER_NAME} already exists, skipping creation"
  else
    k3d cluster create --config "${CLUSTER_CONFIG}" ${K3D_EXTRA_ARGS[@]+"${K3D_EXTRA_ARGS[@]}"}
    log "Cluster ${CLUSTER_NAME} created successfully"
  fi
  
  log "Waiting for API server to be reachable..."
  for i in $(seq 1 30); do
    if kubectl cluster-info &>/dev/null; then
      break
    fi
    if [[ ${i} -eq 30 ]]; then
      log_error "API server did not become reachable after 60s"
      exit 1
    fi
    sleep 2
  done

  log "Waiting for nodes to be ready..."
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
  create_extra_ca_configmap

  log "Installing ArgoCD Helm chart version ${ARGOCD_HELM_CHART_VERSION}..."
  helm upgrade --install argocd argo/argo-cd \
    --namespace "${ARGOCD_NAMESPACE}" \
    --version "${ARGOCD_HELM_CHART_VERSION}" \
    --values "${REPO_ROOT}/bootstrap/argocd-values.yaml" \
    ${ARGOCD_EXTRA_VALUES[@]+"${ARGOCD_EXTRA_VALUES[@]}"} \
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

apply_root_app() {
  log "Applying root app-of-apps Application..."
  kubectl apply -f "${REPO_ROOT}/apps/root.yaml"
  log "Root Application applied. ArgoCD will discover and sync child apps automatically."
}

get_argocd_info() {
  log "ArgoCD is ready!"
  
  ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  
  log "ArgoCD admin password: ${ARGOCD_PASSWORD}"
  log ""
  log "ArgoCD UI (via Traefik ingress):"
  log "  http://argocd.127.0.0.1.nip.io"
  log "  Username: admin"
  log "  Password: ${ARGOCD_PASSWORD}"
  log ""
  log "Fallback (port-forward):"
  log "  kubectl port-forward -n ${ARGOCD_NAMESPACE} svc/argocd-server 8080:80"
  log "  Then open http://localhost:8080 in your browser"
  log ""
  log "To reach the demo app:"
  log "  kubectl port-forward -n demo svc/demo-app 8888:80"
  log "  Then open http://localhost:8888 in your browser"
}

deploy_monitoring() {
  log "Deploying monitoring stack via ArgoCD..."
  kubectl apply -f "${REPO_ROOT}/apps/monitoring/application.yaml"
  log "Monitoring Application manifest applied"
}

deploy_logging() {
  log "Deploying Loki and Alloy via ArgoCD..."
  kubectl apply -f "${REPO_ROOT}/apps/loki/application.yaml"
  kubectl apply -f "${REPO_ROOT}/apps/alloy/application.yaml"
  log "Loki and Alloy Application manifests applied"
}

wait_for_monitoring() {
  log "Waiting for ArgoCD to sync the monitoring stack..."

  local timeout=300
  local elapsed=0
  local interval=10

  log "Waiting for Grafana deployment to be created by ArgoCD..."
  until kubectl get deployment "${GRAFANA_DEPLOYMENT}" \
        -n "${MONITORING_NAMESPACE}" &>/dev/null; do
    if [[ ${elapsed} -ge ${timeout} ]]; then
      log_error "Timed out waiting for Grafana deployment to appear"
      kubectl get application monitoring -n "${ARGOCD_NAMESPACE}" -o yaml 2>/dev/null || true
      return 1
    fi
    log "  deployment not yet created (${elapsed}s elapsed), retrying..."
    sleep ${interval}
    elapsed=$((elapsed + interval))
  done

  log "Grafana deployment found. Waiting for it to become available..."
  kubectl wait --for=condition=available \
    --timeout=300s \
    "deployment/${GRAFANA_DEPLOYMENT}" \
    -n "${MONITORING_NAMESPACE}"

  log "Grafana is ready"
}

wait_for_loki() {
  log "Waiting for Loki to be ready..."

  local timeout=300
  local elapsed=0
  local interval=10

  log "Waiting for Loki StatefulSet pod to be created by ArgoCD..."
  until kubectl get statefulset "${LOKI_STATEFULSET}" \
        -n "${LOGGING_NAMESPACE}" &>/dev/null; do
    if [[ ${elapsed} -ge ${timeout} ]]; then
      log_error "Timed out waiting for Loki StatefulSet to appear"
      kubectl get application loki -n "${ARGOCD_NAMESPACE}" -o yaml 2>/dev/null || true
      return 1
    fi
    log "  StatefulSet not yet created (${elapsed}s elapsed), retrying..."
    sleep ${interval}
    elapsed=$((elapsed + interval))
  done

  log "Loki StatefulSet found. Waiting for pod to become ready..."
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=loki \
    -n "${LOGGING_NAMESPACE}" \
    --timeout=300s

  log "Loki is ready"
}

get_grafana_info() {
  log ""
  log "Grafana UI (via Traefik ingress):"
  log "  http://grafana.127.0.0.1.nip.io"
  log "  Username: admin"
  log "  Password: admin"
  log ""
  log "Fallback (port-forward):"
  log "  kubectl port-forward -n ${MONITORING_NAMESPACE} svc/${GRAFANA_DEPLOYMENT} 3000:80"
  log "  Then open http://localhost:3000 in your browser"
}

deploy_tempo() {
  log "Deploying Tempo via ArgoCD..."
  kubectl apply -f "${REPO_ROOT}/apps/tempo/application.yaml"
  log "Tempo Application manifest applied"
}

wait_for_tempo() {
  log "Waiting for ArgoCD to sync Tempo..."

  local timeout=300
  local elapsed=0
  local interval=10

  log "Waiting for Tempo pod to be created by ArgoCD..."
  until kubectl get pods -l "${TEMPO_POD_LABEL}" \
        -n "${MONITORING_NAMESPACE}" --no-headers 2>/dev/null | grep -q .; do
    if [[ ${elapsed} -ge ${timeout} ]]; then
      log_error "Timed out waiting for Tempo pod to appear"
      kubectl get application tempo -n "${ARGOCD_NAMESPACE}" -o yaml 2>/dev/null || true
      return 1
    fi
    log "  pod not yet created (${elapsed}s elapsed), retrying..."
    sleep ${interval}
    elapsed=$((elapsed + interval))
  done

  log "Tempo pod found. Waiting for it to become ready..."
  kubectl wait --for=condition=ready pod \
    -l "${TEMPO_POD_LABEL}" \
    -n "${MONITORING_NAMESPACE}" \
    --timeout=300s

  log "Tempo is ready"
}

deploy_beyla() {
  log "Deploying Beyla via ArgoCD..."
  kubectl apply -f "${REPO_ROOT}/apps/beyla/application.yaml"
  log "Beyla Application manifest applied"
}

wait_for_beyla() {
  log "Waiting for ArgoCD to sync Beyla..."

  local timeout=300
  local elapsed=0
  local interval=10

  until kubectl get daemonset beyla -n beyla &>/dev/null; do
    if [[ ${elapsed} -ge ${timeout} ]]; then
      log_error "Timed out waiting for the Beyla DaemonSet to appear"
      kubectl get application beyla -n "${ARGOCD_NAMESPACE}" -o yaml 2>/dev/null || true
      return 1
    fi
    log "  DaemonSet not yet created (${elapsed}s elapsed), retrying..."
    sleep ${interval}
    elapsed=$((elapsed + interval))
  done

  kubectl rollout status daemonset/beyla -n beyla --timeout=300s
  log "Beyla is ready. Traces of the demo app show up in Grafana, Explore, Tempo."
}

cleanup() {
  log "Deleting cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}" || true
  log "Cluster deleted"
}

main() {
  log "Starting bootstrap..."
  
  check_requirements
  prepare_extra_ca
  create_cluster
  install_argocd
  wait_for_argocd
  apply_root_app
  get_argocd_info
  deploy_monitoring
  wait_for_monitoring
  get_grafana_info
  deploy_logging
  wait_for_loki
  deploy_tempo
  wait_for_tempo
  deploy_beyla
  wait_for_beyla

  log "Bootstrap complete!"
}

if [[ "${CLEANUP_ON_EXIT:-false}" == "true" ]]; then
  trap cleanup EXIT
fi

main

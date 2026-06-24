#!/usr/bin/env bash
set -euo pipefail

K3D_VERSION="v5.6.0"
KUBECTL_VERSION="v1.28.6"
HELM_VERSION="v3.13.0"

install_k3d() {
  if command -v k3d >/dev/null 2>&1 && [[ "$(k3d version --short 2>/dev/null || true)" == "${K3D_VERSION}" ]]; then
    return
  fi
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/"${K3D_VERSION}"/install.sh | TAG="${K3D_VERSION}" bash
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1 && [[ "$(kubectl version --client --short 2>/dev/null | awk '{print $3}')" == "${KUBECTL_VERSION}" ]]; then
    return
  fi
  curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
}

install_helm() {
  if command -v helm >/dev/null 2>&1 && [[ "$(helm version --short 2>/dev/null | sed 's/+.*//' | cut -d'.' -f1-3)" == "${HELM_VERSION}" ]]; then
    return
  fi
  curl -fsSL -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tar -xzf /tmp/helm.tgz -C /tmp
  sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
  rm -rf /tmp/linux-amd64 /tmp/helm.tgz
}

wait_for_docker() {
  for _ in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  echo "Docker daemon did not become ready in time" >&2
  exit 1
}

main() {
  install_k3d
  install_kubectl
  install_helm
  wait_for_docker
  CLEANUP_ON_EXIT=false bash bootstrap/bootstrap.sh
}

main "$@"

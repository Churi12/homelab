# homelab

[![Launch in Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Churi12/homelab)

A reproducible homelab as code. Instead of a server running 24/7, this repo
defines a Kubernetes lab that can be stood up from scratch on demand, validated
in CI, and torn down. The pipeline is the proof that it works.

This is a personal learning project, built outside work, to get hands-on with
the cloud-native tools I care about: Kubernetes, GitOps with ArgoCD, and the
Grafana observability stack.

## Idea

- Everything is declarative and lives in git.
- A local Kubernetes cluster (k3d or kind, runs in Docker) is the target.
- GitHub Actions stands up the cluster on every push, installs the stack,
  checks it is healthy, then tears it down. A green run means the lab is
  reproducible from zero.
- You can run the exact same steps locally on your own machine.

## Status

Cluster boots with ArgoCD running and deploys a lightweight observability stack
(Prometheus + Grafana) via ArgoCD automatically.

## Launch in Codespaces

Click the Launch in Codespaces badge above to open this repo in a preconfigured
Codespace. The devcontainer starts with Docker-in-Docker enabled, installs the
pinned lab CLI versions (k3d v5.6.0, kubectl v1.28.6, helm v3.13.0), and runs
`bootstrap/bootstrap.sh` automatically.

After creation, the full lab should be ready in about 2 minutes, with ArgoCD,
Grafana, and the demo app accessible from the Codespaces Ports tab. No manual
port-forward commands are needed in Codespaces because ports are auto-forwarded.

## What this is not

It is not an always-on cluster. There is no public endpoint to log into. The
value is reproducibility and the documented learning, not uptime.

## App-of-apps pattern

ArgoCD uses the app-of-apps pattern: one root Application (apps/root.yaml)
watches the apps/ directory and automatically discovers and syncs every
Application manifest found there.

To add a new app, drop an ArgoCD Application manifest into apps/ and ArgoCD
will pick it up on its next sync. The new app points at whatever Kubernetes
manifests describe that workload.

## Get started locally

### Prerequisites

You need Docker, k3d, kubectl, and Helm installed on your machine.

- Docker: https://docs.docker.com/get-docker/
- k3d: https://k3d.io/v5.6.0/#installation
- kubectl: https://kubernetes.io/docs/tasks/tools/
- Helm: https://helm.sh/docs/intro/install/

### Run the bootstrap

The bootstrap script creates the cluster, installs ArgoCD, and applies the
root app-of-apps Application so ArgoCD discovers and syncs everything in apps/.

  git clone https://github.com/Churi12/homelab.git
  cd homelab
  ./bootstrap/bootstrap.sh

### Access ArgoCD

After the bootstrap completes, run this command in another terminal to access
the ArgoCD UI:

  kubectl port-forward -n argocd svc/argocd-server 8080:443

Then open https://localhost:8080 in your browser.

Username: admin
Password: printed by the bootstrap script

### Access Grafana

The bootstrap script also deploys Prometheus and Grafana through ArgoCD. Once
the bootstrap completes, run this command in another terminal to access Grafana:

  kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

Then open http://localhost:3000 in your browser.

Username: admin
Password: admin

The default dashboards include cluster resource usage panels (CPU, memory, and
pod status). Navigate to Dashboards to browse them.

### Access the demo app

After the bootstrap completes, run this command to reach the nginx demo app:

  kubectl port-forward -n demo svc/demo-app 8888:80

Then open http://localhost:8888 in your browser. You should see the nginx
welcome page.

### Validate manifests locally

The CI runs a fast validation job before the cluster boots. You can run the
same checks on your machine without Docker or a cluster.

Install the tools once (pinned to the same versions used in CI):

  KUBECONFORM_VERSION=v0.6.7
  curl -fsSL \
    "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" \
    | tar xz -C /usr/local/bin kubeconform

  KUBELINTER_VERSION=v0.6.8
  curl -fsSL \
    "https://github.com/stackrox/kube-linter/releases/download/${KUBELINTER_VERSION}/kube-linter-linux.tar.gz" \
    | tar xz -C /tmp kube-linter && sudo mv /tmp/kube-linter /usr/local/bin/

Then run the three validation steps from the repo root:

  # 1. Validate all Kubernetes manifests (including ArgoCD Application CRDs)
  find apps/ clusters/ \( -name '*.yaml' -o -name '*.yml' \) \
    | xargs grep -l '^apiVersion:' \
    | xargs kubeconform -strict -ignore-missing-schemas \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -summary

  # 2. Lint the monitoring chart values against the pinned chart version
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update prometheus-community
  helm pull prometheus-community/kube-prometheus-stack \
    --version 55.5.0 --untar --untardir /tmp/charts
  helm lint /tmp/charts/kube-prometheus-stack --values apps/monitoring/values.yaml

  # 3. Check plain Kubernetes manifests for best-practice issues
  kube-linter lint apps/demo-app/

All three steps must exit 0 before opening a pull request.

### Clean up

To manually delete the cluster, run:

  k3d cluster delete homelab

The cluster persists after the bootstrap script completes, so you can continue
to use it. In the GitHub Actions workflow, the cluster is automatically deleted
to keep the environment clean.

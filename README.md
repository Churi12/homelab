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

After the bootstrap completes, open the ArgoCD UI directly in your browser:

  http://argocd.127.0.0.1.nip.io

The nip.io hostname resolves to 127.0.0.1 automatically - no /etc/hosts edits needed.
k3d maps host port 80 to the Traefik ingress controller that k3s ships by default.

Username: admin
Password: printed by the bootstrap script

Fallback (port-forward):

  kubectl port-forward -n argocd svc/argocd-server 8080:80
  Then open http://localhost:8080 in your browser

### Access Grafana

The bootstrap script also deploys Prometheus and Grafana through ArgoCD. Once
the bootstrap completes, open Grafana directly in your browser:

  http://grafana.127.0.0.1.nip.io

Username: admin
Password: admin

The default dashboards include cluster resource usage panels (CPU, memory, and
pod status). Navigate to Dashboards to browse them.

Fallback (port-forward):

  kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
  Then open http://localhost:3000 in your browser

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

Then run the four validation steps from the repo root:

  # 1. Validate all Kubernetes manifests (including ArgoCD Application CRDs)
  find apps/ clusters/ \( -name '*.yaml' -o -name '*.yml' \) \
    | xargs grep -l '^apiVersion:' \
    | xargs kubeconform -strict -ignore-missing-schemas \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -summary

  # 2. Render every Helm Application with the values ArgoCD will apply
  pip install pyyaml
  hack/render_apps.py --out-dir /tmp/rendered

  # 3. Validate the rendered workloads, which is what lands in the cluster
  kubeconform -strict -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -summary /tmp/rendered/*.yaml

  # 4. Check plain Kubernetes manifests for best-practice issues
  kube-linter lint apps/demo-app/

All four steps must exit 0 before opening a pull request.

Step 2 is the one that catches values that the chart silently ignores: a key at
the wrong nesting level renders to nothing rather than failing, so reading the
rendered output is the only way to see what the cluster actually gets.

### Clean up

To manually delete the cluster, run:

  k3d cluster delete homelab

The cluster persists after the bootstrap script completes, so you can continue
to use it. In the GitHub Actions workflow, the cluster is automatically deleted
to keep the environment clean.

## Code quality

The repo uses yamllint and shellcheck to keep YAML consistent and catch shell
script issues before they are committed.

### Install pre-commit

  pip install pre-commit
  pre-commit install

After running `pre-commit install`, the hooks run automatically on every
`git commit`. To run them manually against all files at any time:

  pre-commit run --all-files

The hooks that run on each commit are:

- trailing-whitespace: removes trailing spaces from text files
- end-of-file-fixer: ensures every file ends with a newline
- check-added-large-files: blocks files larger than 500 kB
- yamllint: lints all YAML files using .yamllint
- shellcheck: static analysis of bootstrap/bootstrap.sh

The same yamllint and shellcheck checks run in the CI lint job on every push,
so a clean local pre-commit run means CI will also be green for those checks.

## Keeping the pins fresh

Everything this lab installs is pinned: the k3s image that sets the cluster
Kubernetes version, the ArgoCD chart, every Helm chart in apps/, the CLI tools
CI installs, the GitHub Actions, and the pre-commit hook revisions. Pinning is
what makes a run reproducible, and it is also what makes the repo go quietly
stale.

Renovate closes that gap. Its config lives in .github/renovate.json and it opens
one small PR per group of updates rather than a single unreviewable bump:

- helm charts: every chart under apps/ plus the ArgoCD chart, minor and patch
- kubernetes version: the k3s image and the kubectl CI pin, which move together
- ci tooling: k3d, helm, kubeconform, kube-linter, PyYAML, pre-commit hooks
- github actions: the actions used by the workflows
- major bumps are never grouped, so a breaking one is easy to close or revert

Renovate only proposes. CI is the gate that decides: every bump PR runs the
manifest validation job and the full bootstrap job, so a chart version that no
longer renders, or a k3s image the lab cannot boot on, fails before merge rather
than after.

Because Renovate can only bump a version where it can see it, versions live in
one place per tool: the env block, or a with: version key, or the pin in the
manifest. Do not repeat a version in a step name or a comment, or that copy will
drift.

Enabling Renovate is an owner action: install the free hosted Renovate GitHub App
on the repo. Until then this config does nothing. The first thing the app opens
is a Dependency Dashboard issue listing everything it found.

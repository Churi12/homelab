# homelab

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

Early scaffold. See the open issues for what is being built next.

## What this is not

It is not an always-on cluster. There is no public endpoint to log into. The
value is reproducibility and the documented learning, not uptime.

## Get started locally

### Prerequisites

You need Docker, k3d, kubectl, and Helm installed on your machine.

- Docker: https://docs.docker.com/get-docker/
- k3d: https://k3d.io/v5.6.0/#installation
- kubectl: https://kubernetes.io/docs/tasks/tools/
- Helm: https://helm.sh/docs/intro/install/

### Run the bootstrap

The bootstrap script creates the cluster, installs ArgoCD, and prints how to
access the UI.

  git clone https://github.com/Churi12/homelab.git
  cd homelab
  chmod +x bootstrap/bootstrap.sh
  ./bootstrap/bootstrap.sh

### Access ArgoCD

After the bootstrap completes, run this command in another terminal to access
the ArgoCD UI:

  kubectl port-forward -n argocd svc/argocd-server 8080:443

Then open https://localhost:8080 in your browser.

Username: admin
Password: printed by the bootstrap script

### Clean up

To manually delete the cluster, run:

  k3d cluster delete homelab

The cluster persists after the bootstrap script completes, so you can continue
to use it. In the GitHub Actions workflow, the cluster is automatically deleted
to keep the environment clean.

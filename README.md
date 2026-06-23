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

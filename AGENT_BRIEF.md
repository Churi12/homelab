# Agent brief

If you are an automated agent (for example the GitHub Copilot coding agent)
working in this repo, read this first. It tells you the goal, the constraints,
and how to deliver.

## Goal

Build a reproducible homelab as code. The end result is a Kubernetes lab that:

1. Runs on a local cluster in Docker (k3d preferred, kind is fine), so it needs
   no real hardware and no cloud account.
2. Uses GitOps with ArgoCD to deploy its workloads.
3. Can be stood up from scratch with a single bootstrap script, and the same
   steps run in GitHub Actions on every push to prove it is reproducible.

The owner runs nothing automatically. The owner reviews your pull request, then
runs the code themselves on a personal machine. So clarity and safety matter
more than cleverness.

## Hard constraints

- Local and free only. No cloud provider credentials, no paid services, no
  secrets. Everything must run with just Docker plus the standard CLI tools.
- Pin tool versions where you can, so a run today and a run next month behave
  the same.
- Do not add anything that needs an always-on server or a public endpoint.
- Plain text in commit messages and the PR body: no backticks, no apostrophes,
  no Co-Authored-By lines. Keep it simple and human.
- Keep each pull request small and focused on the one issue it addresses. Open
  it as a draft.

## Style

- Favor readable, well-commented YAML and shell over abstraction.
- Document every step in the README so a human can follow it by hand.
- When you make a non-obvious choice (k3d vs kind, a chart version, an app),
  write one line in the PR explaining why.

## Suggested layout

- bootstrap/    scripts that create the cluster and install ArgoCD
- clusters/     cluster definition (k3d config)
- apps/         ArgoCD applications (app of apps pattern)
- .github/workflows/   the CI workflow that stands the lab up and tears it down

This is a guide, not a rule. Improve on it if you have a better idea, and say so.

## Definition of done for the first task

See the open issue. In general: a green CI run that creates a cluster, installs
ArgoCD, and reports healthy, plus README steps a human can follow to do the same
locally.

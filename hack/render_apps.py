#!/usr/bin/env python3
"""Render every Helm-based ArgoCD Application in apps/ with its pinned chart.

Why this exists: the Applications in apps/ carry their Helm values inline, so a
plain YAML lint only proves the Application manifest itself is well formed. It
says nothing about whether those values are keys the chart actually reads, or
whether the chart can render at all. This script pulls each pinned chart and
renders it with the inline values, which is exactly what ArgoCD does before it
applies anything. The rendered output is then handed to kubeconform.

It also prints a manifest of every app, chart, and version, which the GitHub
Pages job reuses so the published stack table cannot drift from the manifests.

Usage:
  hack/render_apps.py --out-dir /tmp/rendered
  hack/render_apps.py --manifest-json /tmp/stack.json
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
APPS_DIR = REPO_ROOT / "apps"


def log(msg):
    print(f"[render-apps] {msg}", flush=True)


def find_applications():
    """Return every ArgoCD Application manifest under apps/, sorted by name."""
    candidates = sorted(set(APPS_DIR.glob("*.yaml")) | set(APPS_DIR.glob("*/*.yaml")))
    apps = []
    for path in candidates:
        try:
            docs = [d for d in yaml.safe_load_all(path.read_text()) if d]
        except yaml.YAMLError as exc:
            sys.exit(f"{path}: not parseable as YAML: {exc}")
        for doc in docs:
            if doc.get("kind") == "Application" and "argoproj.io" in doc.get("apiVersion", ""):
                apps.append((path, doc))
    return apps


def describe(doc):
    """Pull the bits we care about out of an Application spec."""
    source = doc["spec"]["source"]
    return {
        "name": doc["metadata"]["name"],
        "namespace": doc["spec"]["destination"].get("namespace", "default"),
        "chart": source.get("chart"),
        "repo_url": source["repoURL"],
        "version": source.get("targetRevision"),
        "values": source.get("helm", {}).get("values"),
        "path": source.get("path"),
    }


def helm_repo_add(repo_url, cache):
    """Add a chart repo once per run, using a name derived from the host."""
    if repo_url in cache:
        return cache[repo_url]
    name = repo_url.split("//", 1)[-1].split(".")[0].replace("/", "-")
    subprocess.run(["helm", "repo", "add", name, repo_url], check=True,
                   stdout=subprocess.DEVNULL)
    cache[repo_url] = name
    return name


def render(app, out_dir, repo_cache):
    """helm template the app and write the result. Returns the output path."""
    # Values go in a subdirectory so that out_dir/*.yaml matches only rendered
    # manifests. Callers glob that pattern and feed it straight to kubeconform,
    # which rejects any file without an apiVersion.
    values_dir = out_dir / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    values_file = values_dir / f"{app['name']}.yaml"
    values_file.write_text(app["values"] or "")

    repo_name = helm_repo_add(app["repo_url"], repo_cache)
    subprocess.run(["helm", "repo", "update", repo_name], check=True,
                   stdout=subprocess.DEVNULL)

    out_path = out_dir / f"{app['name']}.yaml"
    cmd = [
        "helm", "template", app["name"], f"{repo_name}/{app['chart']}",
        "--version", app["version"],
        "--namespace", app["namespace"],
        "--values", str(values_file),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log(f"FAIL {app['name']} ({app['chart']} {app['version']}) did not render")
        print(result.stderr, file=sys.stderr)
        return None
    out_path.write_text(result.stdout)
    kinds = [d["kind"] for d in yaml.safe_load_all(result.stdout) if d]
    log(f"OK   {app['name']:<12} {app['chart']}-{app['version']:<8} {len(kinds)} resources")
    return out_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="/tmp/rendered",
                        help="where to write rendered manifests")
    parser.add_argument("--manifest-json",
                        help="also write a JSON summary of every app to this path")
    args = parser.parse_args()

    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    apps = find_applications()
    if not apps:
        sys.exit("no ArgoCD Applications found under apps/ - wrong directory?")

    summary, failures, repo_cache = [], [], {}
    for path, doc in apps:
        app = describe(doc)
        rel = path.relative_to(REPO_ROOT)

        # The root app-of-apps points at this repo, not a chart, so there is
        # nothing to render. Record it and move on.
        if not app["chart"]:
            log(f"SKIP {app['name']:<12} not a Helm source ({app['repo_url']})")
            summary.append({**{k: app[k] for k in
                              ("name", "namespace", "version", "repo_url", "path")},
                            "chart": None, "manifest": str(rel), "rendered": False})
            continue

        out_path = render(app, out_dir, repo_cache)
        if out_path is None:
            failures.append(app["name"])
            continue
        summary.append({"name": app["name"], "namespace": app["namespace"],
                        "chart": app["chart"], "version": app["version"],
                        "repo_url": app["repo_url"], "path": app["path"],
                        "manifest": str(rel), "rendered": True})

    if args.manifest_json:
        pathlib.Path(args.manifest_json).write_text(json.dumps(summary, indent=2) + "\n")
        log(f"wrote manifest to {args.manifest_json}")

    if failures:
        sys.exit(f"[render-apps] {len(failures)} app(s) failed to render: {', '.join(failures)}")
    log(f"rendered {sum(1 for s in summary if s['rendered'])} app(s) into {out_dir}")


if __name__ == "__main__":
    main()

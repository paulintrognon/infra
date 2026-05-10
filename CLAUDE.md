# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Provisioning + cluster config for **a single Debian VPS on OVH** that Paulin owns. Two equally-weighted purposes:

1. **Educational** — learn the Kubernetes / Helm / OpenTofu / Ansible stack on real workloads.
2. **Practical** — host Paulin's personal TypeScript projects (Next.js, NestJS, static sites) **long-term**. Some projects carry non-trivial traffic. The VPS is expected to live **10+ years**.

Consequences for any work done here:

- Favor **stable, portable, well-documented** choices over cutting-edge or trendy ones — we will still be running this in 2036.
- **Robustness is not optional.** It's a learning box AND a production host. Don't downgrade resilience for "easier to learn." When the two pull apart, surface the trade-off.
- Skip multi-node patterns (HA, PDBs, anti-affinity, multi-AZ) — there is one box. Flag them as "would matter at >1 node" rather than implementing them.
- Per-project domains, not subdomains of a shared apex. There is **no "primary domain"** at the cluster level; app domains live with their app's Helm values.

## How to collaborate in this repo

Paulin is a developer **new to infra**. He's chosen this stack to learn it deliberately. The expectation across every interaction:

- **Explain the *why* before the *what*.** When introducing a k8s/Helm/Tofu/Ansible primitive, motivate it before showing the YAML. When skipping a "best practice" that doesn't apply at this scale, say so explicitly.
- **Don't make architectural choices alone.** For anything non-trivial (new component, version pin on something load-bearing, directory layout, naming conventions, secret-management approach, structural change), present realistic options with their trade-offs (cost, complexity, lock-in, learning value, robustness), give a recommendation with reasoning, and let Paulin choose. Use `AskUserQuestion` for crisp decisions, prose for open-ended ones. NOT a trigger: routine task edits, typos, idempotent reconciles, things memory has already settled.
- **Step by step beats big-bang changes.** Stop at meaningful checkpoints, explain what just happened, confirm direction before continuing.
- **Code comments here lean educational.** The existing `tasks/*.yml` have unusually long header comments explaining *why* each design choice was made. Keep that style — comments are part of the deliverable, not noise.

## Where to read before doing anything

The repo documents itself in file headers. Start here, in order:

- `README.md` — first-run setup, the three commands you'll actually type.
- `ansible/bootstrap.yml` (top-of-file comment) — the two-play structure and why it's re-runnable with one command. The single most important piece of design context.
- `ansible/inventory.example.yml` — inventory schema. Each variable's comment explains what it controls.
- `ansible/ansible.cfg` — why we set `ssh_args` / `ControlMaster` (these are also Ansible defaults; we set them explicitly so the file teaches).
- `ansible/tasks/*.yml` — each task file's header explains *why* its approach was chosen (sshd drop-ins beating cloud-init's, ufw-routed fail2ban bans, version-pinned k3s installer, etc.). When in doubt about a convention, the task that uses it explains it.

If a fact about current state seems missing here, it's because the code is the source of truth. Read the file, don't infer from this document.

## Tooling north star (aspirational, not committed)

These are the components Paulin intends to introduce over time. Each one is a future architectural conversation in itself — present options + trade-offs before adopting.

- **k3s + Traefik + local-path storage** — already in place.
- **Helm** — third-party charts (cert-manager, etc.) and a custom `ts-app` chart all his TS projects reuse.
- **cert-manager** — Let's Encrypt TLS for per-app domains.
- **OpenTofu** (NOT HashiCorp Terraform) — declarative DNS records and Helm releases. Use the `tofu` CLI and OpenTofu Registry. Directory will be named `terraform/` by convention.
- **Argo CD** — GitOps reconciliation from this repo, eventually.
- **Observability** — Prometheus / Grafana / Loki or similar; tool not yet picked.
- **Secret management** — possibly Infisical, possibly sealed-secrets, possibly SOPS+age. Open question.
- **Container registry** — GitHub Container Registry (`ghcr.io`).

## Constraints that aren't in the code

- **Single-tenant, single-node, single-owner.** Don't add namespacing, RBAC, ResourceQuotas, NetworkPolicies, or PDBs just because a textbook says to — flag them as "matters with multiple users / nodes / teams" instead.
- **`inventory.example.yml` is the source of truth for inventory schema.** Adding a new variable means adding it there with an explanatory comment, not just to a local `inventory.yml`.
- **`.terraform.lock.hcl` should be committed** when `terraform/` lands. `.gitignore` already excludes the working dir but keeps the lockfile.

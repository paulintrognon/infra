# DOCS — How this stack works

A walkthrough of what's running on the cluster, who installed it, and
how the pieces fit together. Aimed at developers new to Kubernetes /
Helm / Tofu / Argo CD.

Setup instructions: `README.md`. Future plans: `ROADMAP.md`.

## The stack at a glance

A single Debian VPS at OVH runs everything. The layers, from the
metal up:

```
┌──────────────────────────────────────────────────────────────┐
│  WORKLOADS                                                   │
│  paulintrognon.fr · plouf-plouf · (future apps)              │
├──────────────────────────────────────────────────────────────┤
│  ON-CLUSTER OPERATORS                                        │
│  Argo CD          ← GitOps reconciler                        │
│  cert-manager     ← TLS certificates                         │
│  Traefik          ← Ingress controller (bundled with k3s)    │
├──────────────────────────────────────────────────────────────┤
│  KUBERNETES                                                  │
│  k3s              ← single-node Kubernetes distribution      │
├──────────────────────────────────────────────────────────────┤
│  HOST                                                        │
│  Debian           ← OVH VPS, single node, hardened by        │
│                     Ansible                                  │
└──────────────────────────────────────────────────────────────┘
```

Three tools sit *outside* the cluster and put things into it:

- **Ansible** sets up Debian itself (firewall, SSH hardening, k3s
  install).
- **OpenTofu** installs cluster-level operators (cert-manager, Argo CD,
  the Argo CD root Application).
- **Argo CD**, once installed, manages every workload — replacing what
  used to be manual `kubectl apply`.

## The boot path: from empty VPS to running cluster

From fresh Debian to a cluster serving HTTPS traffic:

```
Local laptop                                Remote VPS
────────────                                ──────────
                                            Debian (fresh)
                                                 │
ansible-playbook bootstrap.yml ──ssh──>          │
                                                 ▼
                                            Debian (hardened)
                                            k3s (installed)
                                                 │
tofu apply ──k8s API via SSH tunnel──>           │
                                                 ▼
                                            cert-manager (live)
                                            Argo CD (live)
                                            Argo CD root App (live)
                                                 │
                                                 │ Argo CD polls
                                                 │ this repo
                                                 ▼
                                            Child Applications
                                            Workloads
```

### Step 1: Ansible hardens the VPS and installs k3s

Ansible is a configuration-management tool that runs tasks on a remote
machine over SSH. The playbook `ansible/bootstrap.yml` does two
things:

1. **System base.** Firewall (ufw), fail2ban, sshd hardening,
   unattended security upgrades, swap. Standard host hardening.

2. **k3s install.** Downloads and runs the k3s installer (pinned
   version). k3s is a lightweight Kubernetes distribution — single
   binary, no complex setup. Less robust than full Kubernetes, but a
   single-node cluster wouldn't benefit from the extra machinery
   anyway.

The playbook is safe to re-run anytime — it reconciles the VPS to the
desired state. Upgrades (e.g. bumping k3s) use the same command.

### Step 2: OpenTofu installs cluster-level operators

OpenTofu is an open-source fork of Terraform: declarative
infrastructure-as-code. You describe what should exist; it diffs
against reality and applies the changes.

Inside `terraform/`, three `.tf` files declare what should exist on
the cluster:

- `cert-manager.tf` → a Helm release of cert-manager.
- `argocd.tf` → a Helm release of Argo CD.
- `argocd-root-app.tf` → a Helm release of a tiny local chart whose
  only template is the **Argo CD root Application**.

Tofu state ("what Tofu previously created") lives in a Scaleway Object
Storage bucket. `tofu apply` installs all three.

### Step 3: cert-manager handles TLS

cert-manager is a Kubernetes *operator* — software that runs inside
the cluster and reconciles a specific kind of resource. It watches for
Ingress resources annotated with a `cluster-issuer` and requests TLS
certificates from Let's Encrypt. Issuance and renewal are automatic.

Two `ClusterIssuer` resources in `k8s/system/cert-manager/` connect
cert-manager to Let's Encrypt: one staging (for testing), one prod.
Applied with `kubectl apply` after cert-manager is live.

### Step 4: Traefik routes traffic in

Traefik is the cluster's **ingress controller** — receives HTTPS
requests from outside and routes them to the right Service. Bundled
with k3s, no separate install.

Per-app `Ingress` resources map a hostname to a Service. Each carries
a `cert-manager.io/cluster-issuer` annotation that triggers
cert-manager to issue a cert for that host.

### Step 5: Argo CD takes over

Argo CD is an operator that watches a git repo and makes the cluster
match it. **Commits become deploys** — no more manual `kubectl apply`.

When Argo CD installs, it adds new resource types to the cluster —
`Application` is the main one. An `Application` says "make folder X in
repo Y look like the cluster."

Two pieces of Argo CD machinery are installed together by Tofu:

1. **Argo CD itself** (`terraform/argocd.tf`). Controller pods, admin
   UI, new resource types.

2. **The root Application** (`terraform/argocd-root-app.tf`). A single
   `Application` that tells Argo CD to watch `argocd/apps/` in this
   repo. Every YAML in that folder becomes a *child Application*.

This is the **app-of-apps** pattern. Adding a new workload is a
single-file change in `argocd/apps/`; Argo CD discovers it
automatically.

## The deploy path: from code to cluster

After bootstrap, a deploy looks like:

```
Developer pushes to main
            │
            ▼
   Argo CD root App polls
   the repo (every ~3 min)
            │
            ▼
   Root App sees the change
   in argocd/apps/<app>.yaml
            │
            ▼
   Child Application reconciles
   k8s/apps/<app>/ → live cluster
            │
            ▼
   Workload updated, in-place
   rolling update of pods
```

Each app has its own CI that builds and pushes images to GitHub
Container Registry (GHCR). Image tags are bumped in this repo by hand
for now; ROADMAP Phase 4 covers the planned cross-repo automation.

### What an Application points at

Each child Application is a small YAML in `argocd/apps/`. It contains:

- **Source.** Repo URL, branch, and folder path containing the
  manifests Argo CD should reconcile (e.g. `k8s/apps/paulintrognon.fr/`).
- **Destination.** Cluster and namespace to apply them to (always the
  in-cluster API, namespace `default`).
- **Sync policy.** `automated` with `prune` + `selfHeal` once the app
  is adopted — this is what makes pushes auto-deploy.

The manifests are **raw Kubernetes YAML** — no templating engine on
top. Two apps was below the threshold where shared scaffolding pays
off. A custom `ts-app` Helm chart is planned if the app count grows.

### What "adoption" means

When an Application first syncs against resources that already exist
on the cluster (e.g. previously `kubectl apply`'d), Argo CD doesn't
re-create them. It **adopts** them — adds an
`argocd.argoproj.io/tracking-id` annotation to mark each as owned. No
pod restart, no downtime; pure metadata patch.

This is how Phase 2 onboarded paulintrognon.fr without interrupting
traffic.

## Components at a glance

| Component | Role | Where |
|---|---|---|
| Ansible | Configures the Debian VPS over SSH | `ansible/` |
| k3s | Single-node Kubernetes distribution | installed by Ansible |
| OpenTofu | Manages cluster-level operators | `terraform/` |
| Helm | Packages Kubernetes manifests as charts; used by Tofu | (Tofu provider) |
| cert-manager | Issues TLS certs via Let's Encrypt | `terraform/cert-manager.tf` |
| Traefik | Ingress (HTTP/S routing into the cluster) | bundled with k3s |
| Argo CD | GitOps reconciler | `terraform/argocd*.tf` + `argocd/` |
| Workloads | Per-app raw manifests | `k8s/apps/<app>/` |

## Key decisions

A short list of choices that shape everything above. Full context for
each lives in `ROADMAP.md` under "Architectural decisions."

- **D1: Tofu owns bootstrap, Argo CD owns workloads.** Tofu installs
  Argo CD itself and the root Application; Argo CD takes over from
  there. Avoids a chicken-and-egg on day 1 (Argo CD can't install
  itself).

- **D2: App-of-apps pattern, from day 1.** A root Application manages
  child Applications under `argocd/apps/`. Adding a workload is a
  single file change instead of a Tofu change.

- **D3: Different homes for the two halves of Argo CD's source.** The
  root chart lives in `terraform/argocd-root-app/` (read only by
  Tofu); child Applications live in `argocd/apps/` (read by Argo CD
  over the network).

- **D4: Anonymous HTTPS clone of the (public) repo.** No auth for Argo
  CD's git access. Repo is public, so the deploy graph isn't a secret.
  Revisit if the repo goes private or cross-repo write-back (Phase 4)
  lands.

- **D5: Root Application created via a tiny local Helm chart.** Tofu
  installs a 3-file chart whose only template is the Application.
  Reuses the existing `helm` provider — no new providers to add, and
  `kubernetes_manifest`'s cold-start CRD problem is avoided.

## Where to look next

- **Setup from scratch** — `README.md`.
- **What's coming** — `ROADMAP.md`.
- **Why a specific tweak exists** — file headers. Most `tasks/*.yml`
  and `*.tf` files start with a long comment explaining the choices
  made inside them. They're the canonical source for "why X."

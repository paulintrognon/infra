# Infra

Single Debian VPS on OVH → bootstrapped to single-node k3s + Helm + OpenTofu. Hosts my personal TypeScript projects.

Personal, opinionated. Public for reference. MIT — no support.

## Contents

- [What's where](#whats-where)
- [Prerequisites](#prerequisites)
- [Setting up from scratch](#setting-up-from-scratch)
  - [1. Local inventory](#1-local-inventory)
  - [2. Copy local SSH key to the VPS](#2-copy-local-ssh-key-to-the-vps)
  - [3. Bootstrap the VPS](#3-bootstrap-the-vps)
  - [4. Local kubectl access](#4-local-kubectl-access)
  - [5. OpenTofu state backend](#5-opentofu-state-backend)
  - [6. Install cluster system charts](#6-install-cluster-system-charts)
  - [7. Apply the cert-manager ClusterIssuers](#7-apply-the-cert-manager-clusterissuers)
  - [8. DNS for your app](#8-dns-for-your-app)
  - [9. Deploy the apps](#9-deploy-the-apps)
- [Day-2 operations](#day-2-operations)
  - [Update an app's image](#update-an-apps-image)
  - [Upgrade cert-manager](#upgrade-cert-manager)
  - [Upgrade k3s](#upgrade-k3s)

## What's where

- `ansible/` — VPS bootstrap (runs locally to configure remote server).
- `terraform/` — cluster-level system charts via OpenTofu (cert-manager, ...).
- `k8s/system/` — raw cluster manifests applied with `kubectl` (cert-manager ClusterIssuers).
- `k8s/apps/` — per-app manifests, one folder per app.

## Prerequisites

- An OVH VPS running Debian, reachable on SSH as the default `debian` cloud-init user.
- A local SSH key (defaults to `~/.ssh/id_ed25519`).
- Local tools: `ansible`, `kubectl`, `tofu` (≥ 1.11), `direnv`.

Hook `direnv` into your shell once: add `eval "$(direnv hook bash)"` to `~/.bashrc` (or `direnv hook zsh` to `~/.zshrc`).

## Setting up from scratch

### 1. Local inventory

```bash
cp ansible/inventory.example.yml ansible/inventory.yml
```

Edit `ansible/inventory.yml`, replace `<VPS_IP>` and `<USERNAME>`. The file is gitignored.

### 2. Copy local SSH key to the VPS

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub debian@<VPS_IP>
```

Prompts for the `debian` user's password (set during OVH provisioning).

### 3. Bootstrap the VPS

```bash
cd ansible/
ansible-galaxy collection install -r requirements.yml   # one-time
ansible-playbook bootstrap.yml
```

Idempotent — re-run anytime to reconcile.

**Note:** the VPS auto-reboots at 04:00 local time when an unattended security upgrade requires it. (see `ansible/tasks/system_base.yml`)

### 4. Local kubectl access

The k8s API is bound to `127.0.0.1` on the VPS (port 6443 is blocked at the firewall). Reach it via an SSH tunnel.

Copy the kubeconfig down:

```bash
mkdir -p ~/.kube
ssh <USERNAME>@<VPS_IP> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/paulin-config
chmod 600 ~/.kube/paulin-config
```

The filename `paulin-config` is what the repo's `.envrc` expects.

Open the tunnel (leave this terminal open — closing it closes the tunnel):

```bash
ssh -N -L 6443:127.0.0.1:6443 -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 <USERNAME>@<VPS_IP>
```

In a separate terminal, verify:

```bash
cd infra
direnv allow .
kubectl get nodes
```

The VPS should show as `Ready`.

**Warning:** every `kubectl` and `tofu` command below requires the tunnel. Hanging commands usually mean the tunnel died.

### 5. OpenTofu state backend

State lives in Scaleway Object Storage (bucket `paulin-infra-tfstate`, region `fr-par`). Credentials load via `direnv` only inside `terraform/`.

Create the credentials file outside the repo:

```bash
mkdir -p ~/.config/paulin-infra
```

Create `~/.config/paulin-infra/scaleway.env`:

```bash
export AWS_ACCESS_KEY_ID="SCW..."
export AWS_SECRET_ACCESS_KEY="..."
```

The `AWS_*` names are correct — OpenTofu's S3 backend works against any S3-compatible service.

```bash
chmod 600 ~/.config/paulin-infra/scaleway.env

cd terraform/
direnv allow .
tofu init
```

### 6. Install cluster system charts

```bash
cd terraform/
tofu apply
```

Installs cert-manager (TLS automation) into the `cert-manager` namespace. Type `yes` to confirm.

Verify:

```bash
kubectl get pods -n cert-manager
```

Three pods, all `Running`. The webhook takes ~30s.

### 7. Apply the cert-manager ClusterIssuers

```bash
kubectl apply -f k8s/system/cert-manager/
kubectl get clusterissuers
```

Both `letsencrypt-staging` and `letsencrypt-prod` should show `READY=True`.

**Note:** use `letsencrypt-staging` while testing a new Ingress. Real Let's Encrypt rate-limits at 5 duplicate certs per registered domain per week.

### 8. DNS for your app

Create an A record at your registrar:

```
<your-app-domain>   A   <VPS_IP>
```

For OVH: Manager → Web Cloud → Domain → DNS Zone. Propagation can take a few minutes.

### 9. Deploy the apps

```bash
kubectl apply -R -f k8s/apps/
kubectl rollout status deploy --all
```

Then `curl -i https://<each-app-domain>/api/health` — expect `HTTP/2 200`. First request to a newly-deployed app can take ~1 minute while cert-manager issues the cert.

## Day-2 operations

### Update an app's image

Edit `image:` in `k8s/apps/<app>/deployment.yaml`, then:

```bash
kubectl apply -f k8s/apps/<app>/
kubectl rollout status deploy/<app>
```

Zero-downtime rolling update.

### Upgrade cert-manager

Edit `version` in `terraform/cert-manager.tf`, then:

```bash
cd terraform/
tofu plan      # review what changes
tofu apply
```

### Upgrade k3s

Edit `k3s_version` in `ansible/bootstrap.yml`, then re-run the bootstrap:

```bash
cd ansible/
ansible-playbook bootstrap.yml
```

In-place upgrade via the k3s installer.

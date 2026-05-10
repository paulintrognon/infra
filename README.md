# Infra

Single Debian VPS on OVH → bootstrapped to single-node k3s + Helm + OpenTofu. Hosts my personal TypeScript projects (Next.js, NestJS, static).

Personal, opinionated. Public for reference. MIT — no support.

## Prerequisites

Ansible, kubectl, Helm.

## Setting up

### Step 1: Local inventory file

```bash
cp ansible/inventory.example.yml ansible/inventory.yml
```

Then open ansible/inventory.yml in your editor and replace:
- `<YOUR_VPS_IP>` → VPS IP provided by OVH
- `<YOUR_USERNAME>` → Username for the non-root admin account the bootstrap playbook creates.
- `<YOUR_EMAIL>` → an email you control (Let's Encrypt sends renewal-failure warnings here)
  
_**Note:** inventory.yml is gitignored, so real values never get committed._

### Step 2: Copy your SSH key to the VPS

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub debian@<YOUR_VPS_IP>
```

_**Note:** prompts for the `debian` user's password once (set during OVH provisioning)._

### Step 3: Run the bootstrap playbook

```bash
cd ansible/
ansible-galaxy collection install -r requirements.yml   # one-time, installs the Ansible collections we depend on
ansible-playbook bootstrap.yml
```

_**Note:** the playbook is idempotent — re-run anytime to reconcile the VPS to the desired state (e.g. after bumping `k3s_version` in `bootstrap.yml` to upgrade k3s)._

# Infra

Single Debian VPS on OVH → bootstrapped to single-node k3s + Helm + OpenTofu. Hosts my personal TypeScript projects (Next.js, NestJS, static).

Personal, opinionated. Public for reference. MIT — no support.

## Prerequisites

- **Ansible, kubectl, Helm** — VPS provisioning + cluster ops
- **OpenTofu ≥ 1.11** — infrastructure-as-code for DNS records, system Helm releases, etc. Use OpenTofu, not HashiCorp Terraform
- **direnv** — auto-loads the Scaleway Object Storage credentials that back the tofu state file (loaded only when you `cd terraform/`, never globally). After installing, hook it into your shell: `eval "$(direnv hook bash)"` in `~/.bashrc` (or `direnv hook zsh` in `~/.zshrc`). The actual credentials file is set up in Step 4 below.

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

### Step 4: Set up the OpenTofu state backend

The tofu state file lives in **Scaleway Object Storage** (bucket `paulin-infra-tfstate`, region `fr-par`). Your shell needs Scaleway API credentials to talk to it — `direnv` loads them only when you `cd terraform/`, never globally.

Create the credentials directory outside the repo (so the file can never be committed):

```bash
mkdir -p ~/.config/paulin-infra
```

Open `~/.config/paulin-infra/scaleway.env` in your editor and add:

```bash
export AWS_ACCESS_KEY_ID="SCW..."        # from your password manager
export AWS_SECRET_ACCESS_KEY="..."       # from your password manager
```

Lock down its permissions, trust the project's `.envrc`, and initialize tofu:

```bash
chmod 600 ~/.config/paulin-infra/scaleway.env

cd terraform/
direnv allow .
tofu init
```

_**Note:** the `AWS_*` env var names are correct — OpenTofu's S3 backend uses the AWS SDK regardless of which S3-compatible provider (Scaleway, here) hosts the bucket. To rotate keys, regenerate them in Scaleway console → IAM → Applications → `paulin-infra-tofu` → API Keys, then update the env file (direnv reloads on next prompt)._

# Infra

Single Debian VPS on OVH → bootstrapped to single-node k3s + Helm + OpenTofu. Hosts my personal TypeScript projects (Next.js, NestJS, static).

Personal, opinionated. Public for reference. MIT — no support.

## Prerequisites

- **Ansible, kubectl, Helm** — VPS provisioning + cluster ops
- **OpenTofu ≥ 1.11** — infrastructure-as-code for DNS records, system Helm releases, etc. Use OpenTofu, not HashiCorp Terraform
- **direnv** — auto-loads the Scaleway Object Storage credentials that back the tofu state file (loaded only when you `cd terraform/`, never globally). After installing, hook it into your shell: `eval "$(direnv hook bash)"` in `~/.bashrc` (or `direnv hook zsh` in `~/.zshrc`). The actual credentials file is set up in Step 5 below.

## Setting up

### Step 1: Local inventory file

```bash
cp ansible/inventory.example.yml ansible/inventory.yml
```

Then open ansible/inventory.yml in your editor and replace:
- `<YOUR_VPS_IP>` → VPS IP provided by OVH
- `<YOUR_USERNAME>` → Username for the non-root admin account the bootstrap playbook creates.
  
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

### Step 4: Set up local kubectl access

Bootstrap (Step 3) put k3s on the VPS, but the API server is intentionally bound to `127.0.0.1` on the VPS and not exposed publicly — ufw blocks port 6443 from the internet. To reach the API from your laptop (for `kubectl`, and later for OpenTofu's helm provider in Step 5), we keep the control plane off the public network and forward our local `:6443` to the VPS's loopback via SSH. A tunnel needs to be open before any `kubectl`/`tofu` work, but the K8s API never gets a public listener — good security posture for a long-lived single-VPS setup, and no TLS SAN gymnastics required.

Pull the k3s-shipped kubeconfig down to your laptop:

```bash
mkdir -p ~/.kube
ssh <YOUR_USERNAME>@<YOUR_VPS_IP> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/paulin-config
chmod 600 ~/.kube/paulin-config
```

The `server: https://127.0.0.1:6443` line in the file stays as-is — that's the loopback the tunnel forwards to. The filename `paulin-config` is what the repo's `.envrc` expects; if you change it, edit `.envrc` to match.

Open the tunnel (keep this terminal window open — closing it closes the tunnel):

```bash
ssh -N -L 6443:127.0.0.1:6443 -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 <YOUR_USERNAME>@<YOUR_VPS_IP>
```

What the flags do:
- `-L 6443:127.0.0.1:6443` — forward your laptop's `localhost:6443` to the VPS's `127.0.0.1:6443` (where k3s listens).
- `-N` — don't run a remote command, just hold the forward open.
- `-o ExitOnForwardFailure=yes` — exit immediately if `:6443` can't be bound locally (e.g. an existing tunnel already holds it), instead of "succeeding" with a silently broken forward.
- `-o ServerAliveInterval=60` — send a keepalive probe every 60s, so dropped connections (network blips, NAT timeouts) get detected promptly instead of leaving a zombie tunnel.

**The tunnel does not survive reboots or terminal close** — re-open it whenever you need to reach the cluster.

Then in a separate terminal, trust the repo-root `.envrc` (which exports `KUBECONFIG` and `KUBE_CONFIG_PATH` pointing at the kubeconfig) and verify cluster reachability:

```bash
cd infra
direnv allow .
kubectl get nodes
```

Expected: the VPS shows up as `Ready`. If kubectl hangs, the tunnel isn't open (or its SSH session died) — re-run the `ssh -N -L` command above.

_**Note:** `direnv` deactivates `KUBECONFIG`/`KUBE_CONFIG_PATH` when you `cd` out of the repo, so `kubectl` never accidentally targets this cluster from an unrelated shell. If you SSH to this VPS frequently, you can have the tunnel auto-open on every interactive SSH session by adding `LocalForward 6443 127.0.0.1:6443` to the relevant `Host` entry in `~/.ssh/config`._

### Step 5: Set up the OpenTofu state backend

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

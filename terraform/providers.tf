terraform {
  required_version = ">= 1.11.0"

  # External plugins tofu uses to manage resources. Pinned here, locked by exact
  # version + checksum in .terraform.lock.hcl so `tofu init` is reproducible.
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # State lives in Scaleway Object Storage (S3-compatible).
  # OpenTofu's "s3" backend works against any S3-compatible service
  # when paired with the right "this isn't actually AWS" flags below.
  backend "s3" {
    bucket = "paulin-infra-tfstate"
    key    = "terraform.tfstate"
    region = "fr-par"

    # Scaleway's S3 endpoint.
    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }

    # We're not actually talking to AWS, so disable AWS-only validation
    # paths the backend would otherwise try at init time:
    #   - skip_credentials_validation: don't call AWS STS to verify creds
    #   - skip_region_validation:      "fr-par" isn't an AWS region
    #   - skip_requesting_account_id:  no AWS account to look up
    #   - skip_metadata_api_check:     don't probe EC2 instance metadata
    #   - skip_s3_checksum:            some S3-compatibles reject newer
    #                                  checksum algorithms; safest default
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true

    # Native state locking via S3 conditional writes (OpenTofu 1.11+).
    # Replaces the old DynamoDB-table lock pattern you'll see in
    # legacy Terraform tutorials — no separate lock table needed.
    use_lockfile = true
  }
}

provider "helm" {
  # Cluster connection auto-discovered from the KUBECONFIG env var,
  # which is loaded by direnv from the repo-root .envrc (see ../.envrc).
  # No config_path / config_context pinned here on purpose — keeps
  # providers.tf portable (no laptop-specific paths in committed HCL).
  kubernetes = {}
}

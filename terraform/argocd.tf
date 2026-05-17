# Argo CD — GitOps reconciliation controller for the cluster.
#
# Watches this repo (paulin/infra) and ensures the cluster matches what's
# declared under argocd/. Per ROADMAP decision D1, Tofu owns Argo CD itself
# (the bootstrap) while Argo CD owns everything else — i.e. the workloads
# under argocd/apps/. This file is the Tofu side of that split.
#
# Argo CD reads this public repo over anonymous HTTPS, so
# there is no repo-auth Secret to wire up here. If/when a repo goes private,
# we'd add a kubernetes_secret resource for the Repository credential.
#
# No `values` or `set` overrides on purpose. The chart's defaults run
# Argo CD as ClusterIP-only — no Ingress, no LoadBalancer — which is what
# Phase 1 wants: port-forward-only access until Phase 5 picks a domain and
# wires Ingress + cert-manager + auth properly.
#
# To upgrade: bump `version` below, run `tofu plan` to see what changes,
# then `tofu apply`.

resource "helm_release" "argo_cd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.14"
}

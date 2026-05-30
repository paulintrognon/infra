# Argo CD — GitOps reconciliation controller for the cluster.
#
# Watches this repo (paulin/infra) and ensures the cluster matches what's
# declared under argocd/. Per ROADMAP decision D1, Tofu owns Argo CD itself
# (the bootstrap) while Argo CD owns everything else — i.e. the workloads
# under argocd/apps/. This file is the Tofu side of that split.
#
# Argo CD reads this public repo over anonymous HTTPS, so there is no
# repo-auth Secret to wire up here. If/when a repo goes private, we'd add a
# kubernetes_secret resource for the Repository credential.
#
# --- How the web UI is exposed ---
#
# The values below put the Argo CD web UI on a normal web address, secured
# with HTTPS. Three pieces make that happen:
#
#   1. The address. global.domain sets the UI's web address in ONE place.
#      The chart reuses that single value everywhere it's needed: both for
#      routing incoming traffic to the UI, and for Argo CD's own sense of
#      "what is my address" (it bakes that into the login links it builds).
#      So there's just one line to change if the address ever moves.
#
#   2. The certificate (TLS). cert-manager.io/cluster-issuer annotation tells
#      cert-manager to automatically fetch a free Let's Encrypt certificate
#      and drop it into a Secret (argocd-server-tls) that the Ingress uses.
#      This is the same mechanism every app in this cluster already relies on.
#
#   3. Who does the encrypting. Traefik (the cluster's front door) handles the
#      HTTPS encryption with visitors, then forwards the request to the Argo
#      CD pod as plain, unencrypted HTTP. server.insecure: true is simply us
#      telling Argo CD: "don't bother doing HTTPS yourself — Traefik already
#      handled it." That final unencrypted hop never leaves the server
#      machine, so there's nothing on the wire to eavesdrop; the part that
#      actually travels the public internet is fully encrypted. (Encrypting
#      even that internal hop only matters when you don't trust other things
#      running on the same cluster — which, on a single-owner box, you do.)
#
# To upgrade: bump `version` below, run `tofu plan` to see what changes,
# then `tofu apply`.

resource "helm_release" "argo_cd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.14"

  values = [
    <<-EOT
    global:
      domain: argocd.paulintrognon.fr
    configs:
      params:
        server.insecure: true
    server:
      ingress:
        enabled: true
        ingressClassName: traefik
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
        tls: true
    EOT
  ]
}
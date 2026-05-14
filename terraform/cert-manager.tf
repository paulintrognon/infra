# cert-manager — TLS certificate automation for the cluster.
#
# Issues Let's Encrypt certificates for Ingress resources via ACME.
# The ClusterIssuer resources (staging + prod) that wire this to
# Let's Encrypt live as raw manifests under k8s/system/cert-manager/.
# This file manages only the cert-manager controller itself, via its
# Helm chart from Jetstack.
#
# crds.enabled = true lets the chart install and manage cert-manager's
# CRDs (Certificate, ClusterIssuer, Issuer, ...). The alternative is
# installing CRDs separately and keeping them out of the chart's
# lifecycle, which is the recommended path on multi-operator clusters
# (CRD removal becomes intentional). For this single-operator setup,
# letting the chart own its CRDs is simpler.
#
# To upgrade: bump `version` below, run `tofu plan` to see what changes,
# then `tofu apply`.

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io" 
  chart      = "cert-manager"
  version    = "v1.20.2"

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    },
  ]
}

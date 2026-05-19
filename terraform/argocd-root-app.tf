# Root Argo CD Application — the bootstrap that "turns Argo CD on."
#
# Argo CD itself is installed by argocd.tf, but on its own it just sits
# there watching nothing. This file creates the ROOT `Application` resource
# inside the cluster, which tells Argo CD: "start watching `argocd/apps/`
# in this repo." That kicks off the GitOps cascade described in
# argocd-root-app/templates/application.yaml.
#
# HOW IT'S CREATED
# The Application YAML is wrapped in a tiny local Helm chart at
# ./argocd-root-app/ and installed by Tofu's `helm_release`. Two reasons
# for that wrapping over alternatives like `kubernetes_manifest`:
#   1. No additional Kubernetes-aware Tofu provider — the `helm` provider
#      already handles everything Tofu installs into the cluster.
#   2. Cold-start works without manual steps. `kubernetes_manifest` would
#      try to validate the Application CR against its CRD at `tofu plan`
#      time. On a fresh cluster the CRD doesn't exist yet (it's installed
#      by argocd.tf — which Tofu hasn't applied yet). Helm submits manifests
#      to the API server at APPLY time, not plan time, so the ordering
#      works as long as `depends_on` is set (below).
#
# DAY-2: to change what the root App points at — different branch,
# different folder, etc. — edit argocd-root-app/templates/application.yaml
# and re-run `tofu apply`. You should rarely need to touch THIS file again.

resource "helm_release" "argo_cd_root_app" {
  name      = "argocd-root-app"
  # The Helm release name. Visible to `helm list -n argocd`. Doesn't have
  # to match the chart's `name:` from Chart.yaml but conventionally does.

  namespace = "argocd"
  # Where the Application CR lands. The `argocd` namespace is created by
  # helm_release.argo_cd (see argocd.tf), so it already exists by the time
  # this release is applied. `create_namespace = true` would be redundant
  # and could fight with the other release for ownership of the namespace.

  chart = "${path.module}/argocd-root-app"
  # Path to the chart folder, RELATIVE to this .tf file's directory.
  # `path.module` is a Tofu built-in that expands to "the folder this .tf
  # file lives in" (i.e. `terraform/`). Using it instead of a hardcoded
  # path makes the reference portable — `tofu apply` works the same no
  # matter where it's invoked from.
  #
  # `repository` is intentionally NOT set. That field is only for REMOTE
  # charts (an HTTPS Helm repo or an OCI registry, like the argo-cd chart
  # in argocd.tf). For a folder on disk, set only `chart`.

  depends_on = [helm_release.argo_cd]
  # Explicit ordering: install Argo CD itself FIRST, then this. Without
  # depends_on, Tofu can install resources in parallel when it doesn't see
  # a data dependency between them — and parallel install would race the
  # Application CR against its own CRD.
  #
  # With depends_on, Tofu guarantees `helm_release.argo_cd` reaches a
  # successful state (CRDs installed, controller pods up) before this
  # release starts.
}

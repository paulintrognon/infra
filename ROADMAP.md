# ROADMAP — Argo CD + GitOps deploy automation

This file tracks a multi-session initiative to move from manual `helm upgrade`
to a fully automated GitOps deploy flow:

```
push to plouf-plouf
   → CI builds image, pushes to ghcr.io                  (already done)
   → CI opens a PR in this repo bumping the image tag    (new)
   → merging the PR triggers Argo CD to roll it out      (new)
```

It exists so we can resume mid-flight in a future session without re-deriving
the plan. Update the checkboxes as we go.

Decided on 2026-05-17. Companion conversation: option (b) + (3) from
`AskUserQuestion` on deploy-automation paths.

## End state

- Argo CD installed on the cluster as a Helm release **managed by OpenTofu**
  (same `helm-install-then-tofu-import` pattern we used for cert-manager).
- Every workload (plouf-plouf, paulintrognon.fr, future apps) deployed via an
  Argo CD `Application`. No more manual `helm upgrade`.
- Each app's CI in its own repo opens a PR here on image build; merging the
  PR triggers Argo CD to roll out the new image.
- Tofu owns bootstrap (Argo CD itself + the root Application). Argo CD owns
  workloads. cert-manager migration to Argo CD ownership is deferred (Phase 6).

## Architectural decisions (locked early — each one shapes later phases)

| #  | Decision                                            | Choice                                                                 | Why |
|----|-----------------------------------------------------|------------------------------------------------------------------------|-----|
| D1 | Ownership split: Tofu vs Argo CD                    | Tofu = bootstrap (Argo CD itself + root App). Argo CD = everything else. | Avoids chicken-and-egg on day 1; matches GitOps norm; cert-manager already in Tofu can migrate later if we want consistency. |
| D2 | App-of-apps pattern                                 | Yes, from day 1.                                                       | Two apps already, more coming. Flat-now-switch-later means re-pointing every Application. Cheap to add the indirection upfront. |
| D3 | Directory layout for Argo CD manifests              | `argocd/root.yaml` + `argocd/apps/*.yaml`                              | Sibling to `ansible/` and (future) `terraform/`. Root is what Tofu syncs; children are what root syncs. |
| D4 | Argo CD → this repo auth                            | None — anonymous HTTPS clone of the public repo.                       | Repo is already public, so the "leaks the deploy graph" concern is moot. Zero secrets to manage. Re-evaluate when (a) a repo goes private, or (b) we wire Phase 4 write-back — at that point a GitHub App likely serves both. |

Open decisions are marked 🟡 in the phases below. Fill the table in here as
they're locked.

## Phase 1 — Bootstrap Argo CD

Decisions: D1, D2, D3 above. Plus:

- [x] Argo CD → this repo auth (decided: D4 — anonymous HTTPS, repo is public).
- [x] Pick + pin an Argo CD Helm chart version (chose `9.5.14`, ships Argo CD `v3.4.2`).
- [x] `helm install` Argo CD into the `argocd` namespace.
- [x] Import the Helm release into Tofu state.
- [x] Verify CLI/UI access via port-forward + initial admin password.

## Phase 2 — Onboard plouf-plouf as an Argo CD Application

- [ ] Write `argocd/root.yaml` (the root Application that Tofu will create;
      it points at `argocd/apps/`).
- [ ] Write `argocd/apps/plouf-plouf.yaml` mirroring the current Helm release
      **exactly** — same chart, namespace, release name, values file.
- [ ] **Take over**: stop using manual `helm upgrade`. Use `argocd app diff`
      to confirm zero drift before letting Argo CD adopt the release. This is
      the one step with a real gotcha — see Hazards below.
- [ ] Verify a deliberate change syncs (edit a value, commit, watch Argo CD
      reconcile).

## Phase 3 — Onboard paulintrognon.fr

- [ ] Repeat Phase 2 shape for the second app. Faster the second time.

## Phase 4 — Close the loop: auto-PR from plouf-plouf CI

- [ ] 🟡 Auth mechanism for cross-repo writes from plouf-plouf CI →
      `paulin/infra` (PAT vs GitHub App). App is cleaner long-term and
      avoids tying writes to one human's account.
- [ ] Add a step to plouf-plouf's GHA workflow: after `docker push`,
      open a PR here bumping the image tag in
      `argocd/apps/plouf-plouf.yaml` (or the underlying values file).
- [ ] 🟡 Auto-merge policy (manual review vs auto-merge on green checks).
      Manual review is safer for a learning setup; auto-merge is the eventual
      goal.
- [ ] (Optional) Configure a GitHub webhook → Argo CD so syncs happen
      immediately instead of via 3-minute polling.
- [ ] End-to-end test: commit to plouf-plouf → PR appears here → merge →
      cluster updated.

## Phase 5 — Expose the Argo CD UI

Deferred until after push-to-deploy works. Port-forward suffices until then.

- [ ] 🟡 Domain (e.g. `argocd.<something>.fr`).
- [ ] Ingress + cert-manager certificate for the UI.
- [ ] 🟡 Auth approach (keep built-in admin only, or GitHub OAuth via Dex
      for a real login). At minimum, rotate the initial admin password
      before exposing.

## Phase 6 — Polish & long-term

- [ ] Sync failure notifications (Slack / Discord / email).
- [ ] (Optional) Migrate cert-manager from Tofu ownership to Argo CD ownership
      for consistency. Not urgent — both are working.
- [ ] (Future, explicitly out of scope here) Argo CD Image Updater to
      auto-bump without PRs. The PR step is also our audit trail, so we
      want it for now.

## Hazards we've already identified

- **Phase 2 "take over" step.** Argo CD will fight any drift on first sync.
  The Application must produce **exactly** the same rendered manifests as
  what's already deployed before we point it at the cluster. Plan:
    1. `helm get manifest plouf-plouf` to capture current state.
    2. `argocd app diff` (with auto-sync disabled) to confirm zero diff.
    3. Then enable auto-sync.
- **Image pull secret for ghcr.io.** Already exists in the cluster
  (plouf-plouf pulls today). Argo CD doesn't change pull behavior, but
  verify the secret is still wired up to the app's ServiceAccount /
  namespace after the takeover.
- **Bootstrap admin password.** Argo CD's initial admin password is in a
  Kubernetes Secret. Rotate it (or switch to OAuth) before exposing the UI
  in Phase 5.

## Progress log

_(Append a one-line entry per session as we complete checkboxes, with date.)_

- 2026-05-17 — Roadmap drafted, option (b) + (3) chosen.
- 2026-05-17 — D4 locked: Argo CD reads the (public) infra repo over anonymous HTTPS. Phase 1 auth checkbox closed.
- 2026-05-17 — Phase 1 complete. Argo CD chart `9.5.14` / app `v3.4.2` installed in `argocd` namespace, imported into Tofu state at `terraform/argocd.tf` (one expected first-apply blip on `repository` — helm provider doesn't preserve it on import), UI access verified via port-forward. Initial admin secret left in place; rotation deferred to Phase 5.

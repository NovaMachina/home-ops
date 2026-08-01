# Flux GitOps Improvement Checklist

Derived from a review of `kubernetes/flux/`, all 65 `ks.yaml` files, 74 HelmReleases,
`kubernetes/components/`, and `.github/workflows/flux-local.yaml` (2026-07-31).

Each item below is written to be fed to an agent as a standalone prompt. File lists were
accurate at the time of the review — re-verify with the given commands before editing.

**Global rules for every item:**

- Every change must pass `flux-local test --enable-helm --all-namespaces --path kubernetes/flux/cluster`.
- Changes intended to be behaviourally neutral must produce an empty `flux-local diff`.
- Never touch `*.sops.yaml` contents. `yamlfmt` runs on staged YAML via lefthook — let it.
- Work one item per branch/PR so `flux-local diff` output stays reviewable.

Suggested order: 1 → 6 → 7 → 8 → 9 → 4 → 5 → 3 → 2, with cleanup (10) whenever.

---

## 1. Add Flux failure alerting

- [ ] **Add `Provider` + `Alert` so reconciliation failures are not silent**

There are currently zero `Alert` or `Provider` resources in the repo — confirm with
`grep -rl 'kind: Alert\|kind: Provider' kubernetes/`. A failed HelmRelease upgrade or a
broken Kustomization produces no notification today; it is only noticed when something
visibly breaks. This is the largest gap in the setup.

Add to `kubernetes/apps/flux-system/flux-instance/app/`:

- `provider.yaml` — a `notification.toolkit.fluxcd.io/v1beta3` `Provider`. Alertmanager
  already runs in the `monitoring` namespace (`kubernetes/apps/monitoring/alertmanager/`),
  so `type: alertmanager` pointed at its in-cluster service is the lowest-friction option
  and reuses existing routing. If a push channel is preferred instead, use `type: discord`
  or `type: ntfy` with the webhook URL pulled from 1Password via an `ExternalSecret`
  (`ClusterSecretStore/onepassword`, vault `homelab`) — follow the pattern in any existing
  `externalsecret.yaml`, e.g. `kubernetes/apps/network/cloudflared/app/`.
- `alert.yaml` — a `notification.toolkit.fluxcd.io/v1beta3` `Alert` with
  `eventSeverity: error`, `providerRef` to the above, and `eventSources` matching
  `'*'` in all namespaces for kinds `Kustomization`, `HelmRelease`, `GitRepository`,
  `OCIRepository`, and `HelmRepository`.

Register both in `kubernetes/apps/flux-system/flux-instance/app/kustomization.yaml`.
Note that `notification-controller` is already enabled in
`kubernetes/apps/flux-system/flux-instance/app/helm/values.yaml`, so no controller change
is needed.

Optionally add a second `Alert` with `eventSeverity: info` and a `suspend`-aware
`exclusionList` if a deploy-activity feed is wanted — keep it on a separate provider so
error alerts do not get buried.

**Done when:** `flux get alerts -A` shows the Alert as ready, and deliberately suspending
and breaking a trivial HelmRelease produces a notification.

---

## 2. Move Flux Kustomizations into `flux-system` (stop replicating the age key)

- [ ] **Refactor so `sops-age` exists once instead of in every namespace**

`kubernetes/components/common/kustomization.yaml` includes `sops-age.sops.yaml`, and that
component is applied by all 17 namespace kustomizations (`kubernetes/apps/*/kustomization.yaml`).
The age private key is therefore materialized as a Secret in every app namespace, because
each app's Flux `Kustomization` lives in the app namespace (e.g.
`kubernetes/apps/self-hosted/immich/ks.yaml` has `namespace: &namespace self-hosted`) and
`spec.decryption.secretRef` resolves in the Kustomization's own namespace.

Consequence: any workload or ServiceAccount able to read Secrets in `downloads`, `media`,
etc. can decrypt every SOPS secret in this repository.

The current upstream convention places all Flux `Kustomization` objects in `flux-system`
and uses `targetNamespace` to place the workloads. Every `ks.yaml` here already sets
`targetNamespace`, so the mechanical change is:

1. In each `kubernetes/apps/<ns>/kustomization.yaml`, remove the top-level `namespace: <ns>`
   field (this is what currently rewrites the ks metadata namespace).
2. In each `kubernetes/apps/<ns>/<app>/ks.yaml`, set `metadata.namespace: flux-system`
   while keeping `spec.targetNamespace: <ns>` unchanged. Many files use a
   `&namespace` YAML anchor for both — these must be split into two distinct values.
3. Update every cross-app `dependsOn[].namespace` to `flux-system`, since dependency refs
   point at Kustomizations, not workloads. Find them with
   `grep -rn -A2 'dependsOn' kubernetes/apps --include=ks.yaml`.
4. Remove `./sops-age.sops.yaml` from `kubernetes/components/common/kustomization.yaml`
   and instead apply the Secret only to `flux-system`.
5. Leave `cluster-secrets.sops.yaml` in `components/common` — `postBuild.substituteFrom`
   resolves in the Kustomization's namespace too, so once all Kustomizations are in
   `flux-system`, that Secret also only needs to exist there. Verify this before deleting
   the per-namespace copies; do it as a follow-up commit if it complicates the diff.

This is the most invasive item in the list. Do it last, on its own branch, and rely on
`flux-local diff kustomization` to confirm the rendered workload output is unchanged —
only the Kustomization objects' namespaces should move. Expect prune behaviour to require
care: renaming/moving a Kustomization causes Flux to prune the old one's resources, so
plan to `flux suspend`/`resume` or apply during a maintenance window.

**Done when:** `kubectl get secret sops-age -A` returns exactly one result, in `flux-system`,
and all Kustomizations reconcile ready.

---

## 3. Enable cosign verification on OCIRepositories

- [ ] **Add `verify.provider: cosign` to signed upstream charts**

Only 9 of 61 files containing an `OCIRepository` set `verify`. List the unverified ones with:

```sh
for f in $(grep -rl 'kind: OCIRepository' kubernetes/apps); do grep -q cosign $f || echo $f; done
```

The already-verified example to copy is
`kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml`.

Most upstream charts here are cosign-signed with keyless GitHub OIDC. Add:

```yaml
verify:
  provider: cosign
  matchOIDCIdentity:
    - issuer: "^https://token\\.actions\\.githubusercontent\\.com$"
      subject: "^https://github\\.com/<org>/<repo>.*$"
```

with `<org>/<repo>` matching the chart's publishing repository. **Verify signature presence
per chart before adding** — an unsigned chart with `verify` set will hard-fail
reconciliation. Check with `cosign verify <oci-url>:<tag> --certificate-identity-regexp ...`
or `cosign triangulate`. Charts known to be signed include the grafana, cilium,
external-secrets, cert-manager, rook, and victoria-metrics families. Skip any chart where
verification cannot be demonstrated locally first, and note the skip in a comment.

Do this in small batches (a namespace at a time) so a bad identity regex breaks one app,
not the cluster.

**Done when:** each touched OCIRepository shows `Ready` with a verified-signature message
in `flux get sources oci -A`.

---

## 4. Enable Helm drift detection

- [ ] **Set `driftDetection` on HelmReleases that currently lack it**

Only 6 of 74 HelmReleases set it:

```sh
grep -rl driftDetection kubernetes/apps --include='helmrelease*.yaml'
```

(`envoy-gateway`, `actions-runner-controller` ×2, `keycloak`, `authentik`,
`generic-device-plugin`.)

Without drift detection, manual or controller-driven mutations to chart-managed resources
persist silently until the next chart version bump, which defeats the point of GitOps.

Add to the remaining HelmReleases:

```yaml
driftDetection:
  mode: enabled
```

Roll out namespace by namespace. For charts whose resources are legitimately mutated by
other controllers, use `mode: warn` first, watch the events for a few days, then either
promote to `enabled` with `driftDetection.ignore` paths for the noisy fields, or leave at
`warn` with a comment explaining why. Expect noise from `rook-ceph`, `cilium`,
`cert-manager` (webhook CA bundles), and anything targeted by `reloader` annotations.

**Done when:** every HelmRelease has an explicit `driftDetection` block, and
`kubectl get events -A | grep -i drift` is quiet in steady state.

---

## 5. Standardize HelmRelease remediation and history

- [ ] **Add `install`/`upgrade` remediation and `maxHistory` to HelmReleases missing them**

32 of 74 HelmReleases have no remediation config at all:

```sh
for f in $(find kubernetes/apps -name 'helmrelease*.yaml'); do grep -q remediation $f || echo $f; done
```

The list includes infrastructure that most needs to self-heal: `rook-ceph/operator`,
`rook-ceph/cluster`, `external-secrets`, `openebs`, `keda`, `prometheus-operator/crds`,
`cloudnative-pg` and most of `downloads/`.

Only 6 set `maxHistory`, so Helm release Secrets accumulate in etcd indefinitely.

Apply this baseline to each HelmRelease lacking it:

```yaml
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
  maxHistory: 2
```

Two exceptions to handle deliberately:

- CRD-only releases (e.g. `kubernetes/apps/monitoring/prometheus-operator/crds/`,
  `kubernetes/apps/monitoring/victoria/crds/`) should keep `crds: CreateReplace` and should
  **not** use `strategy: rollback` — rolling back CRDs can drop stored versions. Use
  `retries: 3` with the default `strategy: uninstall` omitted, or leave remediation off with
  an explanatory comment.
- Bootstrap-critical releases (`cilium`, `external-secrets`) may warrant
  `install.remediation.retries: -1` (infinite), matching the pattern already used in
  `kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml`.

**Done when:** every HelmRelease has an explicit remediation policy or an inline comment
explaining its absence.

---

## 6. Normalize `ks.yaml` fields across all apps

- [ ] **Fix missing `prune`, `wait`, `retryInterval`, `timeout`, `commonMetadata`**

These are consistency gaps, not outright bugs, but they make failures behave unpredictably.
Re-derive each list before editing:

```sh
cd kubernetes
for f in $(find apps -name ks.yaml); do grep -q 'prune: true'    $f || echo "prune: $f"; done
for f in $(find apps -name ks.yaml); do grep -q 'wait:'          $f || echo "wait: $f"; done
for f in $(find apps -name ks.yaml); do grep -q 'retryInterval:' $f || echo "retry: $f"; done
for f in $(find apps -name ks.yaml); do grep -q 'timeout:'       $f || echo "timeout: $f"; done
for f in $(find apps -name ks.yaml); do grep -q 'commonMetadata' $f || echo "meta: $f"; done
```

Findings at review time:

- **`prune` missing (1):** `apps/rook-ceph/rook-ceph/ks.yaml` — resources deleted from git
  are currently orphaned in-cluster. Add `prune: true`, but review what would be pruned on
  the next reconcile *before* merging, since this is a storage layer.
- **`wait` missing (8):** `network/envoy-gateway`, `volsync-system/volsync`,
  `monitoring/victoria`, `kube-system/snapshot-controller`,
  `actions-runner-system/actions-runner-controller`, `security/authentik`,
  `security/keycloak`, `database/rabbitmq`. Several of these are `dependsOn` targets for
  other apps, so those dependencies do not actually gate on readiness today. Set
  `wait: true` unless the app is known to never reach a healthy status (in which case add
  `healthChecks`, see item 9, and comment the reason).
- **`retryInterval` missing (35):** all of `downloads/`, all of `monitoring/`, plus
  `network/external-dns`, `network/envoy-gateway`, `network/multus`, `system/*`,
  `kube-system/descheduler`, `rook-ceph`, `external-secrets/*`, `database/mongodb`,
  `openebs`, `self-hosted/paperless`. Without it, a transient failure is retried at the
  full `interval` (30m–1h) instead of quickly. Set `retryInterval: 1m` (or `2m`, matching
  `kubernetes/flux/cluster/ks.yaml`) uniformly.
- **`timeout` missing (1):** `apps/monitoring/grafana/ks.yaml` — add `timeout: 5m`.
- **`commonMetadata` missing (2):** `apps/database/mongodb/ks.yaml`,
  `apps/database/rabbitmq/ks.yaml` — add the
  `commonMetadata.labels.app.kubernetes.io/name: *app` block used by every other ks.

Also pick a rule for `interval` and apply it: currently 55 files use `30m` and 30 use `1h`
with no discernible pattern. Since a GitHub `Receiver` webhook already triggers on push
(`kubernetes/apps/flux-system/flux-instance/app/receiver.yaml`), the interval is only a
safety net — `1h` everywhere is defensible and reduces API churn.

**Done when:** all five greps above return empty, and `flux-local diff kustomization` shows
no change to rendered workloads.

---

## 7. Hoist `postBuild.substituteFrom` into the `cluster-apps` patch

- [ ] **Remove ~45 repetitions of the `cluster-secrets` substitution block**

`kubernetes/flux/cluster/ks.yaml` already hoists SOPS decryption into every child
Kustomization via a `patches[].target` matching
`group: kustomize.toolkit.fluxcd.io, kind: Kustomization`. The same mechanism can supply
`postBuild.substituteFrom`, which is currently repeated in 45 of 65 `ks.yaml` files:

```sh
grep -rl 'name: cluster-secrets' kubernetes/apps --include=ks.yaml | wc -l
```

Extend the existing patch in `kubernetes/flux/cluster/ks.yaml`:

```yaml
        spec:
          decryption:
            provider: sops
            secretRef:
              name: sops-age
          postBuild:
            substituteFrom:
              - name: cluster-secrets
                kind: Secret
```

Then delete the per-app `postBuild.substituteFrom` blocks. **Keep** the per-app
`postBuild.substitute` blocks (27 files use them for `APP`, `VOLSYNC_CAPACITY`, etc.) —
Kustomize strategic merge combines `substitute` from the app with `substituteFrom` from the
patch. Verify this merge behaviour holds on one app first before doing the bulk edit.

Note: this interacts with item 2. If item 2 is done first, `cluster-secrets` only needs to
exist in `flux-system`. Either order works; just re-check the other item's assumptions.

**Done when:** no `ks.yaml` under `kubernetes/apps/` contains `substituteFrom`, and
`flux-local diff` is empty (substituted values must be byte-identical).

---

## 8. Consolidate Helm chart sources

- [ ] **Move stray HelmRepositories out of app directories, prefer OCI**

`kubernetes/flux/meta/repos/` holds 3 HelmRepositories, but four apps ship their own
privately scoped one:

- `kubernetes/apps/database/mongodb/app/helmrepository.yaml`
- `kubernetes/apps/kube-system/descheduler/app/helmrepository.yaml`
- `kubernetes/apps/openebs/openebs/app/helmrepository.yaml`
- `kubernetes/apps/system/harbor/app/helmrepository.yaml`

Preferred fix: migrate all four to `OCIRepository` + `chartRef`, since all four charts are
published to OCI registries and 33 HelmReleases in this repo already use that pattern.
Copy the shape from `kubernetes/apps/monitoring/grafana/app/ocirepository.yaml`. This
removes the HelmRepository entirely and makes chart sourcing uniform.

Fallback if a chart has no OCI distribution: move the HelmRepository into
`kubernetes/flux/meta/repos/`, register it in that directory's `kustomization.yaml`, and
update the HelmRelease `sourceRef` to `namespace: flux-system`.

Confirm Renovate still tracks the version afterwards — `.renovaterc.json5` has a `flux`
manager plus helm datasource rules; OCI chart tags are picked up by the `flux` manager, but
check that the migrated entries appear in the next Renovate dry run rather than silently
going stale.

While here: OCIRepository `interval` values are scattered across 5m/10m/15m/30m/1h. Pick
one (`1h` is fine given the push webhook) and apply it uniformly.

**Done when:** `grep -rl 'kind: HelmRepository' kubernetes/apps` returns nothing, and all
remaining HelmRepositories live under `kubernetes/flux/meta/repos/`.

---

## 9. Add health checks for CRD-backed apps

- [ ] **Use `healthCheckExprs` where `wait: true` is not sufficient**

Only 7 `ks.yaml` files declare `healthChecks` or `healthCheckExprs`:

```sh
grep -rl 'healthChecks\|healthCheckExprs' kubernetes/apps
```

(`flux-operator`, `envoy-gateway`, `volsync`, `actions-runner-controller`, `rook-ceph`,
`cert-manager`, `snapshot-controller`.)

`wait: true` only waits for resources Flux understands natively. For apps whose real
readiness lives in a custom resource, reconciliation reports success while the actual
workload is still converging — which in turn lets dependent Kustomizations start too early.

Add `healthCheckExprs` (CEL, `kustomize.toolkit.fluxcd.io/v1`) for at least:

- `kubernetes/apps/rook-ceph/rook-ceph/ks.yaml` — `CephCluster` phase/health
- `kubernetes/apps/monitoring/victoria/ks.yaml` — `VMSingle` / `VMAgent` status
- `kubernetes/apps/monitoring/open-telemetry/ks.yaml` — `OpenTelemetryCollector` status
- `kubernetes/apps/database/cloudnative-pg/ks.yaml` — `Cluster` (postgresql.cnpg.io)
  `status.conditions` Ready
- `kubernetes/apps/database/rabbitmq/ks.yaml` — `RabbitmqCluster` status

Each entry needs `apiVersion`, `kind`, and `inReady`/`failed` CEL expressions; confirm the
actual status field names against the live CRs with
`kubectl get <kind> -o yaml` before writing the expression. A wrong expression will hang
the Kustomization until `timeout`, so verify one app end-to-end before adding the rest.

**Done when:** each listed Kustomization reports ready only after its custom resources are
genuinely healthy.

---

## 10. Repository cleanup

- [ ] **Delete dead files and directories**

- `kubernetes/flux/meta/repos/ingress-nginx.yaml` — nothing references it
  (`grep -rn ingress-nginx kubernetes/` hits only this file and its kustomization entry).
  `CLAUDE.md` states ingress is Envoy Gateway and nginx manifests are stale. Delete the file
  and its entry in `kubernetes/flux/meta/repos/kustomization.yaml`.
- `kubernetes/components/gatus/` — empty directory, referenced by nothing. Remove it, or
  implement the component if per-app Gatus monitors are still wanted.
- `kubernetes/apps/monitoring/grafana/app/helmrelease.yaml.bak` — committed backup file.
  Delete.
- `kubernetes/apps/self-hosted/scratch` — committed scratch file. The root-level `scratch`
  is gitignored but this one is inside the tree Flux reconciles; confirm with
  `git ls-files kubernetes/apps/self-hosted/scratch` and delete if tracked.
- `kubernetes/components/netpol-default-deny/` is applied by exactly one namespace
  (`kubernetes/apps/security/kustomization.yaml`). Either extend it to more namespaces or
  document why it is scoped to `security` only.

**Done when:** `flux-local test` passes and `git status` is clean after removal.

---

## 11. Reconsider `cluster.networkPolicy: false`

- [ ] **Re-enable the FluxInstance network policy, or document why not**

`kubernetes/apps/flux-system/flux-instance/app/helm/values.yaml` sets
`instance.cluster.networkPolicy: false`, disabling the default policy that denies ingress to
the `flux-system` namespace from other namespaces. The default is `true`.

Investigate whether this was a deliberate workaround (likely for Cilium, or for the
`monitoring` namespace scraping the controllers' metrics — note
`kubernetes/apps/flux-system/flux-operator/app/helm/values.yaml` sets `serviceMonitor.create: true`).

If it was a workaround, prefer re-enabling it and adding a targeted `CiliumNetworkPolicy`
allowing the specific traffic — the repo already has policy patterns in
`kubernetes/apps/security/ciliumnetworkpolicy.yaml` and
`kubernetes/components/netpol-default-deny/`. If it must stay off, add a comment in
`values.yaml` recording the reason so it is not re-litigated.

Related history worth reading first: commits `c12c92d5` ("apply cnp v2"), `c61c8c9a` /
`aa751e0e` (a network policy that was added then reverted).

**Done when:** either the setting is `true` with the cluster healthy, or an inline comment
explains the exception.

---

## 12. Pin OCI charts by digest

- [ ] **Add `ref.digest` alongside `ref.tag` on OCIRepositories**

No OCIRepository currently pins a digest:

```sh
grep -rc 'digest:' kubernetes/apps --include='ocirepository.yaml' | grep -v ':0'
```

Tags are mutable, so a re-pushed upstream tag silently changes what the cluster runs. Add:

```yaml
  ref:
    tag: 1.2.3
    digest: sha256:...
```

When both are set, Flux verifies the tag resolves to that digest. Renovate's `flux` manager
maintains the tag/digest pair, but confirm it does so for these entries — check
`.renovaterc.json5` and run a Renovate dry run before relying on it, otherwise this becomes
manual toil across 61 files.

Do this after item 3 (cosign), since signature verification is the stronger guarantee and
digest pinning is complementary rather than a substitute.

**Done when:** every OCIRepository has a digest, and Renovate PRs update both fields together.

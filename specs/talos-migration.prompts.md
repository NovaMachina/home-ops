# talos-migration implementation prompts

Companion to [`talos-migration.spec.md`](./talos-migration.spec.md). Hand these to an
implementing agent (e.g. Sonnet) **one phase at a time** — each starts cold, so each prompt
is self-contained. Do not advance until the prior phase's verification passes.

Phases 1–4 and 6 are repo-only changes (safe). **Only Phase 5 mutates live nodes** — run that
one yourself with `! task ...` rather than letting an agent batch through it. Phases 1 and 3
are gates: the cluster is never touched until both pass.

---

## Prompt 0 — Orientation (optional, run once at the start)

```
You're working in a home-ops GitOps repo migrating Talos config from talhelper to raw talosctl.
Read these before doing anything:
- specs/talos-migration.spec.md  (the authoritative plan — §V invariants govern correctness)
- talos/talconfig.yaml, talos/talenv.yaml
- talos/patches/global/*.yaml and talos/patches/controller/*.yaml
- .taskfiles/talos/Taskfile.yaml and .taskfiles/bootstrap/Taskfile.yaml
- One generated reference: talos/clusterconfig/kubernetes-talos-controller-01.yaml

Key facts:
- 9 nodes: controllers 10.0.40.100-102 (have VIP 10.0.40.10), workers .103-105, storage .106-108.
- worker-02 (.104) and worker-03 (.105) use DISTINCT factory installer URLs from the rest. Do not collapse them into a shared default.
- Env vars are set by mise: SOPS_AGE_KEY_FILE=./age.key, TALOSCONFIG=./talos/clusterconfig/talosconfig.
- SOPS rules (.sops.yaml): files matching *.sops.yaml under kubernetes/** and bootstrap/** encrypt only data/stringData; talos/** encrypts the full file. New secret file must end in .sops.yaml.
- Do NOT apply anything to live nodes in these tasks. Config-generation and validation only until explicitly told otherwise.

Confirm you've read these and summarize the current talhelper-driven flow in 5 bullets. Do not change anything yet.
```

---

## Prompt 1 — Phase 1: Secrets bundle

```
Goal: produce talos/secrets.sops.yaml — a talosctl-native secrets bundle carrying the EXISTING cluster CA/certs (NOT freshly generated; regenerating would rotate the CA and destroy the cluster). Cites spec §V V6,V7,V8.

Steps:
1. Extract the bundle from a live controlplane config (preserves existing certs):
   talosctl gen secrets --from-controlplane-config talos/clusterconfig/kubernetes-talos-controller-01.yaml --output-file talos/secrets.sops.yaml
2. Verify it carries the same identity as the current talhelper secret BEFORE encrypting. Decrypt talos/talsecret.sops.yaml with sops and compare these fields between the two files:
   - cluster id, cluster secret
   - etcd CA cert, kubernetes CA cert, k8s service account key
   Report a field-by-field match table. If any core CA/secret differs, STOP and report — do not continue.
3. Only after the match is confirmed, encrypt in place:
   sops --encrypt --in-place talos/secrets.sops.yaml
4. Confirm it decrypts cleanly: sops --decrypt talos/secrets.sops.yaml | head.

Do NOT delete talos/talsecret.sops.yaml — it stays until every node is re-applied (V8).
Output: the match table + confirmation the encrypted file decrypts.
```

---

## Prompt 2 — Phase 2: Per-node patch files

```
Goal: create per-node patch files under talos/nodes/ holding everything talhelper synthesized per node. Cites spec §V V3,V4,V5.

Source of truth: talos/talconfig.yaml (nodes list) and the generated talos/clusterconfig/kubernetes-talos-*.yaml for exact field shapes.

Create talos/nodes/<hostname>.yaml for all 9 nodes (talos-controller-01..03, talos-worker-01..03, talos-storage-01..03). Each file is a strategic-merge machine config patch containing ONLY per-node values:
  machine:
    install:
      disk: /dev/sda
      image: <talosImageURL>:<talosVersion>   # talosVersion from talenv.yaml (currently v1.10.6)
    network:
      hostname: <hostname>
      interfaces:
        - deviceSelector:
            hardwareAddr: <MAC>
          dhcp: false
          addresses: ["<IP>/24"]
          routes:
            - network: 0.0.0.0/0
              gateway: 10.0.40.1
          mtu: 1500
          # controllers ONLY also include:
          vip:
            ip: 10.0.40.10

Rules:
- Controllers (.100-.102) include the vip block; workers and storage do NOT.
- worker-02 image URL: factory.talos.dev/installer/11a5f2ae787d5a49a6e8e2377fdb305e905f65d8b369b435500f2eec11d1aace
- worker-03 image URL: factory.talos.dev/installer/bbb84ab9bc2d8703ff7f0c46f04e20fee5e78d8c9af1cec7ce246f5b278dc0e5
- All other nodes: factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
- Pull each node's MAC/IP from talconfig.yaml; double-check against the matching clusterconfig file.

Output: a table of hostname → IP → MAC → image-suffix → has-vip, so I can eyeball-verify all 9.
```

---

## Prompt 3 — Phase 3: Rewrite generate-config + validation gate (CRITICAL)

```
Goal: rewrite `task talos:generate-config` in .taskfiles/talos/Taskfile.yaml to use raw talosctl, then prove the output is byte-equivalent (modulo Talos version) to the current talhelper output. Cites spec §V V1,V2,V11. This is a gate — nothing gets applied to nodes here.

Important: `talosctl gen config` does NOT emit per-node files. The correct pattern is:
  1. talosctl gen config kubernetes https://10.0.40.10:6443 \
       --with-secrets talos/secrets.sops.yaml \
       --additional-sans 10.0.40.10 \
       --install-disk /dev/sda \
       --kubernetes-version <kubernetesVersion from talenv.yaml> \
       --config-patch '@talos/patches/...(CNI=none, pod/service subnets)...' \
       --output-dir <tmp>   --force
     (Choose flags vs patches so the base controlplane.yaml/worker.yaml match talhelper: cni.name=none, podSubnets 10.69.0.0/16, serviceSubnets 10.96.0.0/16, dnsDomain cluster.local, endpoint https://10.0.40.10:6443. You may need a small extra global patch for cluster.network — add it under talos/patches/global/ if so.)
  2. For each of the 9 nodes, produce talos/clusterconfig/kubernetes-<hostname>.yaml by patching the right base (controlplane for controllers, worker for the rest):
       talosctl machineconfig patch <base.yaml> \
         --patch @talos/patches/global/machine-files.yaml \
         --patch @talos/patches/global/machine-kubelet.yaml \
         --patch @talos/patches/global/machine-network.yaml \
         --patch @talos/patches/global/machine-sysctls.yaml \
         --patch @talos/patches/global/machine-time.yaml \
         [controllers only:] --patch @talos/patches/controller/admission-controller-patch.yaml \
                             --patch @talos/patches/controller/cluster.yaml \
                             --patch @talos/patches/controller/machine-features.yaml \
         --patch @talos/nodes/<hostname>.yaml \
         -o talos/clusterconfig/kubernetes-<hostname>.yaml

Validation (do this before declaring success):
  - The committed clusterconfig/ was generated at v1.10.4 but talenv is v1.10.6. To get a clean diff, first regenerate the OLD talhelper baseline at the current version (cd talos && talhelper genconfig) into a temp dir, OR normalize the version string out of both sides.
  - Diff new vs old per node. The ONLY acceptable differences are key ordering and the install image version tag. Any structural/semantic diff (missing patch, wrong subnet, missing/extra vip, wrong cert SANs) must be resolved before proceeding.
  - Report the diff summary per node.

Write the task so generate-config is idempotent and writes into talos/clusterconfig/. Keep the existing .gitignore in clusterconfig/ (generated node files stay gitignored).

Output: the rewritten task + per-node diff summary proving equivalence. Do NOT touch any other Taskfile task yet.
```

---

## Prompt 4 — Phase 4: Rewrite remaining Taskfile/bootstrap/script references

```
Goal: replace all remaining talhelper usage in tasks/scripts with talosctl equivalents. Cites spec §V V12,V13,V14,V15,V16. Still no live applies.

In .taskfiles/talos/Taskfile.yaml:
- apply-node: talosctl apply-config --nodes {{.IP}} --file talos/clusterconfig/kubernetes-<hostname>.yaml --mode {{.MODE}}.
  Map IP→hostname by reading talos/nodes/*.yaml (the file whose interface address matches IP). Keep the existing `down`/`up` Ceph-health guards and the post-apply health wait verbatim.
- upgrade-node: talosctl upgrade --nodes {{.IP}} --image <image>:<version> --timeout=10m.
  Source <image> from talos/nodes/<hostname>.yaml (machine.install.image, strip the :version), <version> from talos/talenv.yaml talosVersion.
- upgrade-k8s: talosctl upgrade-k8s --to <kubernetesVersion from talenv.yaml>.
- reset: talosctl reset --nodes <...> --reboot ... (preserve the existing --system-labels-to-wipe / graceful / wait flag behavior keyed on CLI_FORCE).
- apply-cluster: keep as-is but ensure it calls the new apply-node.
- Remove `which talhelper` from ALL preconditions; keep talosctl/yq/kubectl/jq.

In .taskfiles/bootstrap/Taskfile.yaml (talos bootstrap task), replace the talhelper pipeline:
- gensecret  → talosctl gen secrets (only if talos/secrets.sops.yaml absent)
- genconfig  → `task talos:generate-config`
- gencommand apply --insecure → loop talosctl apply-config --insecure over nodes
- gencommand bootstrap → talosctl bootstrap --nodes 10.0.40.100
- gencommand kubeconfig → talosctl kubeconfig --force <root>
- Update preconditions: drop talhelper, keep talosctl/sops.

In scripts/bootstrap-apps.sh: remove `talhelper` from the check_cli list (line ~129).

Do not remove talhelper from .mise.toml yet (still needed for the Phase 3 baseline diff if re-run). Output: the diffs of every changed file.
```

---

## Prompt 5 — Phase 5: Rolling apply (ops — run interactively, you supervise)

```
Goal: roll the new config onto all 9 nodes, one at a time, cluster stays live. Cites spec §V V17,V18,V19. The config was already proven equivalent in Phase 3, so this should be a no-op-equivalent reconfigure.

Order (least to most critical):
  1. workers: 10.0.40.103, .104, .105
  2. storage: 10.0.40.106, .107, .108
  3. controllers: 10.0.40.100, .101, .102  (one at a time; confirm etcd healthy after each)

For EACH node, sequentially:
  a. Confirm Ceph HEALTH_OK: kubectl wait cephcluster ... (the `down` guard).
  b. task talos:apply-node IP=<ip> MODE=auto
  c. Verify new config is active: talosctl get machineconfig --nodes <ip>  (and `talosctl version`/health).
  d. Wait for Ceph HEALTH_OK again before the next node.
Never apply two controllers simultaneously. If any node fails to come back healthy, STOP and report.

Run one node, report results, and WAIT for my go-ahead before the next. Do not batch.
```

---

## Prompt 6 — Phase 6: Cleanup + docs

```
Goal: remove talhelper now that all 9 nodes run talosctl-generated config. Cites spec §V V8,V9,V10,V16,V20. Only do this after I confirm Phase 5 is fully complete.

1. .mise.toml: remove the "aqua:budimanjojo/talhelper" tool line.
2. Delete talos/talconfig.yaml.
3. Delete talos/talsecret.sops.yaml (superseded by talos/secrets.sops.yaml).
4. talos/talenv.yaml: remove the talhelper `$schema` comment if present; KEEP talosVersion + kubernetesVersion and their `# renovate:` comments intact (Renovate still tracks them).
5. talos/patches/README.md: reword to describe raw-talosctl patching, not talhelper.
6. CLAUDE.md: update the "Talos Config" section and the `task talos:generate-config` comment to describe talos/nodes/<hostname>.yaml + talos/secrets.sops.yaml instead of talconfig.yaml/talsecret.
7. README.md: update the bootstrap/upgrade sections that reference talhelper, talconfig.yaml, talsecret.
8. Update specs/talos-migration.spec.md: mark all §T tasks status `x`.

Verify no stale references remain (ignore .private/ and .git/):
  grep -rn "talhelper\|talconfig" --include="*.yaml" --include="*.toml" --include="*.md" --include="*.sh" . | grep -v -E "\.private/|\.git/"
Output: that grep should return nothing (or only the spec's historical prose). Show me the final result.
```

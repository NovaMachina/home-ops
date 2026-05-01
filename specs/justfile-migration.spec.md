# justfile-migration spec

Extends: SPEC.md T20

## §G — Goal

Replace Taskfile (6 files, ~20 tasks) with Justfile. ∀ existing tasks preserved with equivalent behavior; `go-task` removed from mise.

---

## §C — Constraints

- Root `Taskfile.yaml` + 5 modules under `.taskfiles/` → root `justfile` + 5 `mod.just` files under `.justfiles/`
- Taskfile features in use: `vars:` (including `sh:`), `env:`, `includes:`, `preconditions:`, `requires:`, `for:`, `prompt:`, `internal:`, `dir:`, `set: [pipefail]`, `shopt: [globstar]`
- Just equivalents: `import` (modules), `[private]` (internal), `[confirm]` (prompt), named params with defaults, `export` (env vars), `:=` / `$(cmd)` (vars)
- `CLAUDE.md` documents `task <name>` commands — must update after migration
- T19 (talos-migration) rewrites talos Taskfile tasks; coordinate: migrate talos module after T19 lands, or migrate together
- `lefthook.toml` may reference `task` commands — audit before cutover
- mise tool: `go-task` removed; `just` added

---

## §I — Interfaces

```
cmd: just [recipe]            → replaces task [task]
cmd: just --list              → replaces task --list (default task)
file: justfile                → root, replaces Taskfile.yaml
file: .justfiles/bootstrap.just  → replaces .taskfiles/bootstrap/Taskfile.yaml
file: .justfiles/kubernetes.just → replaces .taskfiles/kubernetes/Taskfile.yaml
file: .justfiles/postgres.just   → replaces .taskfiles/postgres/Taskfile.yaml
file: .justfiles/talos.just      → replaces .taskfiles/talos/Taskfile.yaml
file: .justfiles/volsync.just    → replaces .taskfiles/volsync/Taskfile.yaml
env: KUBECONFIG              ! export in justfile (replaces Taskfile env:)
env: SOPS_AGE_KEY_FILE       ! export in justfile
env: TALOSCONFIG             ! export in justfile
env: MINIJINJA_CONFIG_FILE   ! export in justfile
```

---

## §V — Invariants

### Structure

```
V1: ∀ public task → recipe in justfile | module .just file; name & behavior identical
V2: ∀ internal task (down, up) → [private] attribute in .justfiles/talos.just
V3: root justfile → `import '.justfiles/*.just'` for ∀ 5 modules
V4: `just --list` → shows ∀ public recipes with descriptions (# doc comment above each recipe)
```

### Behavior parity

```
V5:  preconditions (test -f, which) → preserved as `[ -f {{file}} ] || { echo ...; exit 1; }` guards at recipe start
V6:  requires vars (IP, APP, NS, PREVIOUS) → recipe parameters with defaults where applicable
V7:  sh: vars (shell-computed) → `:= \`command\`` at module scope | `$(command)` inline in recipe
V8:  `for: { var: IP_ADDRS }` (apply-cluster) → shell for loop in recipe body
V9:  `prompt:` (reset task) → `[confirm]` attribute on reset recipe
V10: `dir:` (talos tasks) → `cd {{dir}} && ...` at recipe start
V11: `set: [pipefail]` + `shopt: [globstar]` → `set -euo pipefail` shebang recipes where needed
V12: `task reconcile` → `just reconcile`; no namespace prefix needed (root recipe)
V13: namespaced calls (`task talos:apply-node`) → `just talos-apply-node` | `just apply-node` (just uses `-` not `:` as separator)
```

### Tooling

```
V14: `just` ∈ mise tools after migration
V15: `go-task` ⊥ mise tools after migration
V16: CLAUDE.md updated: ∀ `task <x>` → `just <x>`
V17: lefthook.toml audited; ∀ `task` references → `just`
```

### Migration safety

```
V18: both Taskfile & justfile functional in parallel during migration — ⊥ remove Taskfile until ∀ recipes verified
V19: ∀ recipe → manual smoke-test before Taskfile removal (non-destructive recipes only; destructive ones verified by review)
```

---

## §T — Tasks

### Phase 1 — Setup

| id | status | task | cites |
|----|--------|------|-------|
| T1 | . | Add `just` to mise tools in `.mise.toml` | V14 |
| T2 | . | Create `justfile` root with exports (KUBECONFIG, SOPS_AGE_KEY_FILE, TALOSCONFIG, MINIJINJA_CONFIG_FILE), vars, and `import` for ∀ 5 modules | V3,V12 |

### Phase 2 — Migrate modules

| id | status | task | cites |
|----|--------|------|-------|
| T3 | . | Write `.justfiles/kubernetes.just`: `cleanup-pods`, `sync-externalsecrets` | V1,V5,V6 |
| T4 | . | Write `.justfiles/postgres.just`: `backup` | V1,V5 |
| T5 | . | Write `.justfiles/volsync.just`: `unlock`, `list`, `snapshot`, `snapshot-all`, `restore` | V1,V5,V6 |
| T6 | . | Write `.justfiles/bootstrap.just`: `talos`, `apps` | V1,V5 |
| T7 | . | Write `.justfiles/talos.just`: all 8 tasks; `[private]` on `down`/`up`; `[confirm]` on `reset`; `cd` for dir; shell loop for `apply-cluster` | V1,V2,V5,V6,V8,V9,V10 |
| T8 | . | Add root `reconcile` recipe | V12 |

### Phase 3 — Verify & cutover

| id | status | task | cites |
|----|--------|------|-------|
| T9  | . | Run `just --list`; confirm ∀ public recipes visible with descriptions | V4 |
| T10 | . | Smoke-test non-destructive recipes: `just reconcile`, `just kubernetes-cleanup-pods`, `just volsync-list APP=<x> NS=<x>` | V18,V19 |
| T11 | . | Audit `lefthook.toml` for `task` references; update to `just` | V17 |
| T12 | . | Update CLAUDE.md: replace ∀ `task <x>` with `just <x>` | V16 |

### Phase 4 — Cleanup

| id | status | task | cites |
|----|--------|------|-------|
| T13 | . | Remove `go-task` from `.mise.toml` | V15 |
| T14 | . | Delete `Taskfile.yaml` | V18 |
| T15 | . | Delete `.taskfiles/` directory | V18 |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|

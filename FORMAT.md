# SPEC FORMAT (MULTI-FILE)

Multiple files. Shared format. Every cavekit command reads relevant ones.

## FILE LAYOUT

- Core Spec: `SPEC.md` (repo root)
- Feature Specs: `specs/<name>.spec.md`

Rule:
- Core = global truth (shared invariants, constraints, interfaces)
- Feature = scoped behavior (extends core)
- Never duplicate. Always reference.

## SECTIONS

Same in every spec file.

Fixed order. Fixed headers. Addressable.

```
# SPEC

## §G GOAL
one line. what code must do.

## §C CONSTRAINTS
- bullet. non-negotiable boundary.
- bullet. tech/lang/lib locked in.

## §I INTERFACES
external surface. what world sees.
- cmd: `foo bar` → stdout JSON
- api: POST /x → 200 {id}
- file: `config.yaml` schema …
- env: `FOO_KEY` required

## §V INVARIANTS
numbered. testable. each ! MUST hold.
V1: ∀ req → auth check before handler
V2: token expiry ≤ ⊥ allowed
V3: DB write ! in transaction

## §T TASKS
pipe table. ids monotonic (never reused). status: `x` done / `~` wip / `.` todo.
id|status|task|cites
T1|.|scaffold repo|-
T2|.|impl §I.api POST /x|V2
T3|x|add §V.1 middleware|V1,I.api

## §B BUGS
pipe table. backprop log. each row = bug + invariant that catches recurrence.
id|date|cause|fix
B1|2026-04-20|token `<` not `≤`|V2
B2|2026-04-21|race on write|V3
```

**Table cell rules**: literal `|` → escape as `\|`. Backticks OK. Cells trimmed. Empty = `-`.

## CROSS-SPEC ADDRESSING

Global addressing now includes file context.

Forms:
- Core:
  * SPEC.md §V.2
  * shorthand: V.core.2
- Feature:
  * specs/auth.spec.md §V.1
  * shorthand: V.auth.1

Tasks can cite across specs:

`T5|.|add auth check|V.auth.1,V.core.2,I.api`

Rule:

- Never restate invariant from another file
- Always reference

## ADDRESSING

`§<S>.<n>` still valid within a file

Cross-file requires qualifier:

- V.core.2
- V.auth.1

Zero ambiguity.

## CAVEMAN ENCODING

Default for every section. Rules:

- Drop articles (a, an, the). Drop filler.
- Drop aux verbs (is, are, was) where fragment works.
- Short synonyms (fix > implement).
- Fragments fine.

**Preserve verbatim**: code, paths, identifiers, URLs, numbers, error strings, SQL, regex.

**Symbols** (save tokens, machine-readable):

```
→   leads to / becomes / triggers
∴   therefore / fix
∀   for all / every
∃   exists / some
!   must
?   may / optional
⊥   never / impossible / forbidden
≠   not equal / differs from
∈   in / member of
∉   not in
≤   at most
≥   at least
&   and
|   or
```

**Bad** (v1 prose):

> The authentication middleware must verify the token expiry on every request before allowing the handler to execute.

**Good** (v2 caveman):

> V1: ∀ req → auth check before handler

**Bad** (prose bug note):

> Fixed a bug where token expiry comparison used strict less-than instead of less-than-or-equal, causing tokens to be rejected exactly at their expiry timestamp.

**Good** (v2 caveman):

> B1: token `<` not `<=` ∴ tokens rejected @ expiry. §V.2 now ! `≤`.

## CORE VS FEATURE RULES

**Core spec** (`SPEC.md`)

- Global constraints
- Shared interfaces
- Cross-cutting invariants
- High-level tasks only

**Feature spec** (`specs/*.spec.md`)

- Feature goal
- Local constraints
- Feature interfaces
- Feature invariants
- Detailed tasks

Rule:

- If invariant spans multiple features → move to core
- f only one feature cares → keep local

## BUG LOGGING (MULTI-FILE)

Bug goes in one file only:

- Global issue → core §B
- Feature issue → that feature §B

If bug reveals system-wide flaw:

- Add invariant to core
- Reference from feature

## WHY CAVEMAN FOR SPECS

Spec loaded every invocation. 75% fewer tokens = 75% fewer dollars & faster reads.
Human skims fast too. Symbols unambiguous.

## FILE SIZE RULE

- Core should stay small (<300–500 lines target)
- Split into feature specs early, not late
- Do NOT grow core endlessly
- If any spec > 500 lines, compact §B (old bugs drop oldest) before splitting.

## WRITES

| command | writes | target |
|---|---|---|
| `/spec new` | creates | core or feature |
| `/spec amend` | edits | chosen file |
| `/spec bug` | appends | correct file (§B + §V) |
| `/build` | flips | §T status cell in relavante spec `.` → `~` → `x` |
| `/check` | — | read only |

That is whole format.

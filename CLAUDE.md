# ISS-GF BI — AI Coding Instructions

> For AI assistants working on the ISS-GF Power BI report stack.
> Pointers, communication rules, conventions. Keep it lean.

## Project identity

- **Project**: Power BI report stack for **ISS-GF** — one client, one workspace, one repo.
- **Report projects**: the client system is a growing set of report projects, each in its own
  top-level `<CODE>/` folder (`AVS/`, `COMS/`, …). A report project is not a business domain.
- **Goal**: maintain and evolve the client's reports fast and safely — consistent design, correct measures, clean diffs.
- **Everything is code**: reports are **PBIP** projects (TMDL semantic model + PBIR report). Power BI Desktop is only for authoring visuals interactively and for render-verification.

## Stack

- **PBIP format** — every report is a sibling triple `<Name>.Report/` + `<Name>.SemanticModel/` + `<Name>.pbip`, inside its report project folder `<CODE>/`.
- **Data**: PostgreSQL on Azure — see `context/datasources/sources.md`. Much of the report SQL lives in a DB table (`public.sql_source`), **not** in this repo; edits there don't show in a git diff.
- **TMDL** for semantic models, **PBIR** (`definition/` folder, `definition.pbir` version 4.0+) for reports.
- **No** PBIR-Legacy edits (`report.json`) — if found, flag it; upgrade happens in Desktop only.
- Batch tooling: Python scripts in `_scripts/` (idempotent, check-before-set).

## Structure

```
<CODE>/                   → one folder per report project (AVS/, COMS/, …)
  <Name>.Report/          → PBIR report definition
  <Name>.SemanticModel/   → TMDL model definition
  <Name>.pbip
  __backup__/             → *.pbix exports (backup only, gitignored)
context/
  business-logic.md       → KPI definitions, calculation rules, fiscal calendar, naming
  reports/                → one file per report project (avs.md, coms.md, …)
  domains/                → one file per cross-report business domain (empty for now)
  datasources/
    sources.md            → systems, refresh schedules, gateways, credentials owners
    sql/                  → ★ SQL DB tables & schemas: one file per schema/table,
                            columns, types, keys, grain, join paths, known quirks
_scripts/                 → reusable batch scripts + validate.py
_templates/               → house theme.json, style snippets, starter visuals
.log/
  coms/                   → coms {yyyy-mm-dd}.md
  plan/                   → active plans / boards
  daily/                  → daily notes + EOD closes
.claude/skills/           → pbip-editor, dax-sql-formatter
```

- **`context/` is the single seam for business truth** — before writing or changing any DAX/measure/filter logic, read the relevant `reports/*.md`, `domains/*.md` and `datasources/sql/*` files. Never infer table grain, join paths, or KPI definitions from column names when a schema doc exists; if the doc is missing or stale, say so and ask.
- `context/datasources/sql/` is the source of truth for what the DB actually contains — model changes (new columns, renamed fields) start by checking here, and schema doc updates land in the same commit as the model change that used them.

## Report registry

> Updatable — add a row when a report is onboarded, edit when scope changes, mark retired instead of deleting.

| Report | Code | Folder | Context doc | Description | Status |
|---|---|---|---|---|---|
| Tracking customer version | AVS | `AVS/Tracking customer version.*` | `context/reports/avs.md` | Shipment / container / SKU tracking, 6 pages, RLS by client id via `CUSTOMDATA()` | active |
| Coms report | COMS | `COMS/Coms report.*` | `context/reports/coms.md` | EK + PO views, 3 pages, FX table, no RLS | active |

## Available skills

- **pbip-editor** (`.\.claude\skills\pbip-editor`) — use it for **every** report/model edit (visual design attrs, measures, visual calculations, batch changes, structure questions).
- **dax-sql-formatter** (`.\.claude\skills\dax-sql-formatter`) — house formatting style; applies silently to **every** SQL statement and DAX expression that gets written or shown.

These two are the only skills in this workspace; don't reference others.

## Conventions

### PBIX = backup, never source
- `*.pbix` files are **read-only backups** (pre-upgrade snapshots, Desktop exports). Never edit, parse, or "fix" them.
- Gitignored by default (see below). They live in the report project's own `<CODE>/__backup__/` folder and are tracked via Git LFS only on explicit request.

### .gitignore (root)
```gitignore
*.pbix
**/.pbi/localSettings.json
**/.pbi/cache.abf
**/cache.abf
```

### Editing rules
- All edits go through the **pbip-editor** skill workflow: locate → read → surgical edit → validate.
- Preserve `name`, `lineageTag`, `queryRef`, schema `$schema` versions byte-for-byte unless the task is the rename itself.
- House design standard lives in `_templates/` + `context/business-logic.md` — apply from there, don't restate per prompt.
- After any batch edit: run `python _scripts/validate.py` (JSON parse + literal encoding + TMDL tab check).

### Naming
- Report project folders: short `UPPERCASE` code (`AVS`, `COMS`).
- PBIP folders inside them: **exactly** the published report name as Desktop wrote it — don't re-case or rename (`Tracking customer version.Report`, not `TrackingCustomerVersion.Report`). Renaming breaks the `.pbip` and `definition.pbir` paths.
- Scripts: `kebab-case.py`, verbs first (`apply-housestyle.py`).
- Context files: `kebab-case.md`; report docs `context/reports/<code>.md`; SQL schema docs `<schema>.<table>.md`.

### Git
- After any change, output git commands as a single copy-paste bash block. **Do not execute; do not touch the working tree.**
```bash
git add "<paths>"
git commit -m "<type>: <message>"
git push
```
- Wrap file paths in double quotes. One report (or one batch theme) per commit.
- Batch changes touching many reports → suggest a branch (`style/<change>`), review diff, merge.

### Verification
- `python _scripts/validate.py` green before considering a change done.
- Render-verification in Power BI Desktop (open the touched `.pbip`) — Desktop is the final validator; blocking errors name the offending file.

## Logging (lightweight)

- `.log/coms/coms {yyyy-mm-dd}.md` — append a one-line entry per user request + brief response to today's file (create if absent; one file per day, sibling to `.log/plan/` and `.log/daily/`). Tag `#decision` / `#idea` / `#bug` inline for grep.
- `.log/plan/` — active plan/board files; update in place, don't fork copies.
- `.log/daily/` — one note per working day: what shipped, what's blocked, next.
- **EOD routine** (on "close the day" or clear end-of-session): append to today's daily note — reports touched, commits suggested, open threads, tomorrow's first task; verify today's coms file exists and registry rows for any onboarded/changed reports are updated. That's the whole ceremony.
- **Derive counters, never increment them.** Ages and tallies ("Nth day", "Nth report onboarded") must be computed from a stated origin date/commit each time they're written. A restated number is never re-derived and always drifts.
- **A session that crosses midnight logs each entry to its own date, and does not close the new day.** Closing a day that is 20 minutes old leaves the calendar day with a closed daily and no plan.

## Core coding rules

1. **Think before editing** — state assumptions, surface tradeoffs, ask when genuinely unclear (which report, which visual, model-scope vs visual-scope fix). Don't pick silently between real alternatives.
2. **Business truth from `context/`** — a measure is wrong if it contradicts `business-logic.md`, even if the DAX is elegant. Schema questions resolve in `datasources/sql/`, not by guessing.
3. **Surgical diffs** — small, reviewable changes are the entire point of TMDL/PBIR. Touch only what the task requires; match the file's existing serialization; don't reformat untouched JSON/TMDL.
4. **Goal-driven** — turn tasks into verifiable goals ("fix formatting" → "all date columns render yyyy-MMM-dd; validate.py green; diff shows only formatString lines") and loop until verified.
5. **Model-scope beats visual-scope** — when a fix could live in the theme or the model instead of 30 visual.json overrides, propose that first.

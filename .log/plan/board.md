# Active board — ISS-GF BI

> Update in place. Don't fork copies. Origin date for derived counters: **2026-08-10** (commit `9ac9f79`).

---

# Today — 2026-08-11 (day 2)

> Draft plan, not yet executed. Day 2 derived: (2026-08-11 − 2026-08-10) + 1.

## A. `[DEL]` the orphaned PO line status objects — *the day's task*

Original ask was to remove the "PO line status" filter from COMS. **Cancelled** — instead, mark the
two orphaned model objects with a `[DEL]` prefix so they're flagged for a later cleanup pass.

**The slicer stays.** Note it is titled "PO line status" but bound to `_PO_VIEW_[_status]`
(lifecycle status), so it is a different object entirely and is out of scope.

| # | File | Change |
|---|---|---|
| A1 | `__COMS/Coms report.SemanticModel/definition/tables/_PO_VIEW_.tmdl` (line 1375) | `column _po_line_status` → `column '[DEL] _po_line_status'`. **Keep `sourceColumn: _po_line_status` and `lineageTag` unchanged** — the source column is the SQL contract, only the model-facing name changes. |
| A2 | `__COMS/Coms report.SemanticModel/definition/tables/__FX__.tmdl` (line 24) | `measure 'PO line status PO view (FX)'` → `measure '[DEL] PO line status PO view (FX)'`. Keep `lineageTag`. |
| A3 | `__COMS/Coms report.SemanticModel/definition/cultures/en-US.tmdl` | Update the Q&A bindings that name the old objects: `ConceptualProperty` at lines ~17544 and ~17695, plus the term keys at ~17555 / ~17701 / ~17706. All are `"State": "Generated"`, so Desktop would regenerate them — but leaving them stale means the file references names that no longer exist. |

Both objects are **unused by any visual** (verified: no reference to `_po_line_status` or to the
`(FX)` measure anywhere in the report definition), so nothing in the report can break.

Not touched: `__COMS/Coms report.SemanticModel/TMDLScripts/Script 1.tmdl` holds a copy of the measure
definition. It is a saved authoring script, not part of the model.

**Verify**: `python _scripts/validate.py` green → open `__COMS/Coms report.pbip` in Desktop → model
loads with no missing-object error, both objects appear with the `[DEL]` prefix, PO view page renders
unchanged.

## B. Adopt the `__CODE__` folder convention

`AVS/` → `__AVS/` and `COMS/` → `__COMS/` (renamed 2026-08-11, 172 files each). Every documented path
is stale. Fix in the same commit:

- `CLAUDE.md` — Structure tree, naming rule (`UPPERCASE code` → `__UPPERCASE__ code`), registry rows.
- `context/reports/avs.md`, `context/reports/coms.md` — folder paths.
- `context/datasources/sources.md`, `context/datasources/sql/README.md` — the report↔file map.
- This board's Report projects table.

Stage the renames so git records them as renames, not delete+add.

## C. Housekeeping

- Separate the **uncommitted Desktop edits** already sitting in COMS from the work above. They are
  not all cosmetic:
  - **Two visuals deleted from the PO view page** — a textbox (`41d9fad5…`) and a dropdown slicer
    titled **"Status"** bound to `_PO_VIEW_[_status]` (`5102d740…`). Report is 109 → 107 visuals.
  - `pages.json` active page → EK view; a `sortDefinition` on `_po_no_ekporef` and sub-pixel
    position nudges on two EK view visuals. Cosmetic.
  - Decide: keep the deletions (own commit, described as such) or restore from `HEAD`.
  - Note there were **two** `_status` slicers on that page — "Status" (deleted) and "PO line status"
    (`541655e7…`, still present). Worth confirming the surviving one is the intended keeper.
- Commit yesterday's EOD close, today's coms/daily files and the `__FX__` correction.

---

## Report projects

| Code | Report | Format | Onboarded | Context doc | State |
|---|---|---|---|---|---|
| AVS | Tracking customer version | PBIR 4.0 + TMDL | 2026-08-10 | `context/reports/avs.md` | audited, untouched |
| COMS | Coms report | PBIR 4.0 + TMDL | 2026-08-10 | `context/reports/coms.md` | audited, untouched |

## Repo readiness

- [x] `.log/` tree (coms / daily / plan)
- [x] `.gitignore` covers `*.pbix` + cache
- [x] `_scripts/validate.py` — green, negative-tested
- [x] `context/` scaffold
- [x] `CLAUDE.md` matches the repo
- [ ] `_templates/` — no house theme yet
- [x] `context/datasources/sql/` — 34 SQL files mirrored + `README.md` index
- [x] `context/domains/shipment-tracking.md` — COMS/AVS domain documented from the SQL
- [ ] `context/datasources/sql/` — no per-table schema doc (`<schema>.<table>.md`) yet
- [ ] `context/business-logic.md` — domain rules landed; report-level DAX KPIs still undefined

## Open threads

1. ~~**`public.sql_source` mirroring**~~ — **resolved 2026-08-10**: SQL is mirrored into `context/datasources/sql/`. Standing rule: edit file → run against Postgres → refresh model → commit file, same commit.
2. **Ops unknowns** — refresh schedule, gateway, credentials owner, workspace name.
3. **House theme** — AVS on `CY24SU10`, COMS on `CY25SU11`. Pick one house theme.json in `_templates/` and apply model-scope, not per-visual.
4. **AVS RLS semantics** — `CompanyID_AUTO` vs `CompanyID_MAN` (`_ETA_AUTO` / `_ETA_MAN`): what distinguishes them? Both filter `__MAIN__` by `CUSTOMDATA()`, so who sets CUSTOMDATA?
5. **Grain + join paths** for `__MAIN__` / `__CONTAINER__` / `__SKU__` — undocumented; must not be guessed before any DAX work.
6. **COMS `__FX__`** — rate source, rate date, which measures convert.
7. **Scratch pages** — AVS `Cal test` (0 visuals), AVS `Page 1` (1 visual), COMS `EK check`. Delete or keep?
8. ~~**EK VIEW grain**~~ — **confirmed 2026-08-10 as designed**: one row per currently active (main) freight order; other linked orders aggregated into the secondary-order columns.
9. **`COMS DUMMY`** — `COMS COUNTRY SLA.sql` and `COMS SUPPLIER REACTION TIME SLA.sql` write `_report = 'COMS DUMMY'`. Intentional or leftover? Do they feed `portal.sla_master_coms`?
10. ~~**`_crd_actual` array order**~~ — **confirmed 2026-08-10 as deliberate**, left as a hook for further amendments. Do not "fix".
11. ~~**`purchase_order_on_freight_unit.purchase_order_id` → `PurchaseOrderLine.id`**~~ — **confirmed 2026-08-10 correct**. Documented as a key relationship, not a defect.

## Next

Tomorrow's first task: close threads 9 and 4, then write the first per-table schema docs for
`purchase_order_on_freight_unit` and `PurchaseOrderLine`.

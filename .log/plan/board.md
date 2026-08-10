# Active board — ISS-GF BI

> Update in place. Don't fork copies. Origin date for derived counters: **2026-08-10** (commit `9ac9f79`).

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
8. **EK VIEW grain wording** — brief says "grouped by Purchase order"; the SQL groups by freight order (`_fo_id`) and picks a primary PO per FO. Confirm which is meant before any per-PO measure is written.
9. **`COMS DUMMY`** — `COMS COUNTRY SLA.sql` and `COMS SUPPLIER REACTION TIME SLA.sql` write `_report = 'COMS DUMMY'`. Intentional or leftover? Do they feed `portal.sla_master_coms`?
10. **`_crd_actual` array order** — reads `coalesce(date_templates, custom_dates)` while `_crd` / `_crd_estimated` read the opposite order. Confirm intent.

## Next

Tomorrow's first task: close threads 8, 9 and 4 (they're all one conversation), then write the first
per-table schema docs for `purchase_order_on_freight_unit` and `PurchaseOrderLine`.

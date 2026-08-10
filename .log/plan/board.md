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
- [ ] `context/datasources/sql/` — no schema doc written yet
- [ ] `context/business-logic.md` — KPI section still empty

## Open threads

1. **`public.sql_source` mirroring** — report SQL lives in Postgres, not in git. Mirror it into `context/datasources/sql/`, or accept the DB as the source of truth? Blocks all schema documentation.
2. **Ops unknowns** — refresh schedule, gateway, credentials owner, workspace name.
3. **House theme** — AVS on `CY24SU10`, COMS on `CY25SU11`. Pick one house theme.json in `_templates/` and apply model-scope, not per-visual.
4. **AVS RLS semantics** — `CompanyID_AUTO` vs `CompanyID_MAN` (`_ETA_AUTO` / `_ETA_MAN`): what distinguishes them? Both filter `__MAIN__` by `CUSTOMDATA()`, so who sets CUSTOMDATA?
5. **Grain + join paths** for `__MAIN__` / `__CONTAINER__` / `__SKU__` — undocumented; must not be guessed before any DAX work.
6. **COMS `__FX__`** — rate source, rate date, which measures convert.
7. **Scratch pages** — AVS `Cal test` (0 visuals), AVS `Page 1` (1 visual), COMS `EK check`. Delete or keep?

## Next

Tomorrow's first task: close threads 4, plus the EK/PO meaning and the scratch-page question — then
decide thread 1.

# Business logic — ISS-GF

> Single seam for business truth. Read before writing or changing any DAX/measure/filter logic.
> Empty section = not yet documented. If a rule you need is missing here, ask — don't infer it.

## KPI definitions

_TODO — no KPI has been formally defined yet. Add one block per KPI: name, plain-language
definition, DAX shape, grain it is valid at, owner._

## Calculation rules

_TODO — rounding, currency handling, exclusion rules._

Known so far:
- `COMS/__FX__` table exists and carries FX handling. TODO: document rate source, rate date, and
  which measures convert.

## Fiscal calendar

- Date dimension is generated in M, not sourced from the DB: `customCalendar` expression in
  `AVS/Tracking customer version.SemanticModel/definition/expressions.tmdl` (line 1).
- It is a **custom-week** calendar: takes `start_of_cal`, `end_of_cal`, `start_of_week`
  (1 = Monday … 7 = Sunday). Week boundaries are **clamped to the calendar year** — week 1 starts on
  or after Jan 1, the last week ends on or before Dec 31.
- Columns produced include `Year`, `Year-Mon` (`yyyy-MM`), `Sort Column` (`Year * 100 + Month`).
- TODO: confirm which `start_of_week` value ISS-GF actually uses, and whether the fiscal year is the
  calendar year.

## Naming

- Model tables: `__NAME__` = fact/source table, `NAME_param` = field-parameter table,
  `_NAME` = helper/utility table (e.g. `_ROLE`, `_calendar`, `_DATE_SWITCHER`, `__VISIBILITY`).
- TODO: measure naming and display-folder conventions.

## House design standard

_TODO — no `_templates/theme.json` exists yet. Reports currently sit on Microsoft base themes
(`CY24SU10` for AVS, `CY25SU11` for COMS). Deciding a house theme is an open thread._

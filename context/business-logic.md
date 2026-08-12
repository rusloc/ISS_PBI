# Business logic — ISS-GF

> Single seam for business truth. Read before writing or changing any DAX/measure/filter logic.
> Empty section = not yet documented. If a rule you need is missing here, ask — don't infer it.

## Domains

| Domain | Doc | Used by |
|---|---|---|
| Shipment tracking (PO → freight order → shipment) | [`domains/shipment-tracking.md`](domains/shipment-tracking.md) | COMS, AVS |

## KPI definitions

### Shipment tracking (COMS)

Full definitions in the domain doc; the rules that most often get broken:

- **Exception status (RAG)** — five milestone buckets (`_01`…`_05`) scored `dark green` / `green` /
  `yellow` / `red`, rolled up per PO line into `_06_expt_status`. Thresholds come from
  `portal.sla_master_coms`, **not** from the query. A line with outstanding balance can never be
  green.
- **Health check** — actual vs committed lead time bucketed `Healthy` / `Minor` (≤30d) /
  `Moderate` (≤45d) / `Major` (≤60d) / `Severe` (>60d), with a 500-day data-quality guard that
  zeroes absurd sums. Any new lead-time measure must keep that guard.
- **Performance ratios** — `*_perf` fields are ratios where **`< 1` means late**. Don't invert them.
- **Reason code** — first failing segment in fixed order (PR to PO → Product Readiness → Booking →
  Trans Shipment → Custom Clearance); `null` when healthy.
- **NBD gap metrics** (`_nbd_2_crd`, `_nbd_2_eta`, `_nbd_2_del`) exclude orders that haven't
  started: statuses `Cancelled`, `Pending`, `Pending Quotation`, `Pending Quotation Approval`,
  `Pending Booking`, `Not Due`.

_TODO — no report-level DAX KPI has been formally defined yet. Add one block per KPI: name,
plain-language definition, DAX shape, grain it is valid at, owner._

## Calculation rules

### Date fields are not interchangeable

The most common source of a wrong COMS number. Three families, three purposes — see the domain doc
for the exact fallback chains:

| Family | Use it for |
|---|---|
| `_pta` / `_ptd`, `_eta` / `_etd` | the **planned commitment** — exception scoring |
| `_full_eta` / `_full_etd` | **best known** value — display, lead-time maths |
| `_arrival_date_actual` / `_departure_date_actual` (ATA/ATD) | **hard evidence** the event happened |

ATA/ATD exclude transshipment legs (`comments ~* 'Transshipment Port: No'`). Never substitute one
family for another to fill a gap — that is what the `coalesce` chains already do, deliberately.

### Grain

- **PO VIEW**: purchase order **line** × freight order. Partition key `(_po_no_ekporef, _line_no)`.
- **EK VIEW**: one row per **freight order**, attributes taken from the *primary* PO
  (`_sort = 1`, ranked by `current_po_promised_dt`), others collapsed into `_secondary_po`.
- A measure valid at one grain is usually wrong at the other. State the grain in the measure
  description.

### Currency

Charges are carried natively and converted in the SQL: `_*_charges_aed`, `_*_charges_usd`,
`_*_charges_local`, with `_currency_native` / `_iss_dom`. TODO: document the rate source and rate
date used by the query.

Note: COMS's `__FX__` table is **not** about currency — it is a measures table of
`FIRSTNONBLANK(...)` column wrappers (`FX` = fix). See `reports/coms.md`.

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
- SQL output columns: every column is aliased with a leading `_` (house style — see the
  `dax-sql-formatter` skill). Exception buckets are numbered so they sort in milestone order
  (`_01_…` → `_05_…`, roll-up `_06_…`).
- TODO: measure naming and display-folder conventions.

## House design standard

_TODO — no `_templates/theme.json` exists yet. Reports currently sit on Microsoft base themes
(`CY24SU10` for AVS, `CY25SU11` for COMS). Deciding a house theme is an open thread._

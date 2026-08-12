# COMS — Coms report

- **Folder**: `COMS/Coms report.*` (PBIP: `.Report` + `.SemanticModel` + `.pbip`)
- **Format**: PBIR v4.0 (enhanced) + TMDL — editable as code
- **Base theme**: `CY25SU11` (Microsoft base theme, no house theme applied)

## What it is

A **client-facing shipment tracker**: one report where a client can follow their purchase orders all
the way to delivery and check every attribute that matters on the way — ETD, ETA, PTD, PTA, ATD,
ATA, freight orders, purchase order lines and shipments, side by side.

**Primary audience: the Emirates (EK) team** — the report is shaped around their demand, and the EK
view is named for them.

Business semantics — entity hierarchy, quantity flow, the full date vocabulary, the exception/RAG
framework, lifecycle statuses and lead-time metrics — live in
[`../domains/shipment-tracking.md`](../domains/shipment-tracking.md). **Read it before changing any
measure or query.**

## Two views, two grains

The report is built from two independent SQL queries. They cover the *same underlying data* at
**different levels of aggregation** — this is the single most important fact about the report.

| | **PO VIEW** | **EK VIEW** |
|---|---|---|
| Page | `PO view` (39 visuals) | `EK view` (35 visuals) |
| Model table | `_PO_VIEW_` | `_EK_VIEW_` |
| Field parameter | `PO_VIEW_PARAM` | `EK_VIEW_PARAM` |
| M expression | `PO_SQL_SOURCE` | `EK_SQL_SOURCE` |
| `sql_source` key | `_report = 'COMS'`, `_page = 'PO VIEW'` | `_report = 'COMS'`, `_page = 'EK VIEW'` |
| Source file | `context/datasources/sql/COMS PO VIEW.sql` (2071 lines) | `context/datasources/sql/COMS EK VIEW.sql` (1607 lines) |
| **Grain** | **Purchase Order LINE × freight order** | **one row per freight order** |
| Base table | `portal.purchase_order_on_freight_unit` | `portal."PurchaseOrderLine"` → de-duplicated link → `portal.freight_unit` |

### PO VIEW — grouped around the Purchase Order Line

Structure, per the query's own header:

1. **PO enriched block** — three waterfall CTEs: `_pre_calc` (all base attributes and joins) →
   `_calc` (metrics on top of `_pre_calc`) → `_main` (final metrics using both).
2. **PO pending block** — one query capturing PO lines whose remaining quantity > 0.
3. **Wrapper block** — `union all`s the two, adds `_master_line` and the PO-level `_06_expt_status`
   exception roll-up.

Shipped lines (`_line_type = 'Enriched'`) carry PO line **plus** freight-order attributes; remaining
lines carry only the balance, and disappear once shipments fully cover the ordered quantity.

### EK VIEW — one level up

Same three-CTE waterfall (`pre_calc` → `calc` → `main`), then **aggregated up**: the final `select`
does `group by _fo_id`, collapsing every PO on a freight order onto one line.

**Confirmed grain (2026-08-10)**: one row per **currently active (main) freight order**. The other
orders linked to the purchase order are aggregated into the *secondary order* columns on that same
line. This is the intended design, not an accident of the query.

How the collapse works — this is the part to be careful with:

```sql
,row_number()  over (partition by f.id order by p.current_po_promised_dt)        _sort
,first_value(p.po_no) over (partition by f.id order by p.current_po_promised_dt) _primary_po
```

- POs on a freight order are ranked by `current_po_promised_dt`; **`_sort = 1` is the primary
  (active/main) PO**.
- Nearly every attribute is taken as `max(...) filter (where _sort = 1)` — i.e. **the primary PO's
  value**, not an average or a sum across the freight order.
- The remaining linked POs are string-aggregated into `_secondary_po`, so one line shows the main
  order and lists the secondary ones.
- The query then `union all`s its own pending block (`remaining_quantity > 0`).

`_fo_id` is a technical key (sha256 of `freight_unit.id`) and is not shown in the report.

**Consequence for measures**: a measure written here is per *freight order*, and any attribute it
reads is the **primary PO's** value. Anything that must be per-PO or summed across all linked POs
belongs in PO VIEW, not here.

## Model

5 tables, no RLS roles.

| Table | Role |
|---|---|
| `_PO_VIEW_` | PO VIEW fact |
| `_EK_VIEW_` | EK VIEW fact |
| `PO_VIEW_PARAM`, `EK_VIEW_PARAM` | field parameters driving the column pickers |
| `__FX__` | **measures table**, not FX rates — one `Placeholder` column and 7 measures |

`__FX__` holds `FIRSTNONBLANK(...)` wrappers that let a column be used where a measure is required
(field parameters, matrix values): `quantity`, `billing notes PO view (FX)`, `billing notes EK (FX)`,
`PO line status PO view (FX)`, `_PO no PO view (FX)`, `_PO no EK view (FX)`,
`_po outer qty PO VIEW (FX)`. The `(FX)` suffix means *fix/wrapper*, not foreign exchange.

Charge columns are carried in three currencies: `_*_charges_aed`, `_*_charges_usd`,
`_*_charges_local` (with `_currency_native` / `_iss_dom`).

## Pages

| Page | Visuals | Visibility |
|---|---|---|
| EK view | 35 | visible |
| PO view | 39 | visible |
| EK check | 35 | hidden in view mode — QA copy of EK view |

4 bookmarks.

## Editing rules for these two queries

They are 2071 and 1607 lines of interdependent CTEs, jsonb extraction and window functions. Treat
every change as surgical:

1. **Read `../domains/shipment-tracking.md` first** — most "wrong number" questions are a date-field
   or grain misunderstanding, not a bug.
2. **Identify the block** before editing: `_pre_calc` (raw attributes) / `_calc` (derived metrics) /
   `_main` (final) / wrapper / pending. A metric added at the wrong level is either invisible or
   silently wrong.
3. **Never change the grain.** In PO VIEW the partition key is `(_po_no_ekporef, _line_no)`; in EK
   VIEW it is `_fo_id` with `_sort = 1` as primary. Adding a join that fans out breaks both.
4. **SLA day-counts are data** — edit `portal.sla_master_coms`, not the `case` expressions.
5. **Deploy is a DB write**, not just a file save — see below.
6. Mirror the change back into `context/datasources/sql/` in the same commit.

## Deploy path

Each `.sql` file is a self-contained deploy script: it assigns the query to a session variable and
writes it into the `sql_source` table the model reads.

```sql
set dev.ek_view =
$sql$
    ...query...
$sql$;

update sql_source
set  _code    = current_setting ( 'dev.ek_view' )
    ,_updated = now()
where 1=1
    and _page   = 'EK VIEW'
    and _report = 'COMS';
```

So: **edit the file → run the file against Postgres → refresh the semantic model.** Editing the file
alone changes nothing in the report; editing the DB alone leaves the repo lying.

`COMS PO VIEW.sql` also carries a commented-out dev routine that rewrites `portal.` → `portal_dev.`
and populates `public.coms_po_view_demo` — a dev/demo path, disabled.

## Related SQL

`COMS COUNTRY SLA.sql` and `COMS SUPPLIER REACTION TIME SLA.sql` sit in the same folder — SLA
reference feeds. TODO: confirm whether either populates `portal.sla_master_coms`.

## Open questions

- `__FX__`: rate source, rate date, which measures convert.
- Is `EK check` a permanent QA page or a leftover?
- Refresh schedule and workspace.
- `COMS COUNTRY SLA.sql` / `COMS SUPPLIER REACTION TIME SLA.sql` write `_report = 'COMS DUMMY'` —
  intentional, or a leftover? Do they feed `portal.sla_master_coms`?

Closed 2026-08-10: EK VIEW grain (confirmed as designed), the
`purchase_order_on_freight_unit → PurchaseOrderLine.id` key (correct), and the `_crd_actual` array
order (deliberate).

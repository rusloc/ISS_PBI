# SQL source mirror

Every `.sql` file here is the **deployable source** of one row in the Postgres `sql_source` table,
which is what the semantic models actually read (see `../sources.md`).

## The deploy pattern

Each file is self-contained: assign the query to a session variable, then write it into
`sql_source` keyed by `(_report, _page)`.

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

**Editing the file changes nothing on its own.** The loop is: edit file → run file against Postgres
→ refresh the semantic model → commit the file. Editing the DB without updating the file leaves this
mirror lying, which is worse than not having it.

## Naming

`<REPORT KEY> <PAGE KEY>.sql`, matching the `_report` / `_page` values the file writes — so the file
name tells you which model expression consumes it.

## Inventory

| File | `_report` | `_page` | Lines |
|---|---|---|---|
| COMS PO VIEW.sql | COMS | PO VIEW | 2071 |
| COMS EK VIEW.sql | COMS | EK VIEW | 1607 |
| COMS COUNTRY SLA.sql | COMS DUMMY | COUNTRY SLA | 87 |
| COMS SUPPLIER REACTION TIME SLA.sql | COMS DUMMY | SUPPLIER SLA | 86 |
| TRACKER CLIENT PROD MAIN.sql | TRACKER CLIENT PRODUCTION | MAIN | 338 |
| TRACKER CLIENT PROD SKU.sql | TRACKER CLIENT PRODUCTION | SKU | 117 |
| TRACKER CLIENT PROD CONTAINER.sql | TRACKER CLIENT PRODUCTION | CONTAINER | 111 |
| TRACKER CLIENT DEMO MAIN.sql | TRACKER CLIENT DEMO | MAIN | 236 |
| TRACKER CLIENT DEMO SKU.sql | TRACKER CLIENT DEMO | SKU | 86 |
| TRACKER CLIENT DEMO CONTAINER.sql | TRACKER CLIENT DEMO | CONTAINER | 97 |
| TRACKER MAIN APP.sql | TRACKER APP | MAIN | 282 |
| TRACKER SKU APP.sql | TRACKER APP | SKU | 92 |
| CLIENT ANALYSIS SHIPMENTS.sql | CLIENT ANALYSIS | SHIPMENTS | 122 |
| IC RECONCILE CLIENT SIDE DATA.sql | IC RECONCILE | CLIENT SIDE DATA | 306 |
| IC RECONCILE VENDOR SIDE DATA.sql | IC RECONCILE | VENDOR SIDE DATA | 307 |
| IC RECONCILE RLS.sql | IC RECONCILE | RLS | 505 |
| IC RECONCILE ACCRUALS.sql | IC RECONCILE | ACCRUALS | 46 |
| IC RECONCILE LOANS.sql | IC RECONCILE | LOANS | 58 |
| IC RECONCILE PAYMENTS.sql | IC RECONCILE | PAYMENTS | 68 |
| OVERDUE RECEIVABLES MAIN.sql | OVERDUE RECEIVABLES | MAIN | 615 |
| OVERDUE RECEIVABLES UNBOOKED.sql | OVERDUE RECEIVABLES | UNBOOKED | 245 |
| SALES GP CONTRIBUTION.sql | SALES GP | TOTAL GP | 179 |
| SALES GP RLS.sql | SALES GP | RLS | 64 |
| SALES_GP_COMMISSION_ALL_TABLES.sql | SALES GP COMMISSION | DAX | 931 |
| LOGIN INFO PKL.sql | PORTAL LOGIN INFO | PKL | 140 |
| LOGIN INFO USERS.sql | PORTAL LOGIN INFO | USERS | 78 |
| LOGIN INFO RLS.sql | PORTAL LOGIN INFO | RLS | 49 |
| OPERATIONS GEO RLS.sql | OPERATIONS | GEO RLS | 99 |
| OPERATIONS LOB RLS.sql | OPERATIONS | LOB RLS | 50 |
| OPERATIONS SERVICE RLS.sql | OPERATIONS | SERVICE RLS | 48 |
| __GEO RLS GLOBAL.sql | ALL | GOE RLS GLOBAL | 107 |
| CUSTOMER_TRANSACTIONS_INV_AND_PAY_OBT_FLAT_FULL.sql | — | — (no deploy statement) | 98 |
| _JSON BUILD OBJECT TEMPLATE.sql | — | — (snippet template) | 75 |

Only two of these feed a report in this repo today — **COMS** (`COMS *.sql`) and **AVS**
(`TRACKER CLIENT PROD *.sql`). The rest belong to reports not yet onboarded here; they are kept
because they share the same `sql_source` table and the same conventions.

## Quirks worth knowing

- `__GEO RLS GLOBAL.sql` writes `_page = 'GOE RLS GLOBAL'` — looks like a typo for `GEO`, but the
  model side must match it exactly, so **don't "fix" it** without checking every consumer.
- `COMS COUNTRY SLA.sql` and `COMS SUPPLIER REACTION TIME SLA.sql` write to `_report = 'COMS DUMMY'`,
  not `COMS`. TODO: confirm whether that is intentional or a leftover.
- `COMS PO VIEW.sql` ends with a commented-out dev routine that rewrites `portal.` → `portal_dev.`
  and loads `public.coms_po_view_demo`.

## Schema docs

Per-table documentation (`<schema>.<table>.md` — columns, types, keys, grain, join paths) has not
been written yet. The highest-value first targets, from the COMS work:
`portal.purchase_order_on_freight_unit`, `portal."PurchaseOrderLine"`, `portal.freight_unit`,
`portal.freight_unit_enrich`, `portal.sla_master_coms`, `public.sql_source`.

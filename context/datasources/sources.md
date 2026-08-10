# Data sources — ISS-GF

## PostgreSQL (single source for both reports)

| Field | Value |
|---|---|
| Server | `c-powerbicosmos.k4mjimliu3npzv.postgres.cosmos.azure.com` |
| Database | `powerbi` |
| Connector | `PostgreSQL.Database` (some queries wrap it in `Value.NativeQuery`, some use `[HierarchicalNavigation=true]`) |
| Gateway | TODO |
| Credentials owner | TODO |
| Refresh schedule | TODO |
| Workspace | TODO |

## The `public.sql_source` pattern ★

**Query text lives in the database, not in the model.** Both reports read a table
`public.sql_source` with columns:

| Column | Meaning |
|---|---|
| `_report` | report code — `"COMS"`, … |
| `_page` | page/view key — `"EK VIEW"`, `"PO VIEW"`, … |
| `_code` | the SQL statement itself |

The M pattern is: connect → filter `Schema = "public"` and `Name = "public.sql_source"` → expand
`Data` → filter to the `(_report, _page)` pair → use `_code`.

Consequences, and they matter:

- **Resolved 2026-08-10: the SQL is mirrored into `context/datasources/sql/`** — 34 deployable
  `.sql` files, each writing one `(_report, _page)` row. See that folder's `README.md` for the
  inventory and the deploy pattern.
- The mirror is only honest if the loop is respected: **edit file → run file against Postgres →
  refresh model → commit file**. A DB-only edit leaves the repo lying, which is worse than having no
  mirror at all.
- A model refresh can still change shape without a file changing here, if someone edits
  `sql_source` directly. Treat that as a bug to correct, not a workflow.

## Direct-query expressions (AVS)

`AVS/…SemanticModel/definition/expressions.tmdl` also holds inline SQL via `Value.NativeQuery`:
`__CLIENTS_SKU__`, `__CLIENTS_DIM__`, `__CLIENTS_MAIN__`, `_ETA_MAX_DATE`, plus `MAIN_SRC`,
`SKU_SRC`, `CONTAINER_SRC`. These *are* in the repo and *do* diff.

## Which file feeds which report

| Report | `_report` key | Files |
|---|---|---|
| COMS · Coms report | `COMS` | `COMS PO VIEW.sql`, `COMS EK VIEW.sql` |
| AVS · Tracking customer version | `TRACKER CLIENT PRODUCTION` | `TRACKER CLIENT PROD MAIN.sql`, `… SKU.sql`, `… CONTAINER.sql` |

## Table & schema docs

Per-table docs (`<schema>.<table>.md` — columns, types, keys, grain, join paths, known quirks) live
in the same folder. **None written yet.** First candidates, from the COMS work:
`portal.purchase_order_on_freight_unit`, `portal."PurchaseOrderLine"`, `portal.freight_unit`,
`portal.freight_unit_enrich`, `portal.sla_master_coms`, `public.sql_source`.

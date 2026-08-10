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

- Changing a report's SQL is a **database** edit, not a repo edit. It will not show in a git diff.
- The repo cannot be the source of truth for that SQL unless we mirror it into
  `context/datasources/sql/`. TODO: decide whether to mirror, and how to keep it honest.
- A model refresh can change shape without a single file changing here.

## Direct-query expressions (AVS)

`AVS/…SemanticModel/definition/expressions.tmdl` also holds inline SQL via `Value.NativeQuery`:
`__CLIENTS_SKU__`, `__CLIENTS_DIM__`, `__CLIENTS_MAIN__`, `_ETA_MAX_DATE`, plus `MAIN_SRC`,
`SKU_SRC`, `CONTAINER_SRC`. These *are* in the repo and *do* diff.

## Table & schema docs

One file per schema/table in `context/datasources/sql/`, named `<schema>.<table>.md` — columns,
types, keys, grain, join paths, known quirks. **None written yet.** First candidates:
`public.sql_source`, and the tables behind `__MAIN__` / `__CONTAINER__` / `__SKU__`.

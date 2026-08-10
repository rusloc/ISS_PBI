# AVS — Tracking customer version

- **Folder**: `AVS/Tracking customer version.*` (PBIP: `.Report` + `.SemanticModel` + `.pbip`)
- **Format**: PBIR v4.0 (enhanced) + TMDL — editable as code
- **Base theme**: `CY24SU10` (Microsoft base theme, no house theme applied)
- **Scope**: customer-facing shipment / container / SKU tracking

## Pages

| Page | Visuals | Visibility |
|---|---|---|
| Basic | 2 | hidden in view mode |
| Shipments | 38 | visible |
| Container | 34 | visible |
| SKU | 36 | visible |
| Cal test | 0 | hidden in view mode (scratch) |
| Page 1 | 1 | hidden in view mode (scratch) |

16 bookmarks. Active page on open: Shipments.

## Model

10 tables, 12 relationships.

| Table | Role |
|---|---|
| `__MAIN__` | main fact — shipment grain (TODO: confirm), carries `_client_id` |
| `__CONTAINER__` | container-level fact |
| `__SKU__` | SKU-level fact |
| `__VISIBILITY` | column/visual visibility control |
| `_calendar` | date dimension from `customCalendar` M function |
| `_DATE_SWITCHER` | date-field switcher |
| `_ROLE` | role-driven behaviour, columns `active_auto` / `active_man` |
| `SHIPMENT_param`, `CONTAINER_param`, `SKU_param` | field parameters; each has `_ETA_AUTO` / `_ETA_MAN` flags |

## Sources

Reads SQL text out of the `public.sql_source` indirection table (see `../datasources/sources.md`)
under `_report = 'TRACKER CLIENT PRODUCTION'`:

| M expression | `_page` | Mirrored file |
|---|---|---|
| `MAIN_SRC` | `MAIN` | `../datasources/sql/TRACKER CLIENT PROD MAIN.sql` |
| `SKU_SRC` | `SKU` | `../datasources/sql/TRACKER CLIENT PROD SKU.sql` |
| `CONTAINER_SRC` | `CONTAINER` | `../datasources/sql/TRACKER CLIENT PROD CONTAINER.sql` |

Plus inline `Value.NativeQuery` expressions held directly in `expressions.tmdl`
(`__CLIENTS_MAIN__`, `__CLIENTS_SKU__`, `__CLIENTS_DIM__`, `_ETA_MAX_DATE`) — these do diff in git.

The `TRACKER CLIENT DEMO *` and `TRACKER APP *` files in the same folder are sibling variants (demo
and app) not consumed by this report.

Shares the shipment-tracking domain vocabulary with COMS —
see [`../domains/shipment-tracking.md`](../domains/shipment-tracking.md).

## RLS

Two roles, both `modelPermission: read`:

- **`CompanyID_AUTO`** — `__MAIN__` filtered by `CONTAINSSTRING(CUSTOMDATA(), "|" & _client_id & "|")`;
  param tables filtered to `[_ETA_AUTO] == 1`; `_ROLE` to `[active_auto] == 1`.
- **`CompanyID_MAN`** — same `CUSTOMDATA()` filter on `__MAIN__`; param tables filtered to
  `[_ETA_MAN] == 1`; `_ROLE` to `[active_man] == 1`.

**`CUSTOMDATA()` means this is an embedded / app-owns-data scenario** — the client id list is passed
by the hosting app as a pipe-delimited string, not resolved from `USERPRINCIPALNAME()`. Testing RLS
in Desktop requires the commented-out literal in each role file.

TODO: who sets CUSTOMDATA, and what distinguishes AUTO from MAN (ETA source: automatic feed vs
manual entry?).

## Open questions

- Grain of `__MAIN__`, `__CONTAINER__`, `__SKU__` and the join paths between them.
- Are `Cal test` / `Page 1` disposable scratch pages? They can likely be deleted.
- Refresh schedule and workspace.

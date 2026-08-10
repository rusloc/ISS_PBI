# COMS — Coms report

- **Folder**: `COMS/Coms report.*` (PBIP: `.Report` + `.SemanticModel` + `.pbip`)
- **Format**: PBIR v4.0 (enhanced) + TMDL — editable as code
- **Base theme**: `CY25SU11` (Microsoft base theme, no house theme applied)
- **Scope**: EK and PO views

## Pages

| Page | Visuals | Visibility |
|---|---|---|
| EK view | 35 | visible |
| PO view | 39 | visible |
| EK check | 35 | hidden in view mode (QA copy of EK view) |

4 bookmarks.

## Model

5 tables.

| Table | Role |
|---|---|
| `_EK_VIEW_` | EK fact |
| `_PO_VIEW_` | PO fact |
| `EK_VIEW_PARAM`, `PO_VIEW_PARAM` | field parameters |
| `__FX__` | FX rates / currency conversion |

No RLS roles defined.

## Sources

Two M expressions, both pulling SQL text out of the `public.sql_source` indirection table
(see `../datasources/sources.md`):

- `EK_SQL_SOURCE` — `_report = "COMS"`, `_page = "EK VIEW"`
- `PO_SQL_SOURCE` — `_report = "COMS"`, `_page = "PO VIEW"`

## Open questions

- What EK and PO stand for, and the grain of each view.
- Is `EK check` a permanent QA page or a leftover?
- `__FX__`: rate source, rate date, which measures convert.
- Refresh schedule and workspace.

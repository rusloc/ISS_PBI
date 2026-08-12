# Domain: shipment tracking (PO → freight order → shipment)

> Cross-report business truth. Used by **COMS** (`context/reports/coms.md`) and, in a lighter form,
> by the AVS tracker. Everything here is derived from the two COMS queries in
> `context/datasources/sql/` — line references point at `COMS PO VIEW.sql` unless stated.
>
> **These queries are complex and edits must be surgical.** Read this file *and* the relevant block
> of SQL before touching either one.

## 1. Entity hierarchy

```
Purchase Order (po_no / EKPOREF)          ← what the client ordered
  └─ PO line                              portal."PurchaseOrderLine"
       └─ (m:m link, carries quantity)    portal.purchase_order_on_freight_unit
            └─ Freight Unit / Freight Order (FO)   portal.freight_unit
                 ├─ enrichment                     portal.freight_unit_enrich
                 └─ Shipment (ISS job / serial)    _ship_response (jsonb)
```

- A PO line can be split across **several** freight orders (partial shipments).
- A freight order can carry lines from **several** POs (consolidation).
- The link table `purchase_order_on_freight_unit` is therefore genuinely many-to-many and **carries
  the shipped quantity** (`pofu.quantity`). It is the pivot of the whole domain.

### ⚠ Key relationship — confirmed correct, read before writing any join

`portal.purchase_order_on_freight_unit.purchase_order_id` points at **`PurchaseOrderLine.id`**, not
at a PO header. This is **intentional and correct** (confirmed 2026-08-10) — both queries join it
that way and it must stay that way:

```sql
left join portal."PurchaseOrderLine" pol
    on pol.id = pofu.purchase_order_id
```

The trap is for anyone reading the column name and assuming otherwise. Joining it to anything else,
or assuming `PurchaseOrderLine` is keyed by PO number, silently changes the grain. `po_no` is **not**
unique in `PurchaseOrderLine` — a PO number spans many lines, and line identity is synthesised with
`row_number() over(partition by p.po_no order by p.id)`.

## 2. Quantity flow — how a PO line disappears

The core mechanic of the PO view, stated in the query's own header comment:

- **Ordered quantity** lives on the PO line (`po_qty_ordered`).
- **Shipped/used quantity** is `sum(pofu.quantity)` across that line's freight orders.
- **Remaining = ordered − used.**
- A row is emitted for the remaining balance **only while remaining > 0**. Once shipments fully
  cover the ordered quantity, the remaining row vanishes from the result.
- So quantity "flows" out of the pending block and into the shipped (Enriched) block over time.

### Row types (`_line_type`)

| Value | Meaning |
|---|---|
| `Enriched` | a shipped portion — PO line **plus** freight-order/shipment attributes |
| `Pending` | remaining, not yet shipped (from `pol.status`, default case) |
| `Closed` / `Completed` / `Cancelled` | remaining rows whose PO line status matched `close` / `comple` / `cancel` by regex |

`_master_line` collapses this to `Enriched` vs `Master`: everything that is not an enriched shipment
line is the PO line's own master row.

## 3. Date vocabulary — exact definitions

All shipment dates are pulled out of the `_ship_response` jsonb blob. **The names are not
interchangeable and the fallback chains differ.** Getting these wrong is the single most likely way
to break a COMS number.

### Departure

| Field | Definition |
|---|---|
| `_etd_iss` | `etd_date` — ISS's own estimate, raw |
| `_ptd` | `ptd_date` — planned/promised departure |
| `_etd_wakeo` | `etd_wakeo_date` — Wakeo (external carrier-visibility feed) |
| `_etd` | `coalesce(ptd_date, etd_date)` — **planned first** |
| `_revised_etd` | `coalesce(etd_wakeo_date, etd_date)` |
| `_full_etd` | `coalesce(etd_wakeo_date, etd_date, ptd_date)` — the "best known" ETD |
| `_departure_date` | `loading_date` |
| `_departure_date_actual` (**ATD**) | earliest `status_updates` entry whose status matches `Actual Time of Departure` or `Vessel departure`, **restricted to `comments ~* 'Transshipment Port: No'`** — i.e. transshipment legs are excluded |
| `_departure_date_full` | `coalesce(ATD, loading_date)` |

### Arrival

Exactly mirrored: `_eta_iss` = `eta_date`, `_pta` = `pta_date`, `_eta_wakeo` = `eta_wakeo_date`,
`_eta` = `coalesce(pta, eta)`, `_revised_eta` = `coalesce(wakeo, eta)`,
`_full_eta` = `coalesce(wakeo, eta, pta)`, `_arrival_date` = `arrival_date`,
`_arrival_date_actual` (**ATA**) = same `status_updates` rule with `Actual Time of Arrival` /
`Vessel arrival`, `_arrival_date_full` = `coalesce(ATA, arrival_date)`.

**Rule of thumb**: `_*_full` = best-known value for display and lead-time maths; `_*_actual` = hard
evidence the event happened; the bare `_eta` / `_etd` = the *planned* commitment used for exception
scoring. Never substitute one for another to "fill a gap".

### Other dates

| Field | Definition |
|---|---|
| `_del` | `delivery_date` |
| `_pickup_date` / `_cargo_ho` | `pickup_date` (same source, two names) |
| `_crd_actual` / `_crd_estimated` / `_crd` | Cargo Ready Date, read out of the `custom_dates` / `date_templates` jsonb arrays by name; `_crd` = actual, else estimated |
| `_goods_cleared_origin` / `_goods_cleared_destination` | customs clearance milestones from the same arrays |
| `_pod_date`, `_do_date`, `_do_exp` | proof of delivery, delivery order, D/O expiry |
| `_po_need_by_date` (**NBD**) | the client's required date on the PO line |

**Deliberate asymmetry — do not "fix"**: `_crd_actual` reads `coalesce(date_templates, custom_dates)`
while `_crd_estimated` and `_crd` read `coalesce(custom_dates, date_templates)` — the two arrays are
consulted in opposite order (lines 269–289). Confirmed 2026-08-10 as intentional: left that way as a
hook for further amendments and corrections. Leave it alone unless the change *is* that amendment.

### EDD — Expected Delivery Date

Derived, all with a **+3 day** buffer:

| Field | Definition |
|---|---|
| `_first_edd_po` | `min(coalesce(pta, eta)) over (partition by po_no) + 3 days` — first promise made on the PO |
| `_current_edd_po` | `max(coalesce(ATA-if-in-the-past, eta_wakeo, eta)) over (partition by po_no) + 3 days` |
| `_first_edd_fo` | same as `_first_edd_po` but partitioned by freight unit |
| `_final_expected_del_date` | `_current_edd_po`, but **only** on non-Enriched rows where `_original_po_qty = _shipped` — i.e. shown only once the PO line is fully covered |

## 4. Exception framework (RAG)

Five milestone buckets, each scored independently on every enriched line:

| Bucket | Milestone | Driven by |
|---|---|---|
| `_01_po_aknowledgment_expt` | order acknowledged | `dark green` when `_etd`, `_eta` and `_crd` all exist, else `green` |
| `_02_po_pickup_departure_expt` | booking / departure | SLA `Booking Performance`, measured as `coalesce(_etd_wakeo, _ptd, _etd)` vs `_crd + N days` |
| `_03_po_transit_expt` | transit | SLA `Transit Delay`, **mode-specific**, measured as `_eta_wakeo − coalesce(_pta, _eta)` |
| `_04_po_custom_clear_expt` | customs clearance | `_goods_cleared_destination` / `_del` vs arrival |
| `_05_po_delivery_expt` | delivery | delivery milestone |

Severity scale: **`dark green` → `green` → `yellow` → `red`** (dark green = milestone already
achieved in the past, not merely on time).

### Thresholds are data, not code

Day counts come from `portal.sla_master_coms`, folded into a jsonb map (`_sla_map`) in `_pre_calc`
and read per bucket with `jsonb_path_query_first` keyed on **severity + exception name + mode**:

```sql
jsonb_path_query_first (
     _sla_map
    ,'$[*] ? (@.severity == $_col && @.exception == $_expt && @.mode == $_mode)'
    ,jsonb_build_object ( '_col', 'Red', '_expt', 'Transit Delay', '_mode', initcap ( split_part ( _mode, '_', 1 ) ) )
)
```

**Changing an SLA day-count is a `sla_master_coms` row edit, not a query edit.** The exception
names (`Booking Performance`, `Transit Delay`, …) and severities (`Green`/`Yellow`/`Red`) are the
join keys — renaming one in the table silently yields `null` thresholds and drops the colour.

### Roll-up to the PO line

`_06_expt_status` in the wrapper block aggregates the five buckets across each
`(_po_no_ekporef, _line_no)` partition with `array_agg` and applies precedence:

1. no `Enriched` row exists for the line at all → **red**
2. any bucket red → **red**
3. any bucket yellow **and** outstanding balance > 0 → **yellow**
4. any bucket green **and** balance = 0 → **green**
5. all five buckets dark green **and** balance = 0 → **dark green**

Note the ordering consequence: a line with balance still outstanding can never settle to green.

## 5. Lifecycle status (`_status`)

Evaluated in order — the first match wins, so the sequence *is* the definition:

`Delivered` → `Cancelled` → `In transit` → `Arrived` → `Booked` → `Pending Booking` →
`Pending Quotation Approval` → `Pending Quotation` → `null`

Each condition keys off the presence of a shipment serial (ISS job) plus whether ATA/ATD/`_del` are
in the past. `Cancelled` is detected by `regexp_match(_ship_focus_status, 'cancel', 'i')`.

Statuses `Cancelled`, `Pending`, `Pending Quotation`, `Pending Quotation Approval`,
`Pending Booking`, `Not Due` are **excluded** from the NBD-gap metrics (`_nbd_2_crd`, `_nbd_2_eta`) —
they'd otherwise report a delay against an order that hasn't started.

## 6. Lead time & performance

Segment lead times (days): `_days_order_placement_lt`, `_days_supplier_production_lt`,
`_days_iss_cont_booking_lt`, `_days_transit_lt`, `_days_custom_clearance_lt`, summing to
`_e2e_total_lt`. Committed baseline is `_days_total_comm_perf`.

- Each segment has a matching `*_perf` ratio (`_iss_cont_booking_perf`, `_iss_transit_lead_time_perf`,
  `_supplier_committed_prod_rdy_perf`, `_iss_custom_clear_perf`, `_ontime_order_placement_perf`,
  `_e2e_total_lead_time_perf`). **`< 1` means late.**
- `_health_check` buckets the actual-vs-committed gap: `Healthy` → `Minor` (≤30d) → `Moderate`
  (≤45d) → `Major` (≤60d) → `Severe` (>60d).
  **Guard**: when the four segments plus transit exceed **500 days** the sum is treated as `0` —
  a data-quality escape hatch for absurd dates. Any new lead-time measure must keep that guard.
- `_reason_code` attributes the delay to the first failing segment, in fixed order: PR to PO delay →
  Product Readiness Delay → Booking delay → Trans Shipment delay → Custom Clearance Delay. It is
  `null` when `_health_check` is `Healthy`.

Discrepancy fields `_ptd_discrepancy_days` / `_pta_discrepancy_days` measure actual-vs-planned
(`_departure_date_fallback − _ptd`, `_arrival_date_fallback − _pta`).

## 7. Client scoping

`purchase_order_company` (`poc`) carries the client. `poc.iss_domain` also decides **which shipment
blob is authoritative** — a lateral join picks `shipment_response` when the ordering company's
domain matches `freight_unit_enrich.iss_domain`, and `remote_shipment_response` when it matches
`remote_iss_domain`. The query calls this out as a *critical data join*; changing it changes which
dates every downstream metric sees.

## 8. Reference data

| Table | Use |
|---|---|
| `portal.sla_master_coms` | exception thresholds (see §4) |
| `portal.supplier_lead_time_master` | supplier lead time, joined on `upper(supplier_name)` — a name-match join, fragile by nature |
| `portal.country_average_transit_time` | country transit baseline |
| `portal.ports`, `portal.airports`, `public.analytical__air_sea_ports_codes` | port/airport code → name/country/region |
| `public.analytical__iss_country_mapping_codes` | country → region |
| `public.package_types_coms` | package type names |
| `public.focus__shipments` | operational status feed |

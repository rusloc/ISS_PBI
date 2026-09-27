/*
 * STATUS 2026-09-27: PROD, the live EK VIEW source (sql_source, _page 'EK VIEW').
 * 		Replaces "COMS EK VIEW.sql" (kept for history).
 * 		Changes vs the old file:
 * 			* perf rewrite, same output: OPT (A) - (G), see the header below
 * 			* OPT (Q): p.id tie-break in _sort / _primary_po
 * 			* FIX (1): numeric division in the remaining block's _ontime_order_placement_perf
 * 		Checked 2026-09-27 against the old file (same OPT (Q) + FIX (1) applied): 1,336 rows, 0 differences; 2.6 s (old: ~7 min).
 */

-------------------------------------------------------- SOURCE
/*
 * 
 * level of granularity - latest (by fo_id by CURRENT_PO_PROMISED_DT) and agg all other attrs into one line (cell)
 * SQL structure logic:
 * 	=> main (big long) query to get all PO lines which have ship serial (iss_job) or freight order (structured in 3 waterfall CTEs: pre_calc (main attrs) -> calc (calculated attrs on top of mains from pre_calc) -> main (final CTE)
 *  => main query wrapped in CTEs to further agg attrs (pivot on) freight_order_id (tech field not used in report)
 *  => additional query (NULLs query below the main) to capture all order lines with remaining quantities > 0
 * 
 *  > saved into Git repo: https://github.com/rusloc/ISS_GF
 *	> localm Git init
 */
/*
 * OPTIMIZED VERSION (2026-09-27) of "COMS EK VIEW.sql": same columns, names, order and types.
 * 		Changes are marked "OPT (x)" in the code. No DB settings, no buffer / cache control, no new indexes.
 * 		* OPT (A) the "ecrd" join is removed: it read ShipmentDetails (448 MB) and expanded its JSON, but none of its columns was used
 * 		* OPT (B) costs: aggregated only for the shipments this query can join to, not for every shipment in every domain;
 * 		          their cost lines filtered first (CTE _items) instead of hashing all 6.6M lines
 * 		* OPT (C) DN flag: one lookup per shipment via the "Parent ID" index (lateral, limit 1), instead of grouping all 5.6M attachments;
 * 		          customs (cv) read only for the relevant shipments
 * 		* OPT (D) freight_unit_enrich: each JSON response decompressed and parsed once (CTE _resp); feic is a hash join
 * 		          on (unit_no, domain) with the same rules as the former lateral union all;
 * 		          date arrays read 3 times instead of ~20, status_updates once instead of twice, equipment once instead of 6 times
 * 		* OPT (E) focus__shipments: read once, only the relevant serials (CTE _ship), used by fs and costs
 * 		* OPT (F) shipments tracker matview: read once (not twice), only the relevant serials; mt (pre_calc) and ds (calc) share it
 * 		* OPT (G) port names: one hash join instead of a scan of the ports table per row (the two identical branches merged);
 * 		          country / region names: joins on the same (unique) keys instead of scalar subqueries
 * 		* OPT (Q) _sort / _primary_po: p.id added to the order, so the primary PO line is no longer arbitrary on equal promised dates
 * 		* FIX (1) remaining block, _ontime_order_placement_perf: numeric division as in the enriched block
 * 		          (integer division before: 7 days gave 1 - 1 = 0, now 1 - 1.4 = -0.4, same as the enriched block)
 * 		* the "update sql_source" at the end publishes this file as the live EK VIEW
 * 		* a read-only comparison (DO block) against the original sits at the end of the file
 */




-- 1. assign your code to a session variable
set dev.ek_view_opt = 
$sql$ 




	/*
	 * OPT (D): freight_unit_enrich responses, one row per (enrich row, side):
	 * 			* side 1: shipment_response        + iss_domain
	 * 			* side 2: remote_shipment_response + remote_iss_domain
	 * 		Each JSON is decompressed once here instead of once per "->>" (about 200 per row before).
	 * 		jsonb_to_record returns exactly what "->>" returned (text, NULL when the key is missing);
	 * 		its column names must be the JSON keys, so they carry no "_" prefix.
	 * 		Date arrays: one pass per array order, max() of the only matching element (the former scalar subqueries
	 * 		allowed at most one match, else the query failed):
	 * 			_a_* = coalesce(date_templates, custom_dates)   _b_* = coalesce(custom_dates, date_templates)   _c_* = custom_dates
	 * 		Nothing here casts, so nothing here can fail on enrich rows the report never joins; the ::date casts stay in pre_calc.
	 */
    with _resp as materialized (
				select
					 r._unit_no																							_unit_no
					,r._dom																								_dom
					,r._r -> 'cargo'																					cargo
					,r._r -> 'equipment_details'																		equipment_details
					,r._r -> 'wakeo_updates'																			wakeo_updates
					,j.*
					,da.*
					,db.*
					,dc.*
					,su.*
				from (
							select
								 fe.unit_no																				_unit_no
								,fe.iss_domain																			_dom
								,fe.shipment_response																	_r
							from portal.freight_unit_enrich fe
							union all
							select
								 fe.unit_no																				_unit_no
								,fe.remote_iss_domain																	_dom
								,fe.remote_shipment_response															_r
							from portal.freight_unit_enrich fe
						) r
				left join lateral jsonb_to_record(
							case
								when jsonb_typeof(r._r) = 'object'
									then r._r
								else null
							end) j(
								 arrival_date           text
								,carrier                text
								,chargeable_weight      text
								,delivery_date          text
								,destination_country    text
								,destination_port       text
								,equipment              text
								,eta_date               text
								,eta_preference         text
								,eta_wakeo_date         text
								,etd_date               text
								,etd_preference         text
								,etd_wakeo_date         text
								,gross_volume           text
								,gross_weight           text
								,house_no               text
								,id                     text
								,loading_date           text
								,master_no              text
								,master_spo_no          text
								,operational_status     text
								,origin_country         text
								,origin_port            text
								,package_count          text
								,pickup_date            text
								,pta_date               text
								,pta_date__manual_      text
								,ptd_date               text
								,ptd_date__manual_      text
								,serial_no              text
								,service                text
								,shipment_type          text
								,shipping_terms         text
							)
					on true
				cross join lateral (
							select
								 max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Cargo Ready Date Actual')				_a_crd_actual
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Cargo Ready Date Estimated')				_a_crd_estimated
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'POD Date')								_a_pod_date
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'D/O Date')								_a_do_date
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'D/O Expiry Date')						_a_do_exp
							from jsonb_array_elements(
									case
										when jsonb_typeof(coalesce(r._r -> 'date_templates', r._r -> 'custom_dates')) = 'array'
											then coalesce(r._r -> 'date_templates', r._r -> 'custom_dates')
										else null
									end) e(el)
						) da
				cross join lateral (
							select
								 max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Cargo Ready Date Actual')				_b_crd_actual
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Cargo Ready Date Estimated')				_b_crd_estimated
							from jsonb_array_elements(
									case
										when jsonb_typeof(coalesce(r._r -> 'custom_dates', r._r -> 'date_templates')) = 'array'
											then coalesce(r._r -> 'custom_dates', r._r -> 'date_templates')
										else null
									end) e(el)
						) db
				cross join lateral (
							select
								 max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Cargo Ready Date Estimated')				_c_crd_estimated
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Goods Cleared at Origin Customs')		_c_goods_cleared_origin
								,max(e.el ->> 'value') filter(where e.el ->> 'name' = 'Goods Cleared at Destination Customs')	_c_goods_cleared_destination
							from jsonb_array_elements(
									case
										when jsonb_typeof(r._r -> 'custom_dates') = 'array'
											then r._r -> 'custom_dates'
										else null
									end) e(el)
						) dc
				cross join lateral (
							select
								 min(i.item ->> 'date') filter(where 1=1
										and (i.item ->> 'status' ilike '%Actual Time of Arrival%'
											or i.item ->> 'status' ilike '%Vessel arrival%')
										and i.item ->> 'comments' ~* 'Transshipment Port: No')								_su_arrival_actual
								,min(i.item ->> 'date') filter(where 1=1
										and (i.item ->> 'status' ilike '%Actual Time of Departure%'
											or i.item ->> 'status' ilike '%Vessel departure%')
										and i.item ->> 'comments' ~* 'Transshipment Port: No')								_su_departure_actual
							from jsonb_array_elements(
									case
										when jsonb_typeof(r._r -> 'status_updates') = 'array'
											then r._r -> 'status_updates'
										else null
									end) i(item)
						) su
				where 1=1
					and r._unit_no is not null
					and r._dom is not null
	)
	-- every shipment serial the enriched block can join to (a superset: filtering by it never drops a match)
	,_serials as (
				select distinct
					 r.serial_no																						_serial
				from _resp r
				where 1=1
					and r.serial_no is not null
	)
	-- OPT (E): focus__shipments read once, only the relevant serials; original column names kept for fs and costs
	,_ship as materialized (
				select
					 s."ID"
					,s.iss_domain
					,s."Serial No"
					,s."Line Of Business"
					,s."Master ID"
					,s."Operational Status"
					,s."Service"
				from public.focus__shipments s
				where 1=1
					and s."Serial No" in (select sr._serial from _serials sr)
	)
	-- OPT (B): cost lines of the relevant shipments only (the costs join below can match no other line); read once, filtered by a small hash of _ship
	,_items as materialized (
				select
					 c.*
				from public.focus__costs_revenues_items c
				where 1=1
					and c."Shipment ID" in (select s."ID" from _ship s)
	)
	/*
	 * OPT (F): the tracker matview read once for mt (pre_calc) and ds (calc), both keyed by the shipment serial.
	 * 		mt: max() ignores NULLs, so the former "any of the 4 columns not null" filter gave the same values
	 * 		ds: the former "having max(port_of_discharge) is not null" is the case expression
	 */
	,_tracker as materialized (
				select
					 t.serial_no																						_ship_serial
					,max(t.transshipment_locode)																		transshipment_locode
					,max(t.transshipment_port_name)																		transshipment_port_name
					,max(t.transshipment_days)																			transshipment_days
					,max(t.current_vessel)																				current_vessel
					,max(t.port_of_discharge)																			_port_of_discharge
					,case
						when max(t.port_of_discharge) is not null
							then max(t.port_of_discharge_name)
						else null
					end																									_port_of_discharge_name
				from portal.materialized_view_shipments_tracker t
				where 1=1
					and t.serial_no in (select sr._serial from _serials sr)
				group by 1
	)
	-- OPT (G): one row per port code; ctid order = the row the former "limit 1" picked first
	,_ports as materialized (
				select distinct on (p.code::text)
					 p.code::text																						_code
					,p."name"																							_name
				from public.analytical__air_sea_ports_codes p
				where 1=1
					and p.code is not null
				order by p.code::text, p.ctid
	)
	, pre_calc as (
				select
					p."ship_to_location" 																							_branch_bu
					,p.id																											_pid
					,encode(sha256((
						coalesce(f.id::text,'NA'))::bytea),'hex')																	_fo_id
					,fe.id																											_fe_id
					,coalesce(fe.status,'Pending Booking')																			_status
					,p.supplier_no		 																							_supplier_code
				-- supplier name form the closest promised date of PO
					,p.supplier_name 																								_supplier_name
				-- PO number of the closest by promised date
					,p.po_no 																										_po_no_EKPOREF
				-- agg remarks into one cell as well and description
					,p.po_uom																										_po_uom
					,p.po_remarks 																									_po_remarks
					,p.po_desc 																										_commodity
					,f.serial_no																									_iss_ref
					,f.comment																										_freight_order_comment
					,'https://' || fs.iss_domain || '.logistaas.com/shipments/' || fs."ID" || '/'									_focus_link
					,f.pnl_quotation ->> 'quotedDate'																				_quote_date
					,case 
			-- when "_incoterms_fo" is taken as raw logic -> check below the actual column
						when (case 
								when feic.shipping_terms is not null 
									then feic.shipping_terms
								else fe."shipping_terms" end) not in ('CIF','DAP','DDP')
							then coalesce(f.pnl_quotation ->> 'quoteStatus', 'TBA')
						when (case 
								when feic.shipping_terms is not null 
									then feic.shipping_terms
								else fe."shipping_terms" end) in ('CIF','DAP','DDP')
							then coalesce(f.pnl_quotation ->> 'quoteStatus', 'TBA')
						else 'TBA' end																								_quote_status
					,f.pnl_quotation ->> 'quotedAmountUsd'																			_quote_amount_usd
					,f.pnl_quotation ->> 'quotedDetailsUsd'																			_quote_details_usd
					,f.pnl_quotation ->> 'quoteApprovedDate'																		_quote_approve_date
					,f.pnl_quotation ->> 'approvedDetailsUsd'																		_quote_approve_details_usd
					,f.pnl_quotation ->> 'totalQuoteApprovedAmountUsd'																_quote_approve_amount_usd
					,(f.pnl_quotation ->> 'totalQuoteApprovedAmountUsd')::numeric * 3.673											_quote_approve_amount_aed
					,transshipment_locode																							_tranship_locode
					,transshipment_port_name																						_tranship_port_name
					,transshipment_days																								_tranship_days
					,current_vessel																									_tranship_vessel
					,feic.service																				_mode
					,initcap(split_part((feic.service),'_',1))													_transport_mode
					,initcap(split_part((feic.service),'_',2))													_direction
					,fu.purchase_order_company_id																					_client_id
				    ,poc."company_name"																								_client
					,fs._lob																										_lob
					,case 
							when upper(feic.shipping_terms) in ('DAP','CPT','CIF')
								then 'Direct'
							when fs._ic_shipment = 'IC'
								then 'ISS'
							when fs._ic_shipment = 'agent'
								then 'Agent'
							else 'TBA'
						end																											_routed_by
					,p.inco_term_po																									_incoterms
					,p.req_app_dt																									_pr_appr_date
					,p.po_app_dt																									_po_app_date
					,p.po_date																										_po_creation_date
					,(p.po_app_dt + interval '2 days')::date 																		_po_recd_date 
					,p.current_po_promised_dt																						_po_need_by_date
					,case 
						when feic.shipping_terms is not null 
							then feic.shipping_terms
						else fe."shipping_terms" end																				_incoterms_fo
					,fs."ID"																										_focus_ship_id
					,feic.serial_no																			_shipment_serial_iss_job
					,feic.id																					_response_shipment_id
					,fe.shipment_response ->> 'serial_no'																			_inbound_iss_job_no
					,fe.remote_shipment_response ->> 'serial_no'																	_outbound_iss_job_no
					,feic.house_no																		_hbl_hawb
					,feic.master_no																		_mbl_mawb
					,case 
						when initcap(split_part((feic.service),'_',1)) = 'Air'
							then null
						when feic.shipment_type = 'LCL'
							then null
						else 
							(select 
				    			string_agg((equipment_details.value ->> 'equipment_no')::text, '|'::text)
							from jsonb_array_elements(
								feic.equipment_details) equipment_details(value)) end						_container_no
					,coalesce(feic.origin_port,fe.origin_port, null)											_origin_port_pol
				-- logic from view_freight_unit_enrich
			/*
			 * when iss job is null then join by 'origin_port' 
			 * when iss job is NOT null then use shipment_response ->> 'origin_port'
			 */
					,upper(case
			-- OPT (G): the two former branches (iss job null / not null) ran the same lookup, merged; po = _ports joined on the same coalesce(origin_port ...)
							when split_part(coalesce(feic.service,fe.service),'_',1) in ('sea','air')
								then po._name
							when fe.service = 'land_inbound'::text
								then 'Jebel Ali'::character varying
							else null end)					 																			_origin_port_name
				-- country need to split between AIRPORT & PORT tables
			-- OPT (G): coc / cro / cod / crd = joins on the same keys (one row per code), were scalar subqueries per row
					,coc.country_name																								_origin_country
					,coalesce(feic.origin_country,fe.origin_country,null)										_origin_country_code
					,cro."region"																									_origin_region_org_reg
					,coalesce(feic.destination_port,fe.destination_port,null)									_destination_port_code_dest
					,upper(case
			-- OPT (G): merged branches as above; pd = _ports joined on the same coalesce(destination_port ...)
							when split_part(coalesce(feic.service,fe.service),'_',1) in ('sea','air')
								then pd._name
							when fe.service = 'land_inbound'::text
								then 'Jebel Ali'::character varying
							else null end)					 																			_destination_port_name_dest
					,coalesce(feic.destination_country, fe.destination_country,null)							_destination_country_code_dest
					,cod.country_name																								_destination_country_dest
					,crd."region"																									_destination_region_reg
					,case 
						when initcap(split_part((feic.service),'_',1)) = 'Air'
							then feic.shipment_type
						when feic.shipment_type = 'LCL'
							then 'LCL'
						else 
							replace(
								replace(
									replace( (feic.equipment),'[','')
									,']','')
								,', ',' + ') end																					_eqpt_type
				-- count all 20ft cointainers Stnd dry, Dry bulk etc
					,case
						when initcap(split_part((feic.service),'_',1)) = 'Air'
							then null
						when feic.shipment_type = 'LCL'
							then null

			-- OPT (D): eq = equipment list parsed once per row (was 6 times), under the same Air / LCL guard
						else eq._s20 end																							_20_ft
				-- count all 40ft cointainers Stnd dry, Dry bulk etc
					,case
						when initcap(split_part((feic.service),'_',1)) = 'Air'
							then null
						when feic.shipment_type = 'LCL'
							then null

						else eq._s40 end																							_40_ft
				-- sum 20ft + 40ft
					,case
						when initcap(split_part((feic.service),'_',1)) = 'Air'
							then null
						when feic.shipment_type = 'LCL'
							then null

						else coalesce(eq._s20,0) + coalesce(eq._s40,0) end														_count_of_cont
				-- TEUs = 40ft x2 + 20ft x1 (multiplication)
					,case
						when initcap(split_part((feic.service),'_',1)) = 'Air'
							then null
						when feic.shipment_type = 'LCL'
							then null

						else coalesce(eq._s20,0) * 1 + coalesce(eq._s40,0) * 2 end												_teus
					,car._name																										_carrier
					,case
						when (feic.arrival_date)::date > now()::date
							then null
						else (feic.arrival_date)::date end												_arrival_date
			-- OPT (D): su = status_updates read once for both actual dates
					,(feic._su_arrival_actual)::date																				_arrival_date_actual
					,(feic.arrival_date)::date															_arrival_date_full
					,case
						when (feic.loading_date)::date > now()::date 
							then null
						else (feic.loading_date)::date end												_departure_date
					,(feic._su_departure_actual)::date																				_departure_date_actual
					,(feic.loading_date)::date															_departure_date_full
			-- OPT (D): date arrays read once per order in _resp (_a_ = date_templates first, _b_ = custom_dates first, _c_ = custom_dates only)
					,coalesce(feic._a_crd_actual::date
								,fe.cargo_ready_date_actual::date)																	_crd_actual
				    ,coalesce(feic._b_crd_estimated::date
								,fe.cargo_ready_date_estimates::date)																_crd_estimated
					,coalesce(
						feic._b_crd_actual::date
						,fe.cargo_ready_date_actual::date
						,feic._b_crd_estimated::date
						,fe.cargo_ready_date_estimates::date)																		_crd
					,feic._c_crd_estimated::date																					_est_cargo_ready_date
				   	,feic._c_goods_cleared_origin::date																				_goods_cleared_origin
				   	,feic._c_goods_cleared_destination::date																		_goods_cleared_destination
				   	,(feic.pickup_date)::date															_pickup_date
					,case 
						when (feic.etd_preference) = 'etd_tracking'
						and upper(split_part(coalesce(feic.service,fe.service),'_',1)) = 'AIR'
							then (jsonb_path_query_first(
							          fe.shipment_response
							         ,'$.wakeo_updates[*].locations[*].milestones[*]
							               ? (@.type like_regex "\\(RCS\\)")'
							      ) ->> 'actual_time')::date 
						when (feic.etd_preference) = 'etd_tracking'
						and upper(split_part(coalesce(feic.service,fe.service),'_',1)) = 'SEA'
							then (jsonb_path_query_first(
							          fe.shipment_response
							         ,'$.wakeo_updates[*].locations[*].milestones[*]
							               ? (@.type like_regex "gate\\s*in.*departure" flag "i")'
							      ) ->> 'actual_time')::date
						when (feic.etd_preference) = 'etd_tracking'
						and upper(split_part(coalesce(feic.service,fe.service),'_',1)) <> 'SEA'
						and upper(split_part(coalesce(feic.service,fe.service),'_',1)) <> 'AIR'
							then (feic.pickup_date)::date
						else null
					end																												_cargo_ho
		-- eta date group
					,(feic.eta_date)::date																_eta_iss
					,case 
						when (feic.eta_preference) = 'eta_tracking'
						and (feic.eta_wakeo_date)::date is null
						and (feic.eta_date)::date is not null
							then 'Manual'
						when (feic.eta_preference) = 'eta_tracking'
						and (feic.eta_date)::date is not null
						and (feic.wakeo_updates -> 0 is null)::int = 0
							then 'Tracking'
						when (feic.eta_preference) = 'eta_tracking'
						and (feic.eta_date)::date is not null
						and (feic.wakeo_updates -> 0 is null)::int = 1
							then 'Tracking (IC)'
						when (feic.eta_preference) = 'eta_standard'
						and (feic.eta_date)::date is not null
							then 'Manual'
						else null end 																								_eta_source
					,coalesce(
						coalesce(
							(feic.pta_date__manual_)::date
							,(feic.pta_date)::date)
						,(feic.eta_date)::date)															_eta
					,(feic.eta_wakeo_date)::date															_eta_wakeo
					,coalesce(
						(feic.eta_date)::date
						,coalesce(
						(feic.pta_date__manual_)::date
						,(feic.pta_date)::date)::date)													_full_eta
		-- etd date group
					,(feic.etd_date)::date																_etd_iss
					,case 
						when (feic.etd_preference) = 'etd_tracking'
						and (feic.etd_wakeo_date)::date is null
						and (feic.etd_date)::date is not null
							then 'Manual'
						when (feic.etd_preference) = 'etd_tracking'
						and (feic.etd_date)::date is not null
						and (feic.wakeo_updates -> 0 is null)::int = 0
							then 'Tracking'
						when (feic.etd_preference) = 'etd_tracking'
						and (feic.etd_date)::date is not null
						and (feic.wakeo_updates -> 0 is null)::int = 1
							then 'Tracking (IC)'
						when (feic.etd_preference) = 'etd_standard'
						and (feic.etd_date)::date is not null
							then 'Manual'
						else null end 																								_etd_source
					,coalesce(
						coalesce(
							(feic.ptd_date__manual_)::date
							,(feic.ptd_date)::date)
						,(feic.etd_date)::date)															_etd
					,(feic.etd_wakeo_date)::date															_etd_wakeo
					,coalesce(
						(feic.etd_date)::date
						,coalesce(
							(feic.ptd_date__manual_)::date
							,(feic.ptd_date)::date)::date)												_full_etd
					,coalesce(
						(feic.pta_date__manual_)::date
						,(feic.pta_date)::date
						,fe.pta_date::date)																							_pta
					,coalesce(
						(feic.ptd_date__manual_)::date
						,(feic.ptd_date)::date
						,fe.ptd_date::date) 																						_ptd
					,feic._a_pod_date::date																							_pod_date
					,feic._a_do_date::date																							_do_date
					,feic._a_do_exp::date																							_do_exp
				    ,fe.pr_number																									_pr_number
				    ,fe.pr_date																										_pr_date
				    ,case 
				    		when fe.pr_number is null
				    			then 'Pending'
				    		else 'Logged'
				    end																												_req_status	
				  	,(feic.master_spo_no)::text																	_spo_number
				    ,case 
				    		when fe.spo_number is null 
				    			then 'Pending'
				    		else 'Received'
				    end																												_po_status
				    ,fe.grn_no																										_grn_no
				    ,case 
				    		when fe.grn_no is not null then 'Complete'
				    		else 'Pending'
				    end																												_grn_status
				    ,fe.addl_po																										_addl_po
				    ,fe.addl_po_grn_number																							_addl_po_grn
				    ,case
				    		when (feic.delivery_date)::date is null
				    			then null 
				    		else coalesce(
				    				(feic.eta_date)::date
				    				- coalesce(
			    						coalesce(
											(feic.pta_date__manual_)::date
											,(feic.pta_date)::date))::date, 0)
				    end																												_days_delayed_eta
				    ,case
				    		when (feic.delivery_date)::date is null
				    			then null 
				    		else coalesce(
				    				(feic.etd_date)::date 
				    				- coalesce(
										(feic.ptd_date__manual_)::date
										,(feic.ptd_date)::date)::date,0)
				    end																												_days_delayed_etd
--				    ,coalesce(
--						(feic.eta_wakeo_date)::date
--						,(feic.eta_date)::date
--						,(feic.pta_date)::date)
--				    	- coalesce(
--						(feic.etd_wakeo_date)::date
--						,(feic.etd_date)::date
--						,(feic.ptd_date)::date)															_etd_2_eta
--				    	,(feic.delivery_date)::date
--				    	- coalesce(
--						(feic.eta_wakeo_date)::date
--						,(feic.eta_date)::date
--						,(feic.pta_date)::date)															_eta_2_del
    					,p.current_po_promised_dt - (feic.delivery_date)::date							_nbd_2_del
				    	,case 
				    		when (feic.delivery_date)::date > now()::date then null
				    		else (feic.delivery_date)::date end											_del
					,_aux_charge_type
					,coalesce(case 
						when p.req_app_dt is null or p.po_app_dt is null
							then null 
						else p.po_app_dt - p.req_app_dt						
					end,0)																											_days_order_placement_lt
			-- _crd is null or _del is null => null
					,case
						when coalesce(
								feic._a_crd_actual::date
								,feic._a_crd_estimated::date) is null
									or p.po_app_dt is null
								then 0
				-- else => _crd - _po_app_date
						else coalesce(
								feic._a_crd_actual::date
								,feic._a_crd_estimated::date) - p.po_app_dt
								end																									_days_supplier_production_lt
			-- full_eta & delivery__date NOT NULL
					,case 
						when 
							case 
								when (feic.delivery_date)::date > now()::date then null
								else (feic.delivery_date)::date end is not null
						and 
							case
								when (feic.arrival_date)::date > now()::date	then null
								else (feic.arrival_date)::date end is not null
							then 
								case 
									when (feic.delivery_date)::date > now()::date then null
									else (feic.delivery_date)::date end 
								- case
									when (feic.arrival_date)::date > now()::date	then null
									else (feic.arrival_date)::date end
						else 0 end																									_days_custom_clearance_lt
					,case
				-- (Full Departure Date (as _departure_date_fallback in CALC CTE) > full_etd) is not null
					-- _ptd
						when coalesce(
								(feic.ptd_date__manual_)::date
								,(feic.ptd_date)::date) is not null
				-- _ptd - _crd
						then coalesce(
								(feic.ptd_date__manual_)::date
								,(feic.ptd_date)::date)
								 - coalesce(
										feic._a_crd_actual::date
										,feic._a_crd_estimated::date)
						else 0 end																									_days_iss_cont_booking_lt
					,case 
						when 
							coalesce(
								(feic.arrival_date)::date
										,(feic.eta_date)::date
										,coalesce(
										(feic.pta_date__manual_)::date
										,(feic.pta_date)::date)::date) is not null
							then 
								coalesce(
									(feic.arrival_date)::date
										,(feic.eta_date)::date
										,coalesce(
											(feic.pta_date__manual_)::date
											,(feic.pta_date)::date)::date)
													- coalesce(
														(feic.loading_date)::date
														,(feic.etd_date)::date
														,coalesce(
															(feic.ptd_date__manual_)::date
															,(feic.ptd_date)::date)::date)
						else null
					end																												_days_transit_lt
					,case
						when (feic.delivery_date)::date is null
						or p.req_app_dt is null
							then null 
						else (feic.delivery_date)::date - p.req_app_dt
					end																												_e2e_total_lt
					,fe.delivery_location																							_delivery_location
					,q._inner_qty																									_inner_qty
					,feic.gross_volume																			_cbm
					,feic.gross_weight																			_gw
					,feic.chargeable_weight																	_chw
					,feic.package_count																		_qnty
					,(select string_agg(distinct i ->> 'package_type', ', ')
  						from jsonb_array_elements(feic.cargo) i)												_pack_type
  					,fe.shipment_remarks																							_ship_remarks_updates
  					,fe.billing_notes																								_ship_billing_remarks
  					,case 
  						when fe.pre_alert_sent_at is null then 'No'
  						else 'Yes' end 																								_pre_alert	
  		-- OPT (C): agi = the former "att" test (an uploaded AGI attachment with Parent ID = shipment ID), looked up per shipment
  					,case
  						when agi._has_agi is not null and fs."ID" is not null
  							then 'Yes'
  						when agi._has_agi is null and fs."ID" is not null
  							then 'No'
  						else null end																								_dn
					,case 
  						when p.po_app_dt is not null
  						and (p.po_app_dt - p.req_app_dt) <= 5
  							then 1
  						when p.po_app_dt is not null and (p.po_app_dt - p.req_app_dt) > 5
  							then 1 - ABS((p.po_app_dt - p.req_app_dt)::numeric / 5)
  						else 0
  					end																												_ontime_order_placement_perf
  					,case 
  						when  (feic.origin_country) is null
  							or (feic.origin_port) is null 
  							or (feic.origin_port) = ''
  							or regexp_match(feic.operational_status, 'cancel','i') is not null
  								then 0
  						else slt.avg_lead_time + ctt.average_transit_time + 7 + 3 + 5
  					end																												_days_total_comm_perf
  				  	,fe.ancillary_charge_form_no																					_aux_charge_form_no
  				  	,initcap(slt.category)																							_slt_category
  					,slt.avg_lead_time																								_supplier_lead_time
  					,ctt.average_transit_time																						_country_lead_time
  			-- LOCAL costs
  					,costs._org_charges_local																						_org_charges_aed
  					,costs._dest_charges_local																						_dest_charges_aed
  					,costs._frt_charges_local																						_frt_charges_aed
  					,costs._aux_charges_local																						_aux_charges_aed
  			-- USD costs
  					,costs._org_charges_usd																							_org_charges_usd
  					,costs._dest_charges_usd																						_dest_charges_usd
  					,costs._frt_charges_usd																							_frt_charges_usd
  					,costs._aux_charges_usd																							_aux_charges_usd
  			-- other costs related data
  				    ,costs._issued_invoices																							_invoice_no
				    ,costs._issue_date																								_invoice_issue_date
				    ,costs._addl_issued_invoices																					_addl_issued_invoices
				    ,costs._addl_issue_date																							_addl_invoice_issue_date
				    ,cv._amount_native																								_customs_invoice_aed
					,cv._amount_usd																									_customs_invoice_usd
					,cv._currency_native																							_customs_declared_currency
				    ,case 
				    		when costs._issued_invoices is not null 
				    			then 'Billed'
				    		else 'Pending'
				    end 																											_billing_status
  					,costs._ship_focus_status																						_ship_focus_status
  		-- sort attr used to select primary POs and secondary POs and place them in one line
		-- OPT (Q): p.id breaks ties between PO lines with the same promised date (the primary PO line was arbitrary before)
					,row_number() over(partition by f.id order by p.current_po_promised_dt, p.id)									_sort
					,first_value(p.po_no) over(partition by f.id order by p.current_po_promised_dt, p.id) 							_primary_po
				from portal."PurchaseOrderLine" p
		-- many to many rel
				inner join (
							select 
								p.purchase_order_id
								,p.freight_unit_id
								,p.purchase_order_company_id
							from portal.purchase_order_on_freight_unit p
							group by 
								p.purchase_order_id
								,p.freight_unit_id
								,p.purchase_order_company_id
							) fu 
					on fu.purchase_order_id = p.id
				inner join portal.purchase_order_company poc 
					on poc.id = fu.purchase_order_company_id
			-- inner join with FU to keep only order which have FO lines
				inner join portal.freight_unit f
					on f.id = fu.freight_unit_id
--				    and f.shipment_serial_no is not null
				    and f.deleted_at is null
			-- need left join to show FO lines with no shipment serial
				left join portal.freight_unit_enrich fe 
					on fe.unit_no = f.unit_no
		/*
		 * critical data join: if [ordering comp iss_dom] = freight_unit_enrich.iss_Dom => use [shipment_response] 
		 * 					   if [ordering comp iss_dom] = freight_unit_enrich.remote_iss_Dom => ise [remote_shipment_response]
		 */
		/*
		 * OPT (D): feic = _resp rows of this freight unit whose side domain = ordering company domain
		 * 		(= the former lateral union all: shipment_response when iss_domain matches, remote_shipment_response when remote_iss_domain matches)
		 */
				left join _resp feic
					on feic._unit_no = f.unit_no
					and feic._dom = poc.iss_domain
		-- OPT (G): port / country / region lookups for the origin and destination columns
				left join _ports po
					on po._code = coalesce(feic.origin_port,fe.origin_port, null)
				left join _ports pd
					on pd._code = coalesce(feic.destination_port, fe.destination_port,null)
				left join public.analytical__country_codes coc
					on coc.code_2 = coalesce(feic.origin_country,fe.origin_country,null)
				left join public.analytical_country_region cro
					on cro.alpha_2_code = coalesce(feic.origin_country,fe.origin_country,null)
				left join public.analytical__country_codes cod
					on cod.code_2 = coalesce(feic.destination_country,fe.destination_country,null)
				left join public.analytical_country_region crd
					on crd.alpha_2_code = coalesce(feic.destination_country,fe.destination_country,null)
		-- OPT (D): equipment list parsed once per row; the ::jsonb cast runs under the same Air / LCL guard as the former subqueries
				left join lateral (
							select
								 sum(substring(i.item from '^\d+')::int) filter(where i.item like '% x 20 ft%')				_s20
								,sum(substring(i.item from '^\d+')::int) filter(where i.item like '% x 40 ft%')				_s40
							from jsonb_array_elements_text(
									case
										when initcap(split_part((feic.service),'_',1)) = 'Air'
											then null
										when feic.shipment_type = 'LCL'
											then null
										else (feic.equipment)::jsonb
									end) i(item)
						) eq
					on true
				left join (
							select
								fs."ID"
								,fs.iss_domain
								,fs."Serial No"
								,fs."Line Of Business"											_lob
								,case
									when length(fms."Agent Accounting ID") <= 4 then 'IC'
									else 'agent' end											_ic_shipment
						-- OPT (E): _ship = focus__shipments of the relevant serials only
							from _ship fs
							left join focus__master_shipments fms
								on fms."ID" = fs."Master ID"
						) fs
					on fs."Serial No" = feic.serial_no
				left join (
						-- SEA carriers
								select 
									distinct on (coalesce(ap._code, s."SCAC Code"))
									s."Carrier Name" 									_name
									,coalesce(ap._code, s."SCAC Code")					_code
								from public.analytical__scac_codes s
								left join (
											select 
												car."name"											_name
												,unnest(car."allScacs") 							_code
											from portal."CarrierShipping" car
											)  ap 
									on ap._code = s."SCAC Code"
						-- AIR scarriers
							union all  
								select 
									a.name												_name 
									,a.code 											_code
								from public.analytical__airlines a
							) car 
					on car._code = feic.carrier
			/*
			 * OPT (C): the former "att" join grouped all 5.6M attachments; now one lookup per shipment via the "Parent ID" index.
			 * 		limit 1: at most one row per outer row, so the row count does not change (att had one row per shipment too).
			 * 		lateral + limit keeps it a per-row index lookup (an exists() was planned as one full scan of the table).
			 */
				left join lateral (
							select
								 1																							_has_agi
							from public.focus__attachments a
							where 1=1
								and a."Parent ID" = fs."ID"
								and a."Label" = 'AGI'
								and a."Uploaded"::int = 1
							limit 1
						) agi
					on true
			-- customs declaration data
				left join (
								select 
									cv."Shipment ID" 														_ship_id
									,cv."Bill Of Entry Date"::date 	
									,cv."Declaration Currency"												_currency_native 
									,cv."Declaration Type" 													_type
									,cv."Declaration Value" 												_amount_native
									,case 
										when cv."Declaration Currency" = 'AED'
											then cv."Declaration Value"
										else cv."Declaration Value" * coalesce(er."From", er."To")
									end																		_amount_aed
									,case 
										when cv."Declaration Currency" = 'AED'
											then cv."Declaration Value"
										else cv."Declaration Value" * coalesce(er."From", er."To") *3.6
									end																		_amount_usd
								from public.focus__customs cv 
								left join public.focus__exchange_rates er 
									on er."Cost Exchange Rate" = cv."Declaration Currency" 
									and er."Created At"::date = '2025-09-30'
									and er."Cost Exchange Rate" <> 'AED'
									and er."Selling Exchange Rate" = 'AED'
								where 1=1
									and cv."Declaration Value" is not null
--									and cv."Bill Of Entry Date" is not null
									and cv."Declaration Currency" is not null

								-- OPT (C): only the shipments this query can join to (fs comes from _ship)
									and cv."Shipment ID" in (select s."ID" from _ship s)
							) cv
					on cv._ship_id = fs."ID"
			/*
			 * Costs in LOCAL columns show AED (respecing domain); USD column show USD (converted from LOCAL currency)
			 */
				left join (
							select 
								t.*
								,_org_charges_local * u.to_usd_rate																						_org_charges_usd
								,_dest_charges_local * u.to_usd_rate																						_dest_charges_usd
								,_frt_charges_local * u.to_usd_rate																						_frt_charges_usd
								,_aux_charges_local * u.to_usd_rate																						_aux_charges_usd
								,count(*) over(partition by _ship_serial)
							from (
										select 
											s."ID" 																										_ship_id
											,s."Serial No" 																								_ship_serial
											,s."Operational Status"																						_ship_focus_status
											,c.iss_domain																								_iss_dom
											,ac.currency																									_currency
									-- ORIGIN CHARGE
											,sum(case 
												when oc.category = 'Origin Charge'
													then c."Selling Rate" * c."Selling Quantity" 
														* coalesce(nullif("Selling Local Exchange Rate",1), a.to_aed_rate)
												else 0 end )																								_org_charges_local	
									-- DEST CHARGES	
											,sum(case 
												when oc.category = 'Destination Charge'
													then c."Selling Rate" * c."Selling Quantity" 
														* coalesce(nullif("Selling Local Exchange Rate",1), a.to_aed_rate)
												else 0 end )																								_dest_charges_local	
									-- FREIGHT CHARGES	
											,sum(case 
												when oc.category = 'Freight Charge'
													then c."Selling Rate" * c."Selling Quantity" 
														* coalesce(nullif("Selling Local Exchange Rate",1), a.to_aed_rate)
												else 0 end )																								_frt_charges_local
									-- AUX CHARGES	
											,sum(case 
												when oc.category = 'Ancillary Charge'
													then c."Selling Rate" * c."Selling Quantity" 
														* coalesce(nullif("Selling Local Exchange Rate",1), a.to_aed_rate)
												else 0 end )																								_aux_charges_local
									-- other info
											,string_agg(
													case 
														when oc.category = 'Ancillary Charge' 
															then c."Extra Info"
														else null
													end, ' | ') 																							_aux_charge_type	
										-- xl table mapping name: Invoice #
											,string_agg(distinct
													case
														when oc.category <> 'Ancillary Charge' then inv."Serial No"
														else null
													end, ' | ')																							_issued_invoices
										-- xl table mapping name: Billing month
											,string_agg(distinct
													case 
														when oc.category <> 'Ancillary Charge'
															then to_char(inv."Issue Date"::date, 'MON-yyyy')
														else null
													end, ' | ')																							_issue_date
											,string_agg(
													case
														when oc.category = 'Ancillary Charge' then inv."Serial No"
														else null
													end, ' | ')																							_addl_issued_invoices
											,string_agg(
													case 
														when oc.category = 'Ancillary Charge'
															then to_char(inv."Issue Date"::date, 'MON-yyyy')
														else null
													end, ' | ')																							_addl_issue_date
									-- OPT (B): _ship holds only the shipments of the relevant serials, so only those are aggregated;
									-- _items holds only their cost lines (no hash of all 6.6M lines)
										from _ship s
										left join _items c
											on c."Shipment ID" = s."ID" 
											and c.iss_domain = s.iss_domain 
										left join public.analytical__currencies ac
											on ac.iss_domain = s.iss_domain
									/*
									 * join two tables: to_aed & to_usd
									 * local cur column -> convert local to AED
									 * USD cur column -> convert local to USD
									 */
										left join public._fx_rates_aed a
											on a.currency_code = c."Currency"
											and a.rate_date = '2026-05-07'
									-- attr for CHarge types
										left join portal.charge_service_mapping oc
											on upper(trim(oc.service)) = upper(trim(s."Service")) 
											and upper(trim(oc.charge)) = upper(trim(c."Charge Name"))
											and oc.status = 'Active'
										left join public.focus__issued_invoices inv 
											on inv."ID" = (replace(split_part(c."Customer Invoice ID",',',1), '.0',''))::int 
											and inv.iss_domain = c.iss_domain
											and inv."Voided"::int = 0
										where 1=1
											and s."Serial No" is not null
										group by 
											1,2,3,4,5
											) t
								left join public._fx_rates_usd u 
									on u.currency_code = t._currency
									and u.rate_date = '2026-05-07'
							) costs 
		-- conditional join to join on remote_shipment_serail OR main_shipments_serial
					on costs._ship_serial = feic.serial_no
		-- inner quantity		
				left join (
					-- join formatted _inner_qty metric
								select 
									freight_unit_id
									,case 
										when _rows > 1 
											then _multi
										else _single
									end																			_inner_qty
							--- if only one line exists -> show only number; else show PO ID - [number]
								from (
												select 
													pofu.freight_unit_id
													,string_agg(
														pol.po_no || ' - ' || pol.item_code || ' - ' || pofu.quantity
														,' | ')													_multi
													,(sum(pofu.quantity))::text									_single
													,count(*)													_rows
												from portal.purchase_order_on_freight_unit pofu
												left join portal."PurchaseOrderLine" pol 
													on pofu.purchase_order_id = pol.id 
												where 1=1
	--												and pofu.freight_unit_id = 466
												group by 1
									) t
								) q 
					on q.freight_unit_id = fu.freight_unit_id
		-- OPT (A): the former "ecrd" join is removed: none of its columns was used (and one row per serial, so no row count change)
				left join portal.supplier_lead_time_master slt 
					on slt.supplier_id = p.supplier_no
				left join portal.country_average_transit_time ctt
					on ctt.code = feic.origin_country
		-- OPT (F): transshipment columns from _tracker (matview read once for mt and ds, relevant serials only)
				left join _tracker mt
					on mt._ship_serial = feic.serial_no
				where 1=1
--					and f.shipment_serial_no	= 'SHPDXBSI25000180'
--					and poc."company_name" = 'EMIRATES LOGISTICS LLC'
--					and fe.id = 94
--					and f.serial_no	= 'EMA000135'
			)
, calc as (
	select 
		y.*
		,case 
			when _eta_source = 'Tracking' or _eta_source = 'Tracking (IC)'
				then (select min("createdAt"::date)
						from portal."ContainerChanges" c 
						where 1=1
							and c."shipmentId" = y._focus_ship_id
							and c."effectiveEta"::date = y._eta_iss)
			when _eta_source = 'Manual'
				then (select min("createdAt"::date)
						from portal."ShipmentDates" c 
						where 1=1
							and c."shipmentId" = y._focus_ship_id
							and c."etaDate"::date = y._eta_iss)  
			else null end 																							_eta_last_change
		,case 
			when _etd_source = 'Tracking' or _etd_source = 'Tracking (IC)'
				then (select min("createdAt"::date)
						from portal."ContainerChanges" c 
						where 1=1
							and c."shipmentId" = y._focus_ship_id
							and c."effectiveEtd"::date = y._etd_iss)
			when _etd_source = 'Manual'
				then (select min("createdAt"::date)
						from portal."ShipmentDates" c 
						where 1=1
							and c."shipmentId" = y._focus_ship_id
							and c."etdDate"::date = y._etd_iss)  
			else null end 																							_etd_last_change
		,now()::date - _ptd																							_ptd_2_now
		,now()::date - _pickup_date																					_pickup_2_now
		,case 
				when  _departure_date is not null and _ptd is not null
					then  _departure_date - _ptd
				when _departure_date is not null and _etd_iss is not null
					then _departure_date - _etd_iss
				when _ptd is not null and _etd_iss is null 
					then _etd_iss - _ptd
				else null end 																						_dep_discrepancy_days
			,case 
				when  _arrival_date is not null and _pta is not null
					then  _arrival_date - _pta
				when _arrival_date is not null and _eta_iss is not null
					then _arrival_date - _eta_iss
				when _pta is not null and _eta_iss is null 
					then _eta_iss - _pta
				else null end 																						_arr_discrepancy_days
		,case 
			when coalesce(_departure_date_full, _full_etd) is not null
				and coalesce(_arrival_date_full, _full_eta) is not null
					then coalesce(_arrival_date_full, _full_eta) - coalesce(_departure_date_full, _full_etd)
			else null end 																							_etd_2_eta
	    ,case 
			when coalesce(_arrival_date_full, _full_eta) is not null
				then _del 
						- coalesce(_arrival_date_full, _full_eta)
			else null end																							_eta_2_del
		,case 
			when (coalesce(_days_order_placement_lt, 0)
	            + coalesce(_days_supplier_production_lt, 0)
	            + coalesce(_days_custom_clearance_lt, 0)
	            + coalesce(_days_iss_cont_booking_lt, 0)
	            + coalesce(_days_transit_lt, 0)) > 500
	                then 0
	        else (coalesce(_days_order_placement_lt, 0)
                + coalesce(_days_supplier_production_lt, 0)
                + coalesce(_days_custom_clearance_lt, 0)
                + coalesce(_days_iss_cont_booking_lt, 0))
		end																											_actual_lead
		,case 
			when _supplier_lead_time is null
				then null
		    when ((case 
		            when (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0)
		                + coalesce(_days_transit_lt,             0)) > 500
		                then 0
		            else (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0))
		          end) - _days_total_comm_perf) <= 15 
					then 'Healthy'
		    when ((case 
		            when (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0)
		                + coalesce(_days_transit_lt,             0)) > 500
		                then 0
		            else (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0))
		          end) - _days_total_comm_perf) <= 30 
					then 'Minor'
		    when ((case 
		            when (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0)
		                + coalesce(_days_transit_lt,             0)) > 500
		                then 0
		            else (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0))
		          end) - _days_total_comm_perf) <= 45 
					then 'Moderate'
		    when ((case 
		            when (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0)
		                + coalesce(_days_transit_lt,             0)) > 500
		                then 0
		            else (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0))
		          end) - _days_total_comm_perf) <= 60 
					then 'Major'
		    when ((case 
		            when (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0)
		                + coalesce(_days_transit_lt,             0)) > 500
		                then 0
		            else (coalesce(_days_order_placement_lt,     0)
		                + coalesce(_days_supplier_production_lt, 0)
		                + coalesce(_days_custom_clearance_lt,    0)
		                + coalesce(_days_iss_cont_booking_lt,    0))
		          end) - _days_total_comm_perf) > 60
		          	then 'Severe'
			when _supplier_lead_time = 0
				or _del is null
				or _crd_actual is null
				or _full_eta is null
				or _full_etd is null
				or _pr_appr_date is null
				or (_days_total_comm_perf is null or _days_total_comm_perf = 0)
					then null
		    else null end																													_health_check
    		,case 
				when _e2e_total_lt > 0 and _days_total_comm_perf > 0
					then 1 - abs((_e2e_total_lt - _days_total_comm_perf)::numeric
		  			-- divide by {_days_total_comm_perf}
		  					/ coalesce(nullif(_days_total_comm_perf,0),1))
		  		else 0
			end																												_e2e_total_lead_time_perf
		,case 
			when _ptd is not null
			and y._days_iss_cont_booking_lt > 0
				then
					case
						when (_ptd - y._crd) <= 7
							then 1
						else 1 - abs(_ptd - y._crd)::numeric / 7
					end
			else 0 end																										_iss_cont_booking_perf
		,case 
			when _po_app_date is null or _crd is null
		      	then 0
		    when (_crd - _po_app_date) <= _supplier_lead_time
		      	then 1
		    when (_crd - _po_app_date) > _supplier_lead_time
		      	then 1 - abs(_crd - _po_app_date)::numeric / coalesce(nullif(_supplier_lead_time,0),1)
		end																													_supplier_committed_prod_rdy_perf
		,case 
			when coalesce(_arrival_date_full,_full_eta) is null 
			or coalesce(_departure_date_full, _full_etd) is null 
			or _origin_country is null
			 	then 0
			when (coalesce(_arrival_date_full,_full_eta) - coalesce(_departure_date_full, _full_etd)) <= _country_lead_time
				then 1
			when (coalesce(_arrival_date_full,_full_eta) - coalesce(_departure_date_full, _full_etd)) > _country_lead_time
				 then 1 - abs((coalesce(_arrival_date_full,_full_eta) 
				 			- coalesce(_departure_date_full, _full_etd))::numeric / coalesce(nullif(_country_lead_time,0),1))
			else 0
		end																													_iss_transit_lead_time_perf
		,case 
			when _del is null or _arrival_date is null 
				then 0
			when (_del - _arrival_date) <= 3
				then 1
			when (_del - _arrival_date) > 3
				then 1 - abs((_del - _arrival_date)::numeric / 3)
			else null 					
		end																													_iss_custom_clear_perf
	    ,case
	    		when coalesce(_arrival_date_full,_full_eta) is null
	    			then null
	    		else coalesce(_arrival_date_full,_full_eta) - _po_need_by_date
	    end																													_rdd_eta
	    ,case 
	-- if revised ETD <> null => REV ETD - CRD actual 
	    		when coalesce(_departure_date_full, _full_etd) is not null
	    			then coalesce(_departure_date_full, _full_etd) - _crd
			else null
	    end																													_crd_2_etd
	    ,case 
	    		when _crd is not null
				then _crd - _po_creation_date
			else null
	    end																													_po_2_crd
	    ,_crd - _ptd																										_crd_2_ptd
		,case
			when _eta_source = 'Manual' then null 
			else ds._port_of_discharge end																					_port_of_discharge
	    ,case 
	    	when _eta_source = 'Manual' then null 
	    	else ds._port_of_discharge_name	end																				_port_of_discharge_name
	    ,_arrival_date																										_arrival_date_fallback
		,_departure_date								 																	_departure_date_fallback
	from pre_calc y
	-- OPT (F): port of discharge from _tracker (NULL when the serial has no port of discharge, as the former "having" did)
	left join _tracker ds
		on ds._ship_serial = y._shipment_serial_iss_job
	)
, main as (
	select 
		z.*
		,case 
			when _status = 'Delivered' then _delivery_location
			when _status = 'Arrived' then 'At Port of Discharge'
			when _status = 'In transit' then 'On Water'
			when _pickup_date <= now()::date then 'At Origin Port'
			else 'Shipper Warehouse' end 																									_cur_location
		,case 
			when _ptd_2_now <= 30 then '1 Month Delay'
			when _ptd_2_now <= 60 then '2 Months Delay'
			when _ptd_2_now <= 90 then '3 Months Delay'
			when _ptd_2_now <= 120 then '4 Months Delay'
			when _ptd_2_now > 120 then '4+ Months Delay'
			else null end																													_ptd_2_now_bucket
-- additional conditions promoted to main stage to collapse code length
		,case 
			when _health_check is null or _health_check = 'Healthy'
				then null
			when _ontime_order_placement_perf < 1
				then 'PR to PO delay'
			when _supplier_committed_prod_rdy_perf < 1
				then 'Product Readiness Delay'
			when _iss_cont_booking_perf < 1
				then 'Booking delay'
			when _iss_transit_lead_time_perf < 1
				then 'Trans Shipment delay'
			when _iss_custom_clear_perf < 1
				then 'Custom Clearance Delay'
			else null
		end 																																_reason_code
	    ,case 
	    		when z._status in ('Cancelled','Approved', 'Pending', 'Pending Quotation', 'Pending Quotation Approval', 'Pending Booking','TBA','N/A','','Not Due')
	    				then null
	    		when z._crd  is not null
			      	then z._crd - z._po_need_by_date
	    end																																	_nbd_2_crd
		,case 
			when z._status in ('Cancelled','Approved', 'Pending', 'Pending Quotation', 'Pending Quotation Approval', 'Pending Booking','TBA','N/A','','Not Due')
    				then null
	    		when (coalesce(_arrival_date_full,_full_eta)) is not null
	    			then (coalesce(_arrival_date_full,_full_eta)) - z._po_need_by_date
	    		else null
			end																																__nbd_2_arr
		,case 
			when  _departure_date_fallback is not null and _ptd is not null
				then  _departure_date_fallback - _ptd
			when _ptd is not null and _etd_iss is null 
				then _etd_iss - _ptd
			else null end 																													_ptd_discrepancy_days
		,case 
			when  _arrival_date_fallback is not null and _pta is not null
				then  _arrival_date_fallback - _pta
			when _pta is not null and _eta_iss is null 
				then _eta_iss - _pta
			else null end 																													_pta_discrepancy_days
	from calc z
	)
, mart as(
			select 
				m.*
			,case 
				when _cur_location = 'On Water' then 'On Water'
				when _cur_location = 'Shipper Warehouse' then 'Supplier'
				when _cur_location in ('FW RAMOUL','FW JEBEL ALI','DWC','GAC') then 'EK WH'
				when _cur_location = 'TBA' then 'TBA'
				else 'At Port' end																												_port_water
			,now()::date - _po_need_by_date																										_rdd_2_now
			,_etd_iss - _crd																														_etd_2_crd
			,_po_need_by_date - _pta 																											_rdd_2_pta
			,case 
				when _transport_mode = 'Air' and _direction = 'Inbound' and (_etd_iss - _crd) > 7
					then 'Air 7+ Days'
				when _transport_mode = 'Sea' and _direction = 'Inbound' and (_etd_iss - _crd) > 15
					then 'Sea 15+ Days' 
				else 'On Time' end																												_air_sea_bucket
			,_crd - _ptd																														_ptd_2_crd
			,_del - _ptd																														_del_2_ptd
			,_del - _crd																														_del_2_crd
			,coalesce(_eta_iss,_pta,null)																										_effective_eta
			,coalesce(_eta_iss,_pta,null) - _po_need_by_date																					_eta_delay
			,case 
				when _po_need_by_date is null or coalesce(_eta_iss,_pta,null) is null then null
				when (coalesce(_eta_iss,_pta,null) - _po_need_by_date) >= 30 then 'Delayed (30+ days)'
				when (coalesce(_eta_iss,_pta,null) - _po_need_by_date) >= 15 then 'Delayed (15-29 days)'
				when (coalesce(_eta_iss,_pta,null) - _po_need_by_date) > 0 then 'Delayed (< 15 days)'
				when (coalesce(_eta_iss,_pta,null) - _po_need_by_date) <= 0 then 'On time / Early'
				else null end																													_eta_delay_bucket
			,case 
				when _crd is null or _po_need_by_date is null then null
				when (_crd - _po_need_by_date) > 0 then 'Cargo ready After need-by-date (late by ' || (_crd - _po_need_by_date) || ' days)'
				when (_crd - _po_need_by_date) <= 0 then 'Cargo ready on/before need-by-date (late by ' || abs(_crd - _po_need_by_date) || ' days)' 
				else null end																													_crd_status
			,_po_need_by_date - _pta																											_pta_2_rdd
			,case 
				when _status in ('Cancelled') then null
				when _pta is not null then _pta - _po_need_by_date
				else null end																													_nbd_2_pta_status
			,_etd_iss - _ptd																													_etd_2_ptd
			,_del - _etd_iss																													_del_from_etd
			,_po_need_by_date - _crd																											_crd_2_rdd
			,_ptd - _crd																														_ptd_from_crd
			,_etd_iss - _crd																													_etd_from_crd
			,case 
				when _status = 'Cancelled' then null
				when _eta_iss is not null 
					then _eta_iss - _po_need_by_date
				else null end																													_nbd_2_eta
			,case 
				when _status = 'Cancelled' then null
				when _eta_iss is not null 
					then _po_need_by_date - _eta_iss
				else null end																													_eta_2_nbd
			from main m
)
--select * from main
-- need to agg all items on freight order ID
select 
	_fo_id																				_fo_id
	,max(_shipment_serial_iss_job) 	filter(where _sort = 1)								_shipment_serial_iss_job
	,max(_response_shipment_id) filter(where _sort = 1)									_response_shipment_id
	,max(_inbound_iss_job_no) 	filter(where _sort = 1)									_inbound_iss_job_no
	,max(_outbound_iss_job_no) 	filter(where _sort = 1)									_outbound_iss_job_no
	,max(_branch_bu)																	_branch_bu
	,max(_fe_id)																		_fe_id
	,max(_pid)																			_pid
	,null																				_po_qty_ordered
	,0																					_remaining_quantity
	,max(m._supplier_code) filter(where _sort = 1)										_supplier_code
	,max(m._supplier_name) filter(where _sort = 1)										_supplier_name
	,max(_po_no_EKPOREF) filter(where _sort = 1)										_po_no_ekporef
	,max(_po_uom) filter(where _sort = 1)												_po_uom
	,null																				_item_code
	,string_agg(distinct(_po_no_EKPOREF), ' | ') 
		filter(where _sort <> 1 and _po_no_EKPOREF is distinct from _primary_po)		_secondary_po
	,string_agg(distinct(m._po_remarks), ' | ')											_po_remarks
	,string_agg(distinct(m._commodity), ' | ')											_commodity
	,max(_iss_ref)																		_iss_ref
	,max(_freight_order_comment) filter(where _sort = 1)								_freight_order_comment
	,max(_focus_link) filter(where _sort =1 )											_focus_link
	,max(_quote_date)                 filter(where _sort = 1)    						_quote_date
    ,max(_quote_status)               filter(where _sort = 1)    						_quote_status
    ,max(_quote_amount_usd)           filter(where _sort = 1)    						_quote_amount_usd
    ,max(_quote_details_usd)          filter(where _sort = 1)    						_quote_details_usd
    ,max(_quote_approve_date)         filter(where _sort = 1)    						_quote_approve_date
    ,max(_quote_approve_details_usd)  filter(where _sort = 1)    						_quote_approve_details_usd
    ,max(_quote_approve_amount_usd)   filter(where _sort = 1)    						_quote_approve_amount_usd
    ,max(_quote_approve_amount_aed)   filter(where _sort = 1)							_quote_approve_amount_aed
	,max(_tranship_locode) 		  	  filter(where _sort = 1)							_tranship_locode
	,max(_tranship_port_name)	 	  filter(where _sort = 1)							_tranship_port_name
	,max(_tranship_days)		  	  filter(where _sort = 1)							_tranship_days
	,max(_tranship_vessel)			  filter(where _sort = 1)							_tranship_vessel
	,max(_mode)	filter(where _sort = 1)													_mode
	,max(_transport_mode) filter(where _sort = 1)										_transport_mode
	,max(_direction) filter (where _sort = 1)											_direction
	,max(_client_id)																	_client_id																						
	,max(_client)																		_client
	,max(_lob) filter(where _sort = 1)													_lob
	,max(_routed_by)																	_routed_by
	,max(_incoterms)	filter(where _sort = 1)											_incoterms
	,max(_incoterms_fo)																	_incoterms_fo
	,max(_hbl_hawb)																		_hbl_hawb
	,max(_mbl_mawb)																		_mbl_mawb
	,max(_container_no)																	_container_no
	,max(_origin_port_pol)																_origin_port_pol
	,max(_origin_port_name)																_origin_port_name
	,max(_origin_country) filter(where _sort = 1)										_origin_country
	,max(_origin_country_code) filter(where _sort = 1)									_origin_country_code
	,max(_origin_region_org_reg)														_origin_region_org_reg
	,max(_destination_port_code_dest)													_destination_port_code_dest
	,max(_destination_port_name_dest)													_destination_port_name_dest
	,max(_destination_country_code_dest)												_destination_country_code_dest
	,max(_destination_country_dest)														_destination_country_dest
	,max(_destination_region_reg)														_destination_region_reg
	,max(replace(_eqpt_type,'"',''))													_eqpt_type
	,max(_20_ft)																		_20_ft
	,max(_40_ft)																		_40_ft
	,max(_count_of_cont)																_count_of_cont
	,max(_teus)																			_teus
	,max(_carrier)																		_carrier
	,max(_arrival_date)	filter(where _sort = 1)											_arrival_date
	,max(_arrival_date_actual) filter(where _sort = 1)									_arrival_date_actual
	,max(_arrival_date_full) filter(where _sort = 1)									_arrival_date_full
	,max(_arrival_date)	filter(where _sort = 1)											_arrival_date_fallback	
	,max(_departure_date)	filter(where _sort = 1)										_departure_date
	,max(_departure_date_actual) filter(where _sort = 1)								_departure_date_actual
	,max(_departure_date_full) filter(where _sort = 1)									_departure_date_full
	,max(_departure_date)	filter(where _sort = 1)										_departure_date_fallback
	,max(_pr_appr_date)	filter(where _sort = 1)											_pr_appr_date
	,max(_po_app_date)	filter(where _sort = 1)											_po_app_date
	,max(_po_creation_date)	filter(where _sort = 1)										_po_creation_date
	,max(_po_recd_date)	filter(where _sort = 1)											_po_recd_date
-- should be the closest NeedbyDate
	,max(_po_need_by_date) filter(where _sort = 1)										_po_need_by_date
	,max(_crd) filter(where _sort = 1)													_crd
	,max(_crd_estimated)	filter(where _sort = 1)										_crd_estimated
	,max(_crd_actual)	filter(where _sort = 1)											_crd_actual
	,max(_goods_cleared_origin)															_goods_cleared_origin
	,max(_goods_cleared_destination)													_goods_cleared_destination
	,max(_pickup_date)																	_pickup_date
	,max(_cargo_ho)																		_cargo_ho
	,max(_etd_iss) filter(where _sort = 1)												_etd_iss
	,max(_etd_source) filter(where _sort = 1)											_etd_source
	,max(_etd) filter(where _sort = 1)													_etd
	,max(_etd_wakeo)	filter(where _sort = 1)											_etd_wakeo
	,max(_full_etd)	filter(where _sort = 1)												_full_etd
	,max(_eta_iss) filter(where _sort = 1)												_eta_iss
	,max(_eta_source) filter(where _sort = 1)											_eta_source
	,max(_eta)	filter(where _sort = 1)													_eta
	,max(_eta_wakeo)	filter(where _sort = 1)											_eta_wakeo
	,max(_full_eta)	filter(where _sort = 1)												_full_eta
	,max(_pta)	filter(where _sort = 1)													_pta
	,max(_ptd)	filter(where _sort = 1)													_ptd
	,max(_pod_date)																		_pod_date
	,max(_do_date)																		_do_date
	,max(_do_exp)																		_do_exp
	,max(_del)																			_del
	,max(_pr_number)																	_pr_number
	,max(_pr_date)																		_pr_date	
	,max(_req_status)																	_req_status
	,max(_spo_number)																	_spo_number
	,max(_po_status)																	_po_status
-- copied from [_p2p_value_aed] 
	,max(_org_charges_aed + _frt_charges_aed + _dest_charges_aed)						_spo_invoice_val_aed
	,max(_invoice_no) filter(where _sort = 1)											_invoice_no
	,max(_invoice_issue_date) filter(where _sort = 1)									_invoice_issue_date
	,max(_billing_status)																_billing_status
	,max(_grn_no)																		_grn_no
	,max(_grn_status)																	_grn_status
	,max(_addl_po)																		_addl_po
	,max(_addl_issued_invoices)															_addl_issued_invoices
	,max(_addl_invoice_issue_date)														_addl_invoice_issue_date
	,max(_addl_po_grn)																	_addl_po_grn
	,max(_days_delayed_eta)																_days_delayed_eta
	,max(_days_delayed_etd)																_days_delayed_etd
	,max(_rdd_eta)	filter(where _sort = 1)												_rdd_eta
	,max(_nbd_2_crd)	filter(where _sort = 1)											_nbd_2_crd
	,max(_po_2_crd)	filter(where _sort = 1)												_po_2_crd
	,max(_crd_2_ptd) filter(where _sort = 1)											_crd_2_ptd
	,max(_port_of_discharge) filter(where _sort = 1)									_port_of_discharge
	,max(_port_of_discharge_name) filter(where _sort = 1)								_port_of_discharge_name
	,max(_crd_2_etd)	 filter(where _sort = 1)										_crd_2_etd
	,max(_dep_discrepancy_days) filter(where _sort = 1) 								_dep_discrepancy_days
	,max(_arr_discrepancy_days) filter(where _sort = 1)									_arr_discrepancy_days
	,max(_etd_2_eta)	 filter(where _sort = 1)										_etd_2_eta
	,max(_eta_2_del)	 filter(where _sort = 1)										_eta_2_del
	,max(__nbd_2_arr)	 filter(where _sort = 1)										__nbd_2_arr
	,max(_ptd_discrepancy_days) filter(where _sort = 1)									_ptd_discrepancy_days
	,max(_pta_discrepancy_days) filter(where _sort = 1)									_pta_discrepancy_days
	,max(_nbd_2_del)	 filter(where _sort = 1)										_nbd_2_del
	,max(coalesce(_crd_2_etd,0))	 filter(where _sort = 1)
		+ max(coalesce(_etd_2_eta,0))	 filter(where _sort = 1)
		+ max(coalesce(_eta_2_del,0))	 filter(where _sort = 1)
		+ max(coalesce(__nbd_2_arr,0))	 filter(where _sort = 1)
		+ max(coalesce(_nbd_2_del,0))	 filter(where _sort = 1)						_avg_lt
	,max(_cur_location) filter(where _sort = 1)											_cur_location
	,max(_port_water) filter(where _sort = 1)											_port_water
	,max(_rdd_2_now) filter(where _sort = 1)											_rdd_2_now
	,max(_etd_2_crd) filter(where _sort = 1)											_etd_2_crd
	,max(_rdd_2_pta) filter(where _sort = 1)											_rdd_2_pta
	,max(_air_sea_bucket) filter(where _sort = 1)											_air_sea_bucket
	,max(_ptd_2_crd) filter(where _sort = 1)											_ptd_2_crd
	,max(_del_2_ptd) filter(where _sort = 1)											_del_2_ptd
	,max(_del_2_crd) filter(where _sort = 1)											_del_2_crd
	,max(_effective_eta) filter(where _sort = 1)											_effective_eta
	,max(_eta_delay) filter(where _sort = 1)											_eta_delay
	,max(_eta_delay_bucket) filter(where _sort = 1)											_eta_delay_bucket
	,max(_crd_status) filter(where _sort = 1)											_crd_status
	,max(_pta_2_rdd) filter(where _sort = 1)											_pta_2_rdd
	,max(_nbd_2_pta_status) filter(where _sort = 1)											_nbd_2_pta_status
	,max(_etd_2_ptd) filter(where _sort = 1)											_etd_2_ptd
	,max(_del_from_etd)	filter(where _sort = 1)											_del_from_etd
    ,max(m._crd_2_rdd)     filter(where _sort = 1)    									_crd_2_rdd
    ,max(m._ptd_from_crd)  filter(where _sort = 1)   									_ptd_from_crd
    ,max(m._etd_from_crd)  filter(where _sort = 1)    									_etd_from_crd
    ,max(m._nbd_2_eta)     filter(where _sort = 1)    									_nbd_2_eta
    ,max(m._eta_2_nbd)     filter(where _sort = 1)   									_eta_2_nbd
	,max(_customs_invoice_aed) filter(where _sort = 1)									_customs_invoice_aed
	,max(_customs_invoice_usd) filter(where _sort = 1)									_customs_invoice_usd
	,max(_customs_declared_currency) filter(where _sort = 1) 							_customs_declared_currency
	,max(_days_order_placement_lt) filter(where _sort = 1)								_days_order_placement_lt
	,max(_days_supplier_production_lt) filter(where _sort = 1)							_days_supplier_production_lt
	,max(_days_custom_clearance_lt) filter(where _sort = 1)								_days_custom_clearance_lt
	,max(_days_iss_cont_booking_lt)	filter(where _sort = 1)								_days_iss_cont_booking_lt
	,max(_days_transit_lt) filter(where _sort = 1)										_days_transit_lt
	,max(_e2e_total_lt)	filter(where _sort = 1)											_e2e_total_lt
	,max(m._actual_lead)																_actual_lead
	,max(_status) filter (where _sort = 1)												_status
	,max(_delivery_location)															_delivery_location
	,max(_inner_qty)																	_inner_qty
	,max(_cbm)																			_cbm
	,max(_gw)																			_gross_weight
	,max(_chw)																			_chargeable_weight
	,max(_qnty)																			_quantity
	,max(_pack_type)																	_pack_type
	,max(_ship_remarks_updates)															_ship_remarks_updates
	,max(_ship_billing_remarks)															_ship_billing_remarks
	,max(_pre_alert)																	_pre_alert
	,max(_dn)																			_dn
	,max(_ontime_order_placement_perf) filter(where _sort = 1)							_ontime_order_placement_perf
	,max(_iss_cont_booking_perf)	filter(where _sort = 1)								_iss_cont_booking_perf
	,max(_supplier_committed_prod_rdy_perf) filter(where _sort = 1)						_supplier_committed_prod_rdy_perf
	,max(_iss_transit_lead_time_perf) filter(where _sort = 1)							_iss_transit_lead_time_perf
	,max(_iss_custom_clear_perf)	filter(where _sort = 1)								_iss_custom_clear_perf
	,max(_e2e_total_lead_time_perf) filter(where _sort = 1)								_e2e_total_lead_time_perf
	,max(_days_total_comm_perf) filter(where _sort = 1)									_days_total_comm_perf
	,max(_health_check) filter(where _sort = 1)											_health_check
	,max(_eta_last_change) filter(where _sort = 1) 										_eta_last_change
	,max(_etd_last_change) filter(where _sort = 1) 										_etd_last_change
	,max(_ptd_2_now) filter(where _sort = 1) 											_ptd_2_now
	,max(_ptd_2_now_bucket) filter(where _sort = 1) 									_ptd_2_now_bucket
	,max(_pickup_2_now) filter(where _sort = 1)											_pickup_2_now
	,max(_reason_code)																	_reason_code
	,max(_aux_charge_type)																_aux_charge_type
-- LOCAL costs
	,max(_org_charges_aed)																_org_charges_aed
	,max(_dest_charges_aed)																_dest_charges_aed
	,max(_frt_charges_aed)																_frt_charges_aed
	,max(_aux_charges_aed)																_aux_charges_aed
	,max(
		coalesce(_org_charges_aed, 0) 
		+ coalesce(_frt_charges_aed, 0) 
		+ coalesce(_dest_charges_aed, 0)) 												_p2p_value_aed
    ,max(
		coalesce(_org_charges_aed, 0) 
		+ coalesce(_frt_charges_aed, 0) 
		+ coalesce(_dest_charges_aed, 0) 
		+ coalesce(_aux_charges_aed, 0)) 												_total_charges_aed
-- USD costs
	,max(_org_charges_usd)	 															_org_charges_usd
	,max(_dest_charges_usd)																_dest_charges_usd
	,max(_frt_charges_usd)																_frt_charges_usd
	,max(_aux_charges_usd)																_aux_charges_usd
    ,max(
		coalesce(_org_charges_usd, 0) 
		+ coalesce(_frt_charges_usd, 0) 
		+ coalesce(_dest_charges_usd, 0))												 _p2p_value_usd
    ,max(
		coalesce(_org_charges_usd, 0) 
		+ coalesce(_frt_charges_usd, 0) 
		+ coalesce(_dest_charges_usd, 0) 
		+ coalesce(_aux_charges_usd, 0)) 												_total_charges_usd
-- other costs related cols
	,max(_aux_charge_form_no)															_aux_charge_form_no
	,max(_slt_category) filter (where _sort = 1)										_slt_category
	,max(_supplier_lead_time) filter(where _sort = 1)										_supplier_lead_time
	,max(_country_lead_time)	filter(where _sort = 1)										_country_lead_time
	,max('main')																			_row_type
from mart m
where 1=1
group by 1
-- union all PO lines with remaining quantity, no agg, most attrs are NULLs
union all
select
encode(sha256(( 
	_po_no_EKPOREF::text
	|| _po_desc::text
	|| _po_need_by_date::text
	|| _pid::text)::bytea),'hex')							_line_id
	,NULL                  									_shipment_serial_iss_job
	,null 													_response_shipment_id
	,null 													_inbound_iss_job_no
	,null 													_outbound_iss_job_no
	,a._branch_bu          									_branch_bu
	,NULL													_fe_id
	,a._pid													_pid
	,a.po_qty_ordered										_po_qty_ordered	
	,a.remaining_quantity									_remaining_quantity
	,a._supplier_code      									_supplier_code
	,a._supplier_name      									_supplier_name
	,a._po_no_EKPOREF     									_po_no_ekporef
	,null 													_po_uom
	,a._item_code											_item_code
	,NULL                  									_secondary_po
	,a._po_remarks        									_po_remarks
	,a._commodity          									_commodity
	,NULL                  									_iss_ref
	,null 													_freight_order_comment
	,null 													_focus_link
	,null 													_quote_date
	,null													_quote_status
	,null 													_quote_amount_usd
	,null 													_quote_details_usd
	,null 													_quote_approve_date
	,null 													_quote_approve_details_usd
	,null 													_quote_approve_amount_usd
	,null 													_quote_approve_amount_aed
	,null													_tranship_locode
	,null													_tranship_port_name
	,null													_tranship_days
	,null													_tranship_vessel
	,NULL                  									_mode
	,null													_transport_mode
	,null 													_direction
	,a._client_id											_client_id			
	,a._client             									_client
	,null 													_lob
	,NULL                  									_routed_by
	,_po_incoterms         									_incoterms
	,null 													_incoterms_fo
	,NULL                  									_hbl_hawb
	,NULL                  									_mbl_mawb
	,NULL                  									_container_no
	,NULL                  									_origin_port_pol
	,NULL                  									_origin_port_name
	,NULL                  									_origin_country
	,null													_origin_country_code
	,NULL                  									_origin_region_org_reg
	,null 													_destination_port_code_dest
	,null 													_destination_port_name_dest
	,null 													_destination_country_code_dest
	,NULL                  									_destination_country_dest
	,null 													_destination_region_org_reg
	,NULL                  									_eqpt_type
	,NULL                  									_20_ft
	,NULL                  									_40_ft
	,NULL                  									_count_of_cont
	,NULL                  									_teus
	,NULL                  									_carrier
	,null 													_arrival_date
	,null 													_arrival_date_actual
	,null 													_arrival_date_full
	,null 													_arrival_date_fallback
	,null 													_departure_date
	,null 													_departure_date_actual
	,null 													_departure_date_full
	,null 													_departure_date_fallback
	,a._pr_appr_date       									_pr_appr_date
	,a._po_app_date       									_po_appr_date
	,a._po_creation_date   									_po_creation_date
	,a._po_recd_date       									_po_recd_date
	,a._po_need_by_date    									_po_need_by_date
	,NULL                  									_crd
	,null													_crd_estimated
	,null													_crd_actual
	,null													_goods_cleared_origin
	,null													_goods_cleared_destination
	,NULL                  									_pickup_date
	,NULL                  									_cargo_ho
	,null													_etd_iss
	,null													_etd_source
	,NULL                  									_etd
	,null													_etd_wakeo
	,null													_full_etd
	,null													_eta_iss
	,null													_eta_source
	,NULL                  									_eta
	,null													_eta_wakeo
	,null													_full_eta
	,null													_pta
	,null													_ptd
	,null													_pod_date
	,null 													_do_date
	,NULL                  									_do_exp
	,NULL                  									_del
	,null 													_pr_number
	,null 													_pr_date
	,null 													_req_status
	,null 													_spo_number
	,null 													_po_status
	,null 													_spo_invoice_val_aed
	,null													_invoice_no
	,null 													_invoice_issue_date
	,null													_billing_status
	,null													_grn_no
	,null													_grn_status
	,null													_addl_no
	,null													_addl_issued_invoices
	,null													_addl_invoice_issue_date
	,null													_addl_po_grn
	,null													_days_delayed_eta
	,null													_days_delayed_etd
	,null													_rdd_eta
	,null 													_nbd_2_crd
	,null 													_po_2_crd
	,null 													_crd_2_ptd
	,null 													_port_of_discharge
	,null 													_port_of_discharge_name
	,null													_crd_2_etd
	,null 													_dep_discrepancy_days
	,null 													_arr_discrepancy_days
	,null													_etd_2_eta
	,null													_eta_2_del
	,null													__nbd_2_arr
	,null													_ptd_discrepancy_days
	,null													_pta_discrepancy_days
	,null													_nbd_2_del
	,null													_avg_lt
	,null 													_cur_location
	,null													_port_water
	,null													_rdd_2_now
	,null													_etd_2_crd
	,null													_rdd_2_pta
	,null													_air_sea_bucket
	,null													_ptd_2_crd
	,null													_del_2_ptd
	,null													_del_2_crd
	,null													_effective_eta
	,null													_eta_delay
	,null													_eta_delay_bucket
	,null													_crd_status
	,null													_pta_2_rdd
	,null													_nbd_2_pta_status
	,null													_etd_2_ptd
	,null 													_del_from_etd
    ,null::int    											_crd_2_rdd
    ,null::int    											_ptd_from_crd
    ,null::int    											_etd_from_crd
    ,null::int    											_nbd_2_eta
    ,null::int    											_eta_2_nbd
	,null													_customs_invoice_aed
	,null													_customs_invoice_usd
	,null 													_customs_declared_currency
	,a._days_order_placement_lt								_days_order_placement_lt
	,null 													_days_supplier_production_lt
	,null													_days_custom_clearance_lt
	,null													_days_iss_cont_booking_lt
	,null													_days_transit_lt
	,null													_e2e_total_lt
	,null													_actual_lead
	,a._status             									_status
	,NULL                  									_delivery_location
	,null						  							_inner_qty
	,NULL                  									_cbm
	,NULL                  									_gross_weight
	,NULL                  									_chargeable_weight
	,NULL                  									_quantity
	,NULL                  									_pack_type
	,null 													_ship_remarks_updates
	,null 													_ship_billing_remarks
	,NULL                  									_pre_alert
	,null													_dn
	,_ontime_order_placement_perf							_ontime_order_placement_perf
	,null 													_iss_cont_booking_perf
	,0														_supplier_committed_prod_rdy_perf
	,null													_iss_transit_lead_time_perf
	,null													_iss_custom_clear_perf
	,null													_e2e_total_lead_time_perf
	,null													_days_total_comm_perf
	,null													_health_check
	,null 													_ptd_2_now
	,null 													_ptd_2_now_bucket
	,null 													_eta_last_change
	,null 													_etd_last_change
	,null 													_pickup_2_now
	,null													_reason_code
	,null													_aux_charge_type
	,null													_org_charges_aed
	,null													_dest_charges_aed
	,null													_frt_charges_aed
	,null 													_aux_charges_aed
	,null													_p2p_value_aed
	,null													_total_charges_aed
	,null													_org_charges_usd
	,null													_dest_charges_usd
	,null													_frt_charges_usd
	,null 													_aux_charges_usd
	,null													_p2p_value_usd
	,null													_total_charges_usd
	,null 													_aux_charge_form_no
	,null													_slt_category
	,null													_supplier_lead_time
	,null													_country_lead_time
	,'remaining'												_row_type
from (
				select
					poc."id" 																							_client_id
					,p."ship_to_location"																				_branch_bu
					,p."id" 																								_pid
					,p.supplier_no																						_supplier_code
					,p.supplier_name																						_supplier_name
					,p.po_no 																							_po_no_EKPOREF
					,p.item_code																							_item_code
					,p.po_desc																							_po_desc
					,p.po_remarks																						_po_remarks
					,p.po_desc																							_commodity
					,poc.company_name																					_client
					,p.req_app_dt																						_pr_appr_date
					,p.po_app_dt																							_po_app_date
					,p.po_date																							_po_creation_date
					,(p.po_app_dt + interval '2 days')::date 															_po_recd_date 
					,p.current_po_promised_dt																			_po_need_by_date
					,p.inco_term_po																						_po_incoterms
  					,case 
	  						when p.po_app_dt is not null
	  						and (p.po_app_dt - p.req_app_dt) <= 5
	  							then 1
							when p.po_app_dt is not null and (p.po_app_dt - p.req_app_dt) > 5
	  							then 1 - abs((p.po_app_dt - p.req_app_dt)::numeric / 5)	-- FIX (1): numeric division, as in the enriched block (was integer division)
	  						else 0
	  					end																								_ontime_order_placement_perf
					,case 
						when p.req_app_dt is null
							or p.po_app_dt is null
								then null 
						else p.po_app_dt - p.req_app_dt						
					end																									_days_order_placement_lt
					,case 
						when upper(p.status) = 'CANCELLED'
							then 'Cancelled'
						when upper(p.status) <> 'CANCELLED'
							and current_po_promised_dt::date <= (now()::date + interval '90 days')
							and current_po_promised_dt::date > now()::date
								then 'Pending'
						when upper(p.status) <> 'CANCELLED'
							and current_po_promised_dt::date > (now()::date + interval '90 days')
								then 'Not Due'
						when upper(p.status) <> 'CANCELLED'
							and current_po_promised_dt::date <= now()::date
								then 'Due'
						else null
					end																									_status					
				-- qunatity
					,coalesce(p.po_qty_ordered::float, 0) 																po_qty_ordered
					,coalesce(a.used_quantity::float, 0) 																used_quantity
				-- ramaining quantity = inner qty (from big query)
					,(coalesce(p.po_qty_ordered::float, 0)::numeric - coalesce(a.used_quantity::float, 0))				remaining_quantity
					,coalesce(a.freight_units, '') 																		freight_units
				from portal."PurchaseOrderLine" p 
				left join (
										select
											pof.purchase_order_id																	purchase_order_id
											,coalesce(sum(pof.quantity), 0) 															used_quantity
											,string_agg(distinct pof.freight_unit_no, ', ') 											freight_units
										from portal.purchase_order_on_freight_unit pof
										join portal."PurchaseOrderLine" pol
											on pol.id = pof.purchase_order_id
										group by pof.purchase_order_id
								) a
					on a.purchase_order_id = p."id"
				left join portal.supplier_lead_time_master slt 
					on upper(slt.supplier_name) = upper(p.supplier_name)
				join portal.purchase_order_company poc 
					on poc."id" = p.purchase_order_company_id
				where 1=1
					and (coalesce(p.po_qty_ordered::float, 0)::numeric - coalesce(a.used_quantity::float, 0)) > 0				
	) a

$sql$;



-- 2. run the update using that variable
-- 2. update the live source
-- LIVE: this update publishes this file as the prod EK VIEW.
update sql_source
set _code = current_setting('dev.ek_view_opt')
	,_updated = now()
where _page = 'EK VIEW' and _report = 'COMS';




/*
 * ############################################################### COMPARISON (read-only) ###############################################################
 * Run in ONE session:
 * 		1. in "COMS EK VIEW.sql": ONLY its "set dev.ek_view = $sql$ ... $sql$;" statement (NOT the update below it)
 * 		2. in this file: the "set dev.ek_view_opt = $sql$ ... $sql$;" statement
 * 		3. the DO block below. It only runs SELECTs and prints NOTICE lines; it writes nothing.
 * 		   The original runs once (~7 min), the optimized one twice.
 * Like for like: the original gets the same OPT (Q) tie-break (", p.id" in its two window orders) and the same FIX (1)
 * 		(numeric division in the remaining block) in memory before it runs; the file "COMS EK VIEW.sql" is not changed.
 * What it compares: every column; numbers rounded to 6 decimals (float sums depend on row order);
 * 		_aux_charge_type, _addl_issued_invoices, _addl_invoice_issue_date, _inner_qty compared as sorted lists
 * 		(string_agg without order by: element order depends on the plan).
 * Expected: "rows only in original 0, rows only in optimized 0".
 * 		A small remainder can still come from ties the tie-break cannot see: one PO line on one freight order that
 * 		fans out to several rows (both enrich sides, one serial in two domains, several customs lines) - check those by _fo_id.
 */
do $$
declare
	_pat		text := 'over(partition by f.id order by p.current_po_promised_dt)';
	_pat_1		text := '1-ABS((p.po_app_dt - p.req_app_dt)/5)';
	_old		text := current_setting('dev.ek_view');
	_new		text := current_setting('dev.ek_view_opt');
	_norm		text := $n$
					select
						(
							select
								jsonb_object_agg(
									 e.key
									,case
										when jsonb_typeof(e.value) = 'number'
											then to_jsonb(round(e.value::text::numeric, 6))
										when e.key in ('_aux_charge_type', '_addl_issued_invoices', '_addl_invoice_issue_date', '_inner_qty')
											and jsonb_typeof(e.value) = 'string'
											then to_jsonb(array_to_string(array(
													select x
													from unnest(string_to_array(e.value #>> '{}', ' | ')) x
													order by x), ' | '))
										else e.value
									end)
							from jsonb_each(to_jsonb(q)) e
						)																											_row
					from (%s) q
				$n$;
	_t0			timestamptz;
	_rows_new	bigint;
	_ms_new		numeric;
	_only_old	bigint;
	_only_new	bigint;
begin
	-- the original with the OPT (Q) tie-break: exactly 2 places (row_number and first_value)
	if (length(_old) - length(replace(_old, _pat, ''))) / length(_pat) <> 2 then
		raise exception 'expected 2 window orders "%" in dev.ek_view', _pat;
	end if;
	_old := replace(_old, _pat, 'over(partition by f.id order by p.current_po_promised_dt, p.id)');
	-- the original with FIX (1): exactly 1 place (remaining block)
	if (length(_old) - length(replace(_old, _pat_1, ''))) / length(_pat_1) <> 1 then
		raise exception 'expected 1 "%" in dev.ek_view', _pat_1;
	end if;
	_old := replace(_old, _pat_1, '1 - abs((p.po_app_dt - p.req_app_dt)::numeric / 5)');

	-- timing of the optimized query: to_jsonb(q) makes it compute every column
	_t0 := clock_timestamp();
	execute format('select count(*) from (select to_jsonb(q) from (%s) q) x', _new) into _rows_new;
	_ms_new := round(extract(epoch from clock_timestamp() - _t0)::numeric * 1000);
	raise notice 'optimized: % rows in % ms', _rows_new, _ms_new;

	-- content: multiset difference in both directions, each query run once
	execute format($c$
		with _a as (%s)
			,_b as (%s)
			,_ca as (select a._row, count(*) _n from _a a group by 1)
			,_cb as (select b._row, count(*) _n from _b b group by 1)
		select
			 coalesce(sum(greatest(coalesce(ca._n, 0) - coalesce(cb._n, 0), 0)), 0)
			,coalesce(sum(greatest(coalesce(cb._n, 0) - coalesce(ca._n, 0), 0)), 0)
		from _ca ca
		full join _cb cb on cb._row = ca._row
	$c$, format(_norm, _old), format(_norm, _new))
	into _only_old, _only_new;
	raise notice 'rows only in original %, rows only in optimized %', _only_old, _only_new;
end $$;





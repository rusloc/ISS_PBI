




set dev.focus_view = 
$sql$



with latest_dates_ranked as (
				    select
				        "Parent ID",
				        "Date Type",
				        "New Date",
				        row_number() over(
				            partition by "Parent ID", "Date Type"
				            order by "Changed At" desc
				        ) rn
				    from public.focus__shipment_dates_changes
				    where "Date Type" in (
				        'Cargo Ready Date Actual',
				        'Cargo Ready Date Estimated'
))
,latest_dates AS (
				    select
				        "Parent ID"
				        ,max(
				        	case
				            	when "Date Type" = 'Cargo Ready Date Actual'
				            		then "New Date"
				        	end) 																		"Cargo Ready Date Actual"
				        ,max(
				        	case
				            	when "Date Type" = 'Cargo Ready Date Estimated'
				            		then "New Date"
				        	end)	 																	"Cargo Ready Date Estimated"
				    from latest_dates_ranked
				    where 1=1
				    	and rn = 1
				    group by "Parent ID"
)
,calc as (
					select
					-- columns from report query
						encode(sha256((
								asp."ID" || '-' 
								|| asp."CRM Client"	||  '-' 
								|| asp.iss_domain	|| '-')::bytea),'hex')									_line_id
					    ,asp."ID"																			_ship_id
					    ,asp.iss_domain																		_iss_dom
					    ,'NA'																				_fo_no
					    ,null																				_fo_comments
					    ,asp."Creation Date"::date															_creation_date
					    ,asp."Origin"																		_origin
					    ,asp."Destination"																	_destination
					    ,asp."CRM Client"																	_crm_client
					    ,asp."CRM Client Branch"															_crm_client_branch
					    ,asp."Line Of Business"																_lob
					    ,asp."Departure Date"::date															_departure_date
					    ,asp."ETA"::date																	_eta
					    ,fs."ETA (Wakeo)"::date																_eta_wakeo
					    ,asp."ETD"::date																	_etd
					    ,fs."ETD (Wakeo)"::date																_etd_wakeo
					    ,asp."Arrival Date"::date															_arrival_date
					    ,asp."Delivery Date"::date															_delivery_date
					    ,asp."Pickup / Stuffing Date"::date													_pickup_date
					    ,asp."D/O Date"::date																_do_date
					    ,fs."D/O Expiry Date"::date															_do_exp_date
					    ,fs."PTD"::date																		_ptd
					    ,fs."PTD Source"																	_ptd_source
					    ,fs."PTA"::date																		_pta
					    ,fs."PTA Source"																	_pta_source
						,coalesce(ld."Cargo Ready Date Actual"::date,ld."Cargo Ready Date Estimated"::date)	_crd
					    ,ld."Cargo Ready Date Actual"::date													_crd_actual
					    ,ld."Cargo Ready Date Estimated"::date												_crd_estimated
					-- column from the checck list
					    ,'IFS-INFLIGHT SERVICES'															_branch_bu
					    ,'NA'																				_supplier
					    ,'NA'																				_master_line
					    ,null																				_item_desc
					    ,asp."Service Group"																_transport_mode
					    ,asp."Direction"																	_direction
						,case 
							when upper(asp."Shipping Terms") in ('DAP','CPT','CIF')
								then 'Direct'
							when asp."Agent Type" = 'ISS-GF Agent'
								then 'ISS'
							when asp."Agent Type" <> 'ISS-GF Agent'
								then 'Agent'
							else 'TBA'
						end																					_routed_by
						,asp."Shipping Terms"																_incoterms
					    ,asp."Serial No"																	_shipment_serial_no
					    ,asp."Master No"																	_master_no
					    ,asp."House No"																		_house_no
					    ,asp."Carrier / Shipping Line"														_carrier
						,asp."Commodity" 																	_commodity
						,asp."Origin Region"																_origin_region
						,asp."Origin Country Name"															_origin_country_name
						,asp."Origin"																		_origin_country_code
						,asp."Origin Airport / Port"														_origin_port_code
						,asp."Destination Region"															_destination_region
						,asp."Destination Country Name"														_destination_country_name
						,asp."Destination"																	_destination_country_code
						,asp."Destination Airport / Port"													_destination_port_code
						,case 
							when split_part(s."Service",'_',1) = 'air'
								or s."Shipment Type" = 'LCL'
									then null 
							else e._container_ids end														_container_ids
						,case 
							when split_part(s."Service",'_',1) = 'air'
								or s."Shipment Type" = 'LCL'
									then null 
							else e._container_type end														_container_type
						,case 
							when split_part(s."Service",'_',1) = 'air'
								or s."Shipment Type" = 'LCL'
									then null 
							else e._20_ft end 																_20_ft
						,case 
							when split_part(s."Service",'_',1) = 'air'
								or s."Shipment Type" = 'LCL'
									then null 
							else e._40_ft end																_40_ft
						,case 
							when split_part(s."Service",'_',1) = 'air'
								or s."Shipment Type" = 'LCL'
									then null 
							else e._total_count end															_total_count
						,case 
							when split_part(s."Service",'_',1) = 'air'
								or s."Shipment Type" = 'LCL'
									then null 
							else asp."TEU" end																_teu
						,asp."Pickup / Stuffing Date"::date													_cargo_ho
						,case 
							when asp."Serial No" is not null
								and asp."Arrival Date"::date <= now()::date
								and asp."Delivery Date"::date <= now()::date
									then 'Delivered'
							when  asp."Serial No" is not null
								and split_part(s."Operational Status",'_',2) = 'cancelled'
									then 'Cancelled'
							when asp."Serial No" is not null
								and (asp."Arrival Date"::date > now()::date 
									or asp."Arrival Date"::date is null)
								and asp."Departure Date"::date <= now()::date
									then 'In transit' 
							when asp."Serial No" is not null
								and asp."Arrival Date"::date <= now()::date 
								and asp."Departure Date"::date <= now()::date
								and (asp."Delivery Date"::date is null 
									or asp."Delivery Date"::date >= now()::date)
									then 'Arrived'
							when asp."Serial No" is not null
								and (asp."ETD"::date is not null 
									or asp."ETA"::date is not null)
								and (asp."ETD"::date > now()::date 
									or asp."ETA"::date > now()::date)
									then 'Booked'
							when asp."Serial No" is not null
								and (asp."ETD"::date is null 
									or asp."ETA"::date is null)
					-- need to find/replace 'PRE-ALERT' condition
									then 'Pending Booking'
							when asp."Serial No" is not null
								and (asp."ETD"::date is null 
									or asp."ETA"::date is null)
									then 'Pending Quotation Approval'
							when asp."Serial No" is not null
								then 'Pending Quotation'
							else null end																		_status
						,t._delivery_location_agg																_delivery_location
						,null																					_po_outer_qnty
						,null																					_po_inner_qnty
						,null																					_outer_qnty_shipped
						,null 																					_inner_qnty_shipped
						,coalesce(asp."CBM (LCL)",0) + coalesce(asp."CBM (LCL)",0)								_cbm
						,asp."Total Gross Weight"																_gross_weight
						,asp."Total Chargeable Weight"															_charge_weight
						,asp."Packages"																			_packages
						,com._pack_type_name																	_package_type
						,cv._currency_native																	_customs_declared_currency
						,cv._amount_aed																			_customs_invoice_aed
						,s."Remarks" 																			_remarks
						,null 																					_debit_note
						,null 																					_ontime_order_placement_perf
						,null 																					_supplier_committed_prod_rdy_perf
						,null																					_iss_cont_booking_perf
						,case 
							when asp."Delivery Date"::date is null 
								or coalesce(asp."Arrival Date"::date, asp."ETA"::date) is null 
								or coalesce(asp."Departure Date"::date, asp."ETD"::date) is null
								or asp."Origin" is null
									then 0
							when (coalesce(asp."Arrival Date"::date, asp."ETA"::date)
								- coalesce(asp."Departure Date"::date, asp."ETD"::date) ) <= ctt.average_transit_time
									then 1
							when (coalesce(asp."Arrival Date"::date, asp."ETA"::date)
								- coalesce(asp."Departure Date"::date, asp."ETD"::date) ) > ctt.average_transit_time
									then 1 - abs((coalesce(asp."Arrival Date"::date, asp."ETA"::date)
											- coalesce(asp."Departure Date"::date, asp."ETD"::date))::numeric
											/ coalesce(nullif(ctt.average_transit_time,0),1))
							else 0 end																			_iss_transit_lead_time_perf
						,case 
							when asp."Delivery Date"::date is null 
								or asp."Arrival Date"::date is null
									then 0
							when (asp."Delivery Date"::date - asp."Arrival Date"::date) <= 3
								then 1
							when (asp."Delivery Date"::date - asp."Arrival Date"::date) > 3
								then 1 - abs(
								 (asp."Delivery Date"::date - asp."Arrival Date"::date)::numeric / 3)
							else null end																		_iss_custom_clear_perf
						,null																					_e2e_total_lead_time_perf
						,null																					_days_total_comm_perf
						,null																					_actual_lead
						,null																					_health_check
						,null																					_reason_code
						,null																					_days_order_placement_lt
						,null																					_days_supplier_production_lt
						,case 
							when asp."Delivery Date"::date is not null
								and asp."Arrival Date"::date is not null
									then asp."Delivery Date"::date - asp."Arrival Date"::date
							else 0 end																			_days_custom_clearance_lt
						,case
							when fs."PTD"::date is not null 
								then fs."PTD"::date 
									- coalesce(ld."Cargo Ready Date Actual"::date
												,ld."Cargo Ready Date Estimated"::date)
							else null end 																		_days_iss_cont_booking_lt
						,case
							when coalesce(asp."Arrival Date"::date, asp."ETA"::date
									,fs."PTA"::date) is not null
								then coalesce(asp."Arrival Date"::date, asp."ETA"::date
									,fs."PTA"::date) - coalesce(asp."Loading Date", asp."ETD"::date
															,fs."PTD"::date)
							else null end																		_days_transit_lt
						,null																					_e2e_total_lt
						,null																					_p2p_value_usd
						,s."SPO No"																				_spo_number
						,null																					_po_status
						,case 
							when asp."Departure Date"::date is not null
								and asp."ETD"::date is not null
									then  asp."Departure Date"::date - asp."ETD"::date
							when fs."PTD"::date is not null and asp."ETD"::date is not null 
								then asp."ETD"::date - fs."PTD"::date
							else null end																		_dep_discrepancy_days
						,case 
							when asp."Arrival Date"::date is not null
								and asp."ETA"::date is not null
									then asp."Arrival Date"::date - asp."ETA"::date
							when fs."PTA"::date is not null and asp."ETA"::date is not null
								then asp."ETA"::date - fs."PTA"::date
							else null end																		_arr_discrepancy_days
						,null																					_rdd_eta
						,null																					_nbd_2_crd
						,null																					_po_2_crd
						,case 
							when coalesce(asp."Departure Date"::date, asp."ETD"::date) is not null
								then coalesce(asp."Departure Date"::date, asp."ETD"::date) 
									- ld."Cargo Ready Date Actual"::date
							else null end																		_crd_2_etd
						,case 
							when coalesce(asp."Departure Date"::date,asp."ETD"::date) is not null
								and coalesce( asp."Arrival Date"::date, asp."ETA"::date) is not null 
									then coalesce( asp."Arrival Date"::date, asp."ETA"::date)
										- coalesce(asp."Departure Date"::date,asp."ETD"::date)
							else null end																		_etd_2_eta
						,case
							when coalesce( asp."Arrival Date"::date, asp."ETA"::date) is not null
								then asp."Delivery Date"::date
									- coalesce( asp."Arrival Date"::date, asp."ETA"::date)
							else null end																		_eta_2_del
						,null																					_nbd_2_eta
						,null																					_nbd_2_del
						,null																					_avg_lt
						,case 
							when att._rows is not null and fs."ID" is not null
								then 'Yes'
							when att._rows is null and fs."ID" is not null
								then 'No' 
							else null end																		_dn
						,'https://' || s.iss_domain || '.logistass.com/shipments/' || s."ID" || '/'				_focus_link
					from (
									select 
										*
									from public.analytical__shipments_pbi asp
									where 1=1
											and asp."Creation Date" >= DATE '2026-01-01'
											and asp.iss_domain = 'ISS-AE'
											and asp."CRM Client" = 'EMIRATES AIRLINE'
							--				and asp."CRM Client Branch" = 'EMIRATES AIRLINE - DEPARTMENT - INFLIGHT SERVICES'
											and asp."Direction" = 'Inbound'
							) asp
					left join public.focus__shipments s 
						on s."Serial No" = asp."Serial No"
						and s.iss_domain = asp.iss_domain
					-- delivery location attr
					left join (
									select 
										t."Shipment ID"												_ship_id
										,t.iss_domain												_iss_dom
										,string_agg(t."Pickup Location", ' | ')						_pickup_location_agg
										,string_agg(t."Delivery Location", ' | ')					_delivery_location_agg
									from public.focus__trucks t
									group by 1,2
								) t
						on t._ship_id = s."ID"
						and t._iss_dom = s.iss_domain
					-- package type
					left join (
									select 
										c."Shipment ID"												_ship_id
										,c.iss_domain												_iss_dom
										,string_agg(c."Package Type", ' | ')						_pack_type_code
										,string_agg(p."name", ' | ')								_pack_type_name
									from public.focus__cargos c
									left join public.package_types_coms p
										on p."code" = c."Package Type"
									group by 1,2
								) com 
						on com._ship_id = s."ID"
						and com._iss_dom = s.iss_domain
					left join (
									select 
										a."Parent ID" 												_ship_id
										,count(*)													_rows
									from public.focus__attachments a
									where 1=1
										and a."Label" = 'AGI'
										and a."Uploaded"::int = 1 
									group by 1
								) att
						on att._ship_id = s."ID"
					left join (
					    select distinct
					        "ID"
					        ,"ETA (Wakeo)"
					        ,"ETD (Wakeo)"
					        ,"D/O Expiry Date"
					        ,"PTA"
					        ,"PTA Source"
					        ,"PTD"
					        ,"PTD Source"
					    from public.focus__shipments
					) fs
					    on asp."ID" = fs."ID"
					left join latest_dates ld
					    on asp."ID" = ld."Parent ID"
					left join (
									select 
										e."Master ID"									
										,e.iss_domain
										,string_agg(e."Equipment No", ' | ')										_container_ids
										,string_agg(distinct e."Equipment Type", ' | ')								_container_type
										,count(*) filter(where e."Equipment Type" ilike '%20%')						_20_ft
										,count(*) filter(where e."Equipment Type" ilike '%40%')						_40_ft
										,count(*)																	_total_count
									from public.focus__equipment e 
									group by 1,2
						) e
						on e."Master ID" = s."Master ID"
						and e.iss_domain = s.iss_domain
					left join (
									select 
										cv."Shipment ID" 														_ship_id
										,cv."Bill Of Entry Date"::date 											_bill_of_entry
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
										and cv."Bill Of Entry Date" is not null
										and cv."Declaration Currency" is not null
							) cv
						on cv._ship_id = s."ID"
					left join portal.country_average_transit_time ctt
						on ctt.code = asp."Origin"
					where 1=1
						and not exists (
										select 1
										from portal.freight_unit_enrich fu
										where 1=1
											and (fu.shipment_id = asp."ID"
												or fu.remote_shipment_response ->> 'serial_no' = asp."Serial No"
												or fu.shipment_response ->> 'serial_no' = asp."Serial No"
											))
			)
select 
	c.*
	,case 
		when _ptd is not null 
		and _days_iss_cont_booking_lt > 0
			then 
				case 
					when (_ptd - _crd) <= 7
						then 1
					else 1 - abs(_ptd - _crd)::numeric / 7 
				end 
		else 0 end																										_iss_cont_booking_perf
from calc c
where 1=1
--	and _shipment_serial_no = 'DXBAI26020325'
	
	
$sql$	
	
	


	
-- update source code
update sql_source 
set _code = current_setting('dev.focus_view') 
	,_updated = 	now() 
where 1=1	
	and _page = 'FOCUS VIEW' 
	and _report = 'COMS';

	



	





set dev.focus_view = 
$sql$



with latest_dates_ranked as (
    select
        "Parent ID",
        "Date Type",
        "New Date",
        ROW_NUMBER() over(
            partition by "Parent ID", "Date Type"
            order by "Changed At" desc
        ) rn
    from public.focus__shipment_dates_changes
    where "Date Type" in (
        'Cargo Ready Date Actual',
        'Cargo Ready Date Estimated'
    )
),
latest_dates AS (
    select
        "Parent ID"
        ,MAX(
        	case
            	when "Date Type" = 'Cargo Ready Date Actual'
            		then "New Date"
        	end) 																		"Cargo Ready Date Actual"
        ,MAX(
        	case
            	when "Date Type" = 'Cargo Ready Date Estimated'
            		then "New Date"
        	end)	 																	"Cargo Ready Date Estimated"
    from latest_dates_ranked
    where 1=1
    	and rn = 1
    group by "Parent ID"
)
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
		when upper(asp."Shipping Terms") in ('DAP','CPT', 'CIF')
			then 'Direct'
		when upper(asp."Shipping Terms") not in ('DAP','CPT', 'CIF')
		and asp."Contact Type" = 'intercompany'
			then 'ISS'
		when upper(asp."Shipping Terms") not in ('DAP','CPT', 'CIF')
		and asp."Contact Type" <> 'intercompany'
			then 'Agent'
		else 'NA'
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
	,null 																				_cargo_ho
	,null 																				_status
	,null																				_delivery_location
	,null																				_po_outer_qnty
	,null																				_po_inner_qnty
	,null																				_outer_qnty_shipped
	,null 																				_inner_qnty_shipped
	,coalesce(asp."CBM (LCL)",0) + coalesce(asp."CBM (LCL)",0)							_cbm
	,asp."Total Gross Weight"															_gross_weight
	,asp."Total Chargeable Weight"														_charge_weight
	,asp."Packages"																		_packages
	,null 																				_package_type
	,cv._currency_native																_customs_declared_currency
	,cv._amount_aed																		_customs_invoice_aed
	,s."Remarks" 																		_remarks
	,null 																				_debit_note
	,null 																				_ontime_order_placement_perf
	,null 																				_supplier_committed_prod_rdy_perf
	,null																					_iss_cont_booking_perf
	,null																					_iss_transit_lead_time_perf
	,null																					_iss_custom_clear_perf
	,null																					_e2e_total_lead_time_perf
	,null																					_days_total_comm_perf
	,null																					_actual_lead
	,null																					_health_check
	,null																					_reason_code
	,null																					_days_order_placement_lt
	,null																					_days_supplier_production_lt
	,null																					_days_custom_clearance_lt
	,null																					_days_iss_cont_booking_lt
	,null																					_days_transit_lt
	,null																					_e2e_total_lt
	,null																					_p2p_value_usd
	,null																					_spo_number
	,null																					_po_status
	,null																					_dep_discrepancy_days
	,null																					_arr_discrepancy_days
	,null																					_rdd_eta
	,null																					_nbd_2_crd
	,null																					_po_2_crd
	,null																					_crd_2_etd
	,null																					_etd_2_eta
	,null																					_eta_2_del
	,null																					_nbd_2_eta
	,null																					_nbd_2_del
	,null																					_avg_lt
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
--left join portal.freight_unit_enrich pfuer
--    on pfuer.shipment_id = asp."ID"
where 1=1
	and not exists (
					select 1
					from portal.freight_unit_enrich fu
					where 1=1
						and fu.shipment_id = asp."ID")
	
	
	
	
	
$sql$	
	
	
	
-- update source code
update sql_source 
set _code = current_setting('dev.focus_view') 
	,_updated = 	now() 
where 1=1	
	and _page = 'FOCUS VIEW' 
	and _report = 'COMS';

	
	

	
	
	
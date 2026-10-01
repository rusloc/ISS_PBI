


set dev.coms_dax =
$dax$


EVALUATE
SELECTCOLUMNS (
    '_PO_VIEW_'
    ,"Category",                                           '_PO_VIEW_'[_slt_category]
    ,"Supplier",                                           '_PO_VIEW_'[_supplier_name]
    ,"EK PO REF#",                                         '_PO_VIEW_'[_po_no_ekporef]
    ,"Master Line",                                        '_PO_VIEW_'[_master_line]
    ,"ISS REFERENCE #",                                    '_PO_VIEW_'[_fo_serial]
    ,"PO Description",                                     '_PO_VIEW_'[_commodity]
    ,"ITEM CODE",                                          '_PO_VIEW_'[_item_code]
    ,"MODE",                                               '_PO_VIEW_'[_transport_mode]
    ,"ROUTED BY",                                          '_PO_VIEW_'[_routed_by]
    ,"INCOTERMS",                                          '_PO_VIEW_'[_incoterms]
    ,"ISS JOB#",                                           '_PO_VIEW_'[_shipment_serial_iss_job]
    ,"HB/L#",                                              '_PO_VIEW_'[_hbl_hawb]
    ,"MBL#",                                               '_PO_VIEW_'[_mbl_mawb]
    ,"CONTAINER #",                                        '_PO_VIEW_'[_container_no]
    ,"POL",                                                '_PO_VIEW_'[_origin_port_pol]
    ,"PORT NAME",                                          '_PO_VIEW_'[_origin_port_name]
    ,"ORG COUNTRY",                                        '_PO_VIEW_'[_origin_country]
    ,"ORG REGION",                                         '_PO_VIEW_'[_origin_region_org_reg]
    ,"DEST",                                               '_PO_VIEW_'[_destination_port_code_dest]
    ,"EQPT TYPE",                                          '_PO_VIEW_'[_eqpt_type]
    ,"20'",                                                '_PO_VIEW_'[_20_ft]
    ,"40'",                                                '_PO_VIEW_'[_40_ft]
    ,"# OF CONT.",                                         '_PO_VIEW_'[_count_of_cont]
    ,"# of TEU's",                                         '_PO_VIEW_'[_teus]
    ,"Carrier",                                            '_PO_VIEW_'[_carrier]
    ,"PR APPR DATE",                                       '_PO_VIEW_'[_pr_appr_date]
    ,"PO APPR DATE",                                       '_PO_VIEW_'[_po_app_date]
    ,"PO CREATION DATE",                                   '_PO_VIEW_'[_po_creation_date]
    ,"PO RECD DATE",                                       '_PO_VIEW_'[_po_recd_date]
    ,"PO NEED BY DATE",                                    '_PO_VIEW_'[_po_need_by_date]
    ,"CRD",                                                '_PO_VIEW_'[_crd]
    ,"PICK UP",                                            '_PO_VIEW_'[_pickup_date]
    ,"CARGO H/O",                                          '_PO_VIEW_'[_cargo_ho]
    ,"ETD",                                                '_PO_VIEW_'[_ptd]
    ,"REVISED ETD",                                        '_PO_VIEW_'[_etd_iss]
    ,"ETA",                                                '_PO_VIEW_'[_pta]
    ,"REVISED ETA",                                        '_PO_VIEW_'[_eta_iss]
    ,"D/O EXP",                                            '_PO_VIEW_'[_do_exp]
    ,"DEL",                                                '_PO_VIEW_'[_del]
    ,"STATUS",                                             '_PO_VIEW_'[_status]
    ,"DELIVERY LOCATION",                                  '_PO_VIEW_'[_delivery_location]
    ,"Inner Qty (PO)",                                     '_PO_VIEW_'[_po_inner_qnty]
    ,"Outer Qty (PO)",                                     '_PO_VIEW_'[_po_outer_qty]
    ,"Inner Qty (Enriched)",                               '_PO_VIEW_'[_inner_qnty_shipped]
    ,"Outer Qty (Enriched)",                               '_PO_VIEW_'[_shipped]
    ,"Inner Qty (Balance)",                                '_PO_VIEW_'[_balance_inner_qnty]
    ,"Outer Qty (Balance)",                                '_PO_VIEW_'[_balance_outer_qnty]
    ,"CBM",                                                '_PO_VIEW_'[_cbm]
    ,"G/W (KGS.)",                                         '_PO_VIEW_'[_gw]
    ,"C/W (KGS.)",                                         '_PO_VIEW_'[_chw]
    ,"QTY",                                                '_PO_VIEW_'[_qnty]
    ,"PACK TYPE",                                          '_PO_VIEW_'[_pack_type_name]
    ,"Customs Declared Currency",                          '_PO_VIEW_'[_customs_declared_currency]
    ,"Customs Declared Value",                             '_PO_VIEW_'[_customs_invoice_aed]
    ,"SHIPMENT REMARKS/UPDATES",                           '_PO_VIEW_'[_freight_order_comment]
    ,"P/A Sent",                                           '_PO_VIEW_'[_pre_alert]
    ,"D/N",                                                '_PO_VIEW_'[_dn]
    ,"ON TIME ORDER PLACEMENT PERF %",                     '_PO_VIEW_'[_ontime_order_placement_perf]
    ,"Supplier committed product readiness performance %", '_PO_VIEW_'[_supplier_committed_prod_rdy_perf]
    ,"ISS container booking performance %",                '_PO_VIEW_'[_iss_cont_booking_perf]
    ,"ISS Transit Lead Time Perf %",                       '_PO_VIEW_'[_iss_transit_lead_time_perf]
    ,"ISS custom clearance Perf %",                        '_PO_VIEW_'[_iss_custom_clear_perf]
    ,"E2E TOTAL LEAD TIME ACCURACY",                       '_PO_VIEW_'[_e2e_total_lead_time_perf]
    ,"No of Days Total Comm LT (as per contract)",         '_PO_VIEW_'[_days_total_comm_perf]
    ,"Actual Lead (PO to Date)",                           '_PO_VIEW_'[_actual_lead]
    ,"HEALTH CHECK",                                       '_PO_VIEW_'[_health_check]
    ,"REASON CODE",                                        '_PO_VIEW_'[_reason_code]
    ,"No of Days Order Placement LT",                      '_PO_VIEW_'[_days_order_placement_lt]
    ,"No. of Days Supplier Production Lead Time",          '_PO_VIEW_'[_days_supplier_production_lt]
    ,"No. of Days Custom Clearance LT",                    '_PO_VIEW_'[_days_custom_clearance_lt]
    ,"No. of Days ISS Cont. Booking LT",                   '_PO_VIEW_'[_days_iss_cont_booking_lt]
    ,"No. of Days Transit LT",                             '_PO_VIEW_'[_days_transit_lt]
    ,"E2E Total LT",                                       '_PO_VIEW_'[_e2e_total_lt]
    ,"REQUISITION / BILLING NOTES",                        '_PO_VIEW_'[_ship_billing_remarks]
    ,"SPO #",                                              '_PO_VIEW_'[_spo_number]
    ,"PO STATUS",                                          '_PO_VIEW_'[_po_status]
    ,"Days Delayed - ETD",                                 '_PO_VIEW_'[_etd_2_ptd]
    ,"Days Delayed - ETA",                                 '_PO_VIEW_'[_eta_2_pta]
    ,"RDD-ETA",                                            '_PO_VIEW_'[_nbd_2_pta_status]
    ,"NBD TO CRD",                                         '_PO_VIEW_'[_nbd_2_crd]
    ,"PO TO CRD (Supplier Response)",                      '_PO_VIEW_'[_po_2_crd]
    ,"CRD TO ETD",                                         '_PO_VIEW_'[_crd_2_etd_alt]
    ,"ETD TO ETA",                                         '_PO_VIEW_'[_etd_2_eta_alt]
    ,"ETA TO DEL",                                         '_PO_VIEW_'[_eta_2_del_alt]
    ,"NBD TO ETA",                                         '_PO_VIEW_'[_nbd_2_eta_alt]
    ,"NBD TO DEL",                                         '_PO_VIEW_'[_nbd_2_del]
    ,"AVERAGE LT",                                         '_PO_VIEW_'[_avg_lt]
    ,"VESSEL NAME",                                        '_PO_VIEW_'[_tranship_vessel]
    ,"P&L QUOTED DATE",                                    '_PO_VIEW_'[_quote_date]
    ,"QUOTE CHARGE DESCRIPTION AND AMT BREAK DOWN",        '_PO_VIEW_'[_quote_details_usd]
    ,"P&L QUOTE STATUS",                                   '_PO_VIEW_'[_quote_status]
    ,"P&L QUOTE APPROVED DATE",                            '_PO_VIEW_'[_quote_approve_date]
    ,"P&L APPROVED AMOUNT",                                '_PO_VIEW_'[_quote_approve_details_usd]
    ,"TOTAL QUOTE APPROVED AMOUNT USD",                    '_PO_VIEW_'[_quote_approve_amount_usd]
    ,"TOTAL QUOTE APPROVED AMOUNT AED",                    '_PO_VIEW_'[_quote_approve_amount_aed]
    ,"ETD to TODAY",                                       '_PO_VIEW_'[_ptd_2_now]
    ,"ETD to Today (Bucket)",                              '_PO_VIEW_'[_ptd_2_now_bucket]
    ,"Port / On Water / Supplier",                         '_PO_VIEW_'[_port_water]
    ,"DISCHARGE PORT ETA : JED/KFK/FUJ/SOH",               '_PO_VIEW_'[_port_of_discharge]
    ,"CRD TO INITIAL ETD (BUCKET)",                        '_PO_VIEW_'[_ptd_2_crd]
    ,"PO REVISED RDD TO TODAY (BUCKET)",                   '_PO_VIEW_'[_rdd_2_now]
    ,"PO REVISED RDD TO CRD (BUCKET)",                     '_PO_VIEW_'[_crd_2_cur]
    ,"PO CRD TO REVISED ETD (BUCKET)",                     '_PO_VIEW_'[_etd_2_crd]
    ,"PO REVISED NBD TO ETA",                              '_PO_VIEW_'[_pta_2_rdd]
    ,"AIR ( >7 Days) & SEA (>15 Days)",                    '_PO_VIEW_'[_air_sea_bucket]
    ,"ETD FROM CRD",                                       '_PO_VIEW_'[_ptd_from_crd]
    ,"DEL FROM ETD",                                       '_PO_VIEW_'[_del_from_etd]
    ,"DEL FROM CRD",                                       '_PO_VIEW_'[_del_2_crd]
    ,"EFFECTIVE ETA",                                      '_PO_VIEW_'[_effective_eta]
    ,"ETA DELAY (days late vs Need By)",                   '_PO_VIEW_'[_eta_delay]
    ,"ETA DELAY FLAG",                                     '_PO_VIEW_'[_eta_delay_bucket]
    ,"CRD vs NEED BY (days)",                              '_PO_VIEW_'[_nbd_2_crd]
    ,"CRD READINESS STATUS",                               '_PO_VIEW_'[_crd_status]
)
ORDER BY 
    "EK PO REF#"
    ,"ITEM CODE"
    ,"PO NEED BY DATE"
    ,"Master Line" DESC


$dax$





-- save the DAX query into 'DAX SRC' row
update sql_source
set _code = current_setting('dev.coms_dax')
	,_updated = 	now()
where 1=1
	and _report = 'COMS'
	and _page = 'DAX SRC';






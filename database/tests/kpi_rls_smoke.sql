\set ON_ERROR_ROLLBACK on
\pset pager off
BEGIN;
-- ===== dati sintetici (SOLO test) =====
INSERT INTO core.exhibitor_category(name) VALUES ('Studio indie');
INSERT INTO core.exhibitor(exhibitor_code,legal_name,legal_name_norm,vat_number,category_id)
 SELECT 'ESP00'||i,'Azienda '||i,'AZIENDA '||i,'1000000000'||i,(SELECT category_id FROM core.exhibitor_category) FROM generate_series(1,6) i;
INSERT INTO core.stand(stand_code,pavilion_id,sqm,position_type,first_edition_id)
 SELECT 'P1-A0'||i,(SELECT pavilion_id FROM core.pavilion WHERE code='P1'),10,'LINEA',(SELECT edition_id FROM core.edition WHERE year=2024) FROM generate_series(1,6) i;
INSERT INTO core.stand_edition(stand_id,edition_id,commercial_status)
 SELECT s.stand_id,e.edition_id,'SOLD' FROM core.stand s, core.edition e WHERE e.year=2025 OR (e.year=2024 AND s.stand_code='P1-A01');
INSERT INTO core.price_list(edition_id,origin) SELECT edition_id,'RECONSTRUCTED_FROM_CONTRACTS' FROM core.edition WHERE year IN (2024,2025);
INSERT INTO core.price_item(price_list_id,code,name,item_type,unit,unit_price,pavilion_id)
 SELECT pl.price_list_id,'SPAZIO-P1','Area P1','SPACE','SQM',50,(SELECT pavilion_id FROM core.pavilion WHERE code='P1') FROM core.price_list pl;
INSERT INTO core.price_item(price_list_id,code,name,item_type,unit,unit_price) SELECT price_list_id,'EX-EL3','Elettrico','EXTRA','EACH',200 FROM core.price_list;
INSERT INTO core.price_item(price_list_id,code,name,item_type,unit,unit_price,max_quantity) SELECT price_list_id,'SP-SOCIAL','Social','SPONSORSHIP','PACKAGE',300,10 FROM core.price_list;
INSERT INTO core.contract(contract_number,edition_id,exhibitor_id,status,signed_on,list_amount,discount_pct,net_amount)
 SELECT 'C2025-000'||right(x.exhibitor_code,1),e.edition_id,x.exhibitor_id,'SIGNED','2025-03-01',1000,0.10,900 FROM core.exhibitor x, core.edition e WHERE e.year=2025;
INSERT INTO core.contract(contract_number,edition_id,exhibitor_id,status,signed_on,list_amount,discount_pct,net_amount)
 SELECT 'C2024-0001',e.edition_id,x.exhibitor_id,'SIGNED','2024-03-01',1000,0.20,800 FROM core.exhibitor x, core.edition e WHERE e.year=2024 AND x.exhibitor_code='ESP001';
INSERT INTO core.contract_stand(contract_id,stand_edition_id,edition_id)
 SELECT c.contract_id,se.stand_edition_id,c.edition_id
 FROM core.contract c JOIN core.exhibitor x USING (exhibitor_id)
 JOIN core.stand s ON s.stand_code='P1-A0'||right(x.exhibitor_code,1)
 JOIN core.stand_edition se ON se.stand_id=s.stand_id AND se.edition_id=c.edition_id
 WHERE c.contract_number LIKE 'C2025-%';
INSERT INTO core.contract_stand(contract_id,stand_edition_id,edition_id)
 SELECT c.contract_id,se.stand_edition_id,c.edition_id FROM core.contract c JOIN core.stand_edition se ON se.edition_id=c.edition_id JOIN core.stand s ON s.stand_id=se.stand_id AND s.stand_code='P1-A01' WHERE c.contract_number='C2024-0001';
INSERT INTO core.contract_line(contract_id,line_no,line_type,price_item_id,description,quantity,unit_price,amount,contract_stand_id)
 SELECT c.contract_id,1,'SPACE',(SELECT pi.price_item_id FROM core.price_item pi JOIN core.price_list pl USING (price_list_id) WHERE pl.edition_id=c.edition_id AND pi.code='SPAZIO-P1'),'Area',10,50,500,cs.contract_stand_id
 FROM core.contract c JOIN core.contract_stand cs ON cs.contract_id=c.contract_id;
INSERT INTO core.contract_line(contract_id,line_no,line_type,price_item_id,description,quantity,unit_price,amount)
 SELECT c.contract_id,2,'EXTRA',(SELECT pi.price_item_id FROM core.price_item pi JOIN core.price_list pl USING (price_list_id) WHERE pl.edition_id=c.edition_id AND pi.code='EX-EL3'),'El',1,200,200 FROM core.contract c;
INSERT INTO core.contract_line(contract_id,line_no,line_type,price_item_id,description,quantity,unit_price,amount)
 SELECT c.contract_id,3,'SPONSORSHIP',(SELECT pi.price_item_id FROM core.price_item pi JOIN core.price_list pl USING (price_list_id) WHERE pl.edition_id=c.edition_id AND pi.code='SP-SOCIAL'),'Soc',1,300,300 FROM core.contract c;
INSERT INTO core.payment(contract_id,kind,due_on,due_amount,paid_on,paid_amount,paid_amount_is_assumed)
 SELECT contract_id,'DEPOSIT','2025-03-16',270,'2025-03-10',270,true FROM core.contract WHERE contract_number LIKE 'C2025-%';
INSERT INTO core.payment(contract_id,kind,due_on,due_amount,paid_on,paid_amount,paid_amount_is_assumed)
 SELECT contract_id,'BALANCE','2025-11-19',630,CASE WHEN contract_number<>'C2025-0006' THEN DATE '2025-11-10' END,CASE WHEN contract_number<>'C2025-0006' THEN 630 END,contract_number<>'C2025-0006' FROM core.contract WHERE contract_number LIKE 'C2025-%';
INSERT INTO core.ticket_order(order_code,edition_id,channel_id,purchased_at,source_id)
 SELECT 'O25-1',e.edition_id,(SELECT channel_id FROM core.sales_channel WHERE code='ONLINE'),'2025-11-01T10:00:00Z',(SELECT source_id FROM core.data_source WHERE code='BIGL_2025') FROM core.edition e WHERE e.year=2025;
INSERT INTO core.ticket(ticket_code,order_id,edition_id,ticket_type_id,valid_day,price,persons,source_id)
 SELECT t.code,o.order_id,o.edition_id,(SELECT ticket_type_id FROM core.ticket_type WHERE code=t.tt),t.vd::date,t.p,t.n,o.source_id
 FROM core.ticket_order o, (VALUES ('T1','FULL','2025-12-19',22,1),('T2','FULL','2025-12-19',22,1),('T3','FAMILY','2025-12-20',60,4),('T4','PASS_3D',NULL,49,1)) AS t(code,tt,vd,p,n);
INSERT INTO core.gate_reading(edition_id,gate_id,ticket_code,ticket_id,read_at,result,source_id,source_row_key)
 SELECT e.edition_id,(SELECT gate_id FROM core.gate WHERE gate_code=r.g),r.c,(SELECT ticket_id FROM core.ticket WHERE ticket_code=r.c),r.t::timestamptz,r.res,(SELECT source_id FROM core.data_source WHERE code='TORN_2025'),r.g||r.c||r.t
 FROM core.edition e, (VALUES ('P1-NORD','T1','2025-12-19T08:10:00Z','OK'),('P1-NORD','T1','2025-12-19T08:20:00Z','OK'),('P1-SUD','T2','2025-12-19T08:30:00Z','OK'),
   ('P2-OVEST','T4','2025-12-19T09:00:00Z','OK'),('P1-NORD','T9','2025-12-19T08:15:00Z','OK'),('P1-NORD','T3','2025-12-20T08:10:00Z','KO')) AS r(g,c,t,res)
 WHERE e.year=2025;
INSERT INTO core.stand_visit_hourly(stand_edition_id,visit_date,visit_hour,scans,source_id)
 SELECT se.stand_edition_id,DATE '2025-12-19',h,10+h,(SELECT source_id FROM core.data_source WHERE code='VISITE_2025') FROM core.stand_edition se JOIN core.edition e USING (edition_id), generate_series(10,11) h WHERE e.year=2025;
INSERT INTO core.stand_lead(lead_code,stand_edition_id,exhibitor_id,captured_at,email_hash,marketing_consent,review_status,source_id)
 SELECT 'L'||n,se.stand_edition_id,x.exhibitor_id,'2025-12-19T10:00:00Z',decode(repeat('ab',32),'hex'),true,CASE n WHEN 1 THEN 'OK' ELSE 'PRIVACY_REVIEW' END,(SELECT source_id FROM core.data_source WHERE code='LEAD_2025')
 FROM generate_series(1,2) n, core.exhibitor x JOIN core.stand s ON s.stand_code='P1-A01' JOIN core.stand_edition se ON se.stand_id=s.stand_id JOIN core.edition e ON e.edition_id=se.edition_id AND e.year=2025 WHERE x.exhibitor_code='ESP001';
COMMIT;
\echo '===== K1 mismatch viste di controllo (atteso 0 e 0)'
SELECT (SELECT count(*) FROM dq.v_stand_status_mismatch) AS mismatch_stand, (SELECT count(*) FROM dq.v_contract_amount_mismatch) AS mismatch_importi;
\echo '===== K2 commerciale (atteso 2025: 6 contratti, net 5400, space 2700, extras 1080, spons 1620, parts_diff 0, cash 4770, rev/mq 45, deposito 100)'
SELECT year,contracts_signed,contracted_net,round(space_net,2) space_net,round(extras_net,2) extras_net,round(sponsorship_net,2) sp,round(parts_diff,6) parts_diff,cash_collected,sqm_sold,revenue_per_sqm,deposit_paid_pct FROM analytics.kpi_commercial_edition ORDER BY year;
\echo '===== K3 saturazione (atteso 2025 P1: sold 60 / sellable 60 = 100)'
SELECT edition_id,pavilion_id,stands_sold,sqm_sellable,sqm_sold,saturation_pct FROM analytics.kpi_saturation WHERE sqm_sellable>0 ORDER BY 1,2 NULLS LAST;
\echo '===== K4 visitatori 2025 (atteso: venduti 4, persone 7, validati 3, validation 75.00, ingressi-giorno 3, passaggi 6, orfani 1)'
SELECT year,tickets_sold,persons_sold,tickets_validated,validation_rate_pct,unique_daily_entries,passes_total,passes_orphan FROM analytics.kpi_visitors_edition WHERE year=2025;
\echo '===== K5 picco presenza stimata 19/12 (atteso P1=3 (T1,T2,T9), P2=1, totale evento NULL=4)'
SELECT pavilion_id,peak_est_present,peak_bucket_end,is_estimate FROM analytics.kpi_presence_peak WHERE day_date='2025-12-19' ORDER BY pavilion_id NULLS LAST;
\echo '===== K6 confronto edizioni (atteso 2025 vs 2024: +575.00)'
SELECT year,contracted_net,prev_year,contracted_net_delta_pct FROM analytics.kpi_edition_comparison ORDER BY year;
\echo '===== K7 rinnovo (atteso 2024: 1,1,100.00 ; 2025: rate NULL)'
SELECT year,exhibitors,renewed_next,renewal_rate_pct FROM analytics.kpi_renewal_edition ORDER BY year;
\echo '===== K8 ESP001 (atteso 2025: visite 43, visits_per_sqm 4.30, lead qualificati 0, cost_per_qualified_contact NULL, delta +12.50)'
SELECT year,contracted_net,sqm,revenue_per_sqm,visits,visits_per_sqm,leads_collected,leads_qualified,cost_per_qualified_contact,prev_year,contracted_net_delta_pct FROM analytics.kpi_exhibitor_edition WHERE exhibitor_id=(SELECT exhibitor_id FROM core.exhibitor WHERE exhibitor_code='ESP001') ORDER BY year;
\echo '===== K9 riconciliazione (atteso tutti MATCH)'
SELECT check_code,edition_id,value_a,value_b,status FROM analytics.reconciliation_status WHERE value_a<>0 OR value_b<>0 ORDER BY 1,2;
\echo '########## SICUREZZA ##########'
SELECT exhibitor_id AS e1 FROM core.exhibitor WHERE exhibitor_code='ESP001' \gset
SELECT exhibitor_id AS e2 FROM core.exhibitor WHERE exhibitor_code='ESP002' \gset
\echo '--- S1 portale ESP001 (atteso C2024-0001 e C2025-0001)'
BEGIN; SET LOCAL ROLE arcade_portal; SELECT set_config('app.exhibitor_id', :'e1', true);
SELECT contract_number FROM core.contract ORDER BY 1;
\echo '--- S2 (atteso lines 6, pays 2, stands 2)'
SELECT (SELECT count(*) FROM core.contract_line) lines,(SELECT count(*) FROM core.payment) pays,(SELECT count(*) FROM core.contract_stand) stands;
\echo '--- S3 altri espositori invisibili (atteso 1)'
SELECT count(*) AS esp_visibili FROM core.exhibitor;
\echo '--- S4 visite proprie (atteso 2)'
SELECT count(*) FROM core.stand_visit_hourly;
\echo '--- S5 lead propri non in revisione (atteso L1)'
SELECT lead_code FROM core.stand_lead;
\echo '--- S6 email_hash vietato (atteso ERRORE permission denied)'
SELECT email_hash FROM core.stand_lead;
\echo '--- S7 ticket / gate_reading / audit_log vietati (atteso 3 ERRORI)'
SELECT count(*) FROM core.ticket;
SELECT count(*) FROM core.gate_reading;
SELECT count(*) FROM core.audit_log;
\echo '--- S8 scrittura vietata (atteso ERRORE)'
UPDATE core.contract SET net_amount=1;
\echo '--- S9 viste portale'
SELECT contract_number,edition_year,stands,deposit_paid_on,balance_paid_on FROM portal.v_my_contracts ORDER BY 1;
SELECT edition_year,stand_code,sum(visits) FROM portal.v_my_visits_hourly GROUP BY 1,2;
SELECT edition_year,visits,visits_per_sqm,contracted_net_delta_pct FROM portal.v_my_kpi ORDER BY 1;
\echo '--- S10 benchmark anonimo (6 espositori >= 5 => 1 riga)'
SELECT * FROM portal.v_benchmark_visits_per_sqm;
COMMIT;
\echo '--- S11 FAIL-CLOSED senza app.exhibitor_id (atteso 0,0,0,0)'
BEGIN; SET LOCAL ROLE arcade_portal;
SELECT (SELECT count(*) FROM core.contract) c,(SELECT count(*) FROM portal.v_my_contracts) v1,(SELECT count(*) FROM portal.v_my_kpi) v2,(SELECT count(*) FROM portal.v_benchmark_visits_per_sqm) bench;
COMMIT;
\echo '--- S12 sessione ESP002: solo C2025-0002, 0 lead'
BEGIN; SET LOCAL ROLE arcade_portal; SELECT set_config('app.exhibitor_id', :'e2', true);
SELECT contract_number FROM core.contract; SELECT count(*) AS lead_visibili FROM core.stand_lead;
COMMIT;
\echo '--- S13 STAFF vede tutto (atteso 7)'
BEGIN; SET LOCAL ROLE arcade_app; SELECT count(*) FROM core.contract;
\echo '--- S14 audit append-only (INSERT ok, UPDATE e DELETE ERRORE)'
INSERT INTO core.audit_log(action,entity) VALUES ('TEST','x');
UPDATE core.audit_log SET action='y';
DELETE FROM core.audit_log;
COMMIT;
\echo '--- S15 BI: analytics ok, core e portal vietati (atteso 1 riga, poi 2 ERRORI)'
BEGIN; SET LOCAL ROLE arcade_bi; SELECT count(*) FROM analytics.kpi_saturation;
SELECT * FROM core.contract LIMIT 1;
SELECT * FROM portal.v_my_contracts;
COMMIT;
\echo '--- S16 ETL: DELETE sul core vietato (ERRORE), staging leggibile'
BEGIN; SET LOCAL ROLE arcade_etl; DELETE FROM core.ticket; SELECT count(*) FROM staging.stg_ticket;
COMMIT;

\set ON_ERROR_ROLLBACK on
BEGIN;
INSERT INTO core.stand(stand_code,pavilion_id,sqm,position_type,first_edition_id)
 SELECT 'P1-A01',pavilion_id,36,'LINEA',(SELECT edition_id FROM core.edition WHERE year=2024) FROM core.pavilion WHERE code='P1';
INSERT INTO core.stand_edition(stand_id,edition_id) SELECT s.stand_id,e.edition_id FROM core.stand s, core.edition e WHERE e.year IN (2025,2026);
INSERT INTO core.exhibitor_category(name) VALUES ('Publisher');
INSERT INTO core.exhibitor(exhibitor_code,legal_name,legal_name_norm,vat_number,category_id)
 SELECT 'ESP001','Onda S.p.A.','ONDA','25634216073',category_id FROM core.exhibitor_category;
INSERT INTO core.exhibitor(exhibitor_code,legal_name,legal_name_norm,vat_number,category_id)
 SELECT 'ESP002','Sestante S.r.l.','SESTANTE','30365414586',category_id FROM core.exhibitor_category;
INSERT INTO core.contract(contract_number,edition_id,exhibitor_id,status,signed_on,list_amount,discount_pct,net_amount)
 SELECT 'C2025-0001',e.edition_id,x.exhibitor_id,'SIGNED','2025-03-01',1000,0.05,950 FROM core.edition e, core.exhibitor x WHERE e.year=2025 AND x.exhibitor_code='ESP001';
INSERT INTO core.contract(contract_number,edition_id,exhibitor_id,status,signed_on,list_amount,discount_pct,net_amount)
 SELECT 'C2025-0002',e.edition_id,x.exhibitor_id,'SIGNED','2025-03-02',1000,0,1000 FROM core.edition e, core.exhibitor x WHERE e.year=2025 AND x.exhibitor_code='ESP002';
INSERT INTO core.contract_stand(contract_id,stand_edition_id,edition_id)
 SELECT c.contract_id,se.stand_edition_id,c.edition_id FROM core.contract c JOIN core.stand_edition se ON se.edition_id=c.edition_id WHERE c.contract_number='C2025-0001';
\echo '--- TEST 1: doppia vendita stesso stand/edizione (atteso: ERRORE unique)'
INSERT INTO core.contract_stand(contract_id,stand_edition_id,edition_id)
 SELECT c.contract_id,se.stand_edition_id,c.edition_id FROM core.contract c JOIN core.stand_edition se ON se.edition_id=c.edition_id WHERE c.contract_number='C2025-0002';
\echo '--- TEST 2: stand di edizione 2026 su contratto 2025 (atteso: ERRORE FK composita)'
INSERT INTO core.contract_stand(contract_id,stand_edition_id,edition_id)
 SELECT c.contract_id,se.stand_edition_id,c.edition_id FROM core.contract c, core.stand_edition se JOIN core.edition e ON e.edition_id=se.edition_id WHERE c.contract_number='C2025-0002' AND e.year=2026;
\echo '--- TEST 3: imponibile incoerente con sconto (atteso: ERRORE check)'
INSERT INTO core.contract(contract_number,edition_id,exhibitor_id,status,signed_on,list_amount,discount_pct,net_amount)
 SELECT 'C2025-0003',e.edition_id,x.exhibitor_id,'SIGNED','2025-03-02',1000,0.10,950 FROM core.edition e, core.exhibitor x WHERE e.year=2025 AND x.exhibitor_code='ESP002';
\echo '--- TEST 4: biglietto con giorno valido fuori edizione (atteso: ERRORE FK edition_day)'
INSERT INTO core.ticket_order(order_code,edition_id,channel_id,purchased_at,source_id)
 SELECT 'O25000001',e.edition_id,(SELECT channel_id FROM core.sales_channel LIMIT 1),now(),(SELECT source_id FROM core.data_source WHERE code='BIGL_2025') FROM core.edition e WHERE e.year=2025;
INSERT INTO core.ticket(ticket_code,order_id,edition_id,ticket_type_id,valid_day,price,persons,source_id)
 SELECT 'T25000001',o.order_id,o.edition_id,(SELECT ticket_type_id FROM core.ticket_type WHERE code='FULL'),'2025-12-25',22,1,o.source_id FROM core.ticket_order o;
\echo '--- TEST 5: abbonamento 3gg con valid_day NULL (atteso: OK)'
INSERT INTO core.ticket(ticket_code,order_id,edition_id,ticket_type_id,valid_day,price,persons,source_id)
 SELECT 'T25000002',o.order_id,o.edition_id,(SELECT ticket_type_id FROM core.ticket_type WHERE code='PASS_3D'),NULL,49,1,o.source_id FROM core.ticket_order o;
\echo '--- TEST 6: lettura orfana (ticket_id NULL) accettata + idempotenza (atteso: OK poi ERRORE unique)'
INSERT INTO core.gate_reading(edition_id,gate_id,ticket_code,read_at,result,source_id,source_row_key)
 SELECT 1,1,'T25999999','2025-12-19T08:00:05Z','OK',(SELECT source_id FROM core.data_source WHERE code='TORN_2025'),'P1-NORD|T25999999|2025-12-19T08:00:05Z';
INSERT INTO core.gate_reading(edition_id,gate_id,ticket_code,read_at,result,source_id,source_row_key)
 SELECT 1,1,'T25999999','2025-12-19T08:00:05Z','OK',(SELECT source_id FROM core.data_source WHERE code='TORN_2025'),'P1-NORD|T25999999|2025-12-19T08:00:05Z';
\echo '--- TEST 7: viste di controllo (atteso: v_stand_status_mismatch segnala lo stand con contratto ma non SOLD)'
SELECT * FROM dq.v_stand_status_mismatch;
\echo '--- TEST 8: mismatch somma righe (nessuna riga -> vuoto)'
SELECT * FROM dq.v_contract_amount_mismatch;
ROLLBACK;

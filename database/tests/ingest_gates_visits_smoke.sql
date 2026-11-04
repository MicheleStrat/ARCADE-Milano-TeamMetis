-- Test V5 per tornelli (2024 e 2025), visite stand e rilancio dei batch.
-- Eseguire su un database VUOTO con V1..V5. Tutto e' in una transazione e termina con ROLLBACK.
-- Dati sintetici scritti per il test: nessun dato del cliente.
\set ON_ERROR_STOP on
BEGIN;

-- ---------- dati minimi: espositore, due stand 2025 (uno venduto, uno no), contratto firmato ----------
INSERT INTO core.exhibitor_category(name) VALUES ('Test');
INSERT INTO core.exhibitor(exhibitor_code, legal_name, legal_name_norm, vat_number, category_id)
SELECT 'ESP001', 'Azienda Test', 'AZIENDA TEST', '00000000001', category_id FROM core.exhibitor_category;
INSERT INTO core.stand(stand_code, pavilion_id, sqm, position_type, first_edition_id)
SELECT c, (SELECT pavilion_id FROM core.pavilion WHERE code = 'P1'), 36, 'LINEA', (SELECT edition_id FROM core.edition WHERE year = 2024)
FROM (VALUES ('P1-A01'), ('P1-A02')) AS v(c);
INSERT INTO core.stand_edition(stand_id, edition_id)
SELECT s.stand_id, e.edition_id FROM core.stand s, core.edition e WHERE e.year = 2025;
INSERT INTO core.contract(contract_number, edition_id, exhibitor_id, status, signed_on, list_amount, net_amount)
SELECT 'C2025-0001', e.edition_id, x.exhibitor_id, 'SIGNED', '2025-03-01', 100, 100
FROM core.edition e, core.exhibitor x WHERE e.year = 2025;
INSERT INTO core.contract_stand(contract_id, stand_edition_id, edition_id)
SELECT c.contract_id, se.stand_edition_id, c.edition_id
FROM core.contract c
JOIN core.stand_edition se ON se.edition_id = c.edition_id
JOIN core.stand s ON s.stand_id = se.stand_id AND s.stand_code = 'P1-A01';

-- ---------- biglietti 2025 e 2024 ----------
INSERT INTO dq.import_batch(source_id, file_name, file_sha256, triggered_by)
SELECT source_id, 'tkt25.csv', repeat('1', 64), 'test' FROM core.data_source WHERE code = 'BIGL_2025';
INSERT INTO dq.import_batch(source_id, file_name, file_sha256, triggered_by)
SELECT source_id, 'tkt24.csv', repeat('2', 64), 'test' FROM core.data_source WHERE code = 'BIGL_2024';
INSERT INTO staging.stg_ticket(batch_id, row_no, id_ordine, id_biglietto, data_acquisto, canale, tipo_biglietto, giorno_valido, prezzo, persone, fascia_eta_titolare, provincia, codice_sconto)
SELECT b.batch_id, v.n, v.o, v.t, v.acq, v.canale, v.tipo, v.giorno, '22,00', '1', '25-34', 'MI', NULL
FROM dq.import_batch b
JOIN (VALUES
  ('tkt25.csv', 1, 'O-A', 'T-A', '01/12/2025 10:00', 'Online',              'Giornaliero intero',   '19/12/2025'),
  ('tkt25.csv', 2, 'O-B', 'T-B', '01/12/2025 10:00', 'Rivenditore partner', 'Abbonamento 3 giorni', '3 giorni'),
  ('tkt24.csv', 1, 'O-C', 'T24-A', '01/12/2024 10:00', 'Cassa',             'Intero',               '20/12/2024')
) AS v(f, n, o, t, acq, canale, tipo, giorno) ON v.f = b.file_name;
SELECT batch_id AS b_t25 FROM dq.import_batch WHERE file_name = 'tkt25.csv' \gset
SELECT batch_id AS b_t24 FROM dq.import_batch WHERE file_name = 'tkt24.csv' \gset
CALL dq.load_ticket_batch(:b_t25);
CALL dq.load_ticket_batch(:b_t24);

DO $$
BEGIN
  ASSERT (SELECT count(*) FROM core.ticket) = 3, 'attesi 3 biglietti nel core (incluso il canale "Rivenditore partner")';
  ASSERT (SELECT count(*) FROM dq.quarantine) = 0, 'nessuna quarantena per i biglietti validi';
END $$;

-- ---------- tornelli 2025 (v2, UTC) ----------
INSERT INTO dq.import_batch(source_id, file_name, file_sha256, triggered_by)
SELECT source_id, 'torn25.csv', repeat('3', 64), 'test' FROM core.data_source WHERE code = 'TORN_2025';
INSERT INTO staging.stg_gate_reading_v2(batch_id, row_no, timestamp_utc, ticket_code, gate_id, result)
SELECT b.batch_id, v.n, v.ts, v.code, v.gate, v.res
FROM dq.import_batch b
CROSS JOIN (VALUES
  (1, '2025-12-19T08:00:05Z', 'T-A', 'P1-Sud',  'OK'),  -- 09:00:05 a Milano: NON fuori orario
  (2, '2025-12-19T08:00:05Z', 'T-A', 'P1-Sud',  'OK'),  -- identica alla 1: va conservata (chiave #2)
  (3, '2025-12-19T08:30:00Z', 'T-B', 'P1-Nord', 'KO'),  -- GAT-003
  (4, '2025-12-19T08:31:00Z', 'T-X', 'P1-Nord', 'OK'),  -- codice orfano: GAT-001, caricata
  (5, '2025-12-19T08:32:00Z', 'T-A', 'XX-Sud',  'OK'),  -- varco sconosciuto: quarantena GAT-008
  (6, 'not-a-date',           'T-A', 'P1-Sud',  'OK'),  -- istante non valido: quarantena
  (7, '2025-12-19T08:33:00Z', '',    'P1-Sud',  'OK'),  -- codice vuoto: quarantena (non deve sparire)
  (8, '2025-12-19T16:45:00Z', 'T-A', 'P1-Sud',  'OK'),  -- 17:45 a Milano: GAT-002 fuori orario
  (9, '2025-12-20T08:00:00Z', 'T-A', 'P1-Sud',  'OK')   -- giorno diverso dal giorno valido: GAT-005
) AS v(n, ts, code, gate, res)
WHERE b.file_name = 'torn25.csv';
SELECT batch_id AS b_g25 FROM dq.import_batch WHERE file_name = 'torn25.csv' \gset
CALL dq.load_gate_batch(:b_g25);

DO $$
DECLARE b bigint := (SELECT batch_id FROM dq.import_batch WHERE file_name = 'torn25.csv');
BEGIN
  ASSERT (SELECT rows_read FROM dq.import_batch WHERE batch_id = b) = 9, 'rows_read';
  ASSERT (SELECT rows_loaded FROM dq.import_batch WHERE batch_id = b) = 6, 'rows_loaded = 6 (righe 1,2,3,4,8,9)';
  ASSERT (SELECT rows_quarantined FROM dq.import_batch WHERE batch_id = b) = 3, 'rows_quarantined = 3 (righe 5,6,7)';
  ASSERT (SELECT rows_read - rows_loaded - rows_quarantined - rows_rejected FROM dq.import_batch WHERE batch_id = b) = 0,
         'nessuna riga persa: lette = caricate + quarantena + scartate';
  ASSERT (SELECT count(*) FROM core.gate_reading WHERE import_batch_id = b AND source_row_key = 'P1-SUD|T-A|2025-12-19T08:00:05Z') = 1, 'chiave naturale della prima lettura';
  ASSERT (SELECT count(*) FROM core.gate_reading WHERE import_batch_id = b AND source_row_key = 'P1-SUD|T-A|2025-12-19T08:00:05Z#2') = 1, 'la lettura identica e'' conservata con suffisso #2';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-002') = 1, 'GAT-002 solo per la riga 8 (non per le 09:00 locali)';
  ASSERT (SELECT source_row_no FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-002') = 8, 'GAT-002 sulla riga 8';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-001') = 1, 'GAT-001: un solo codice orfano (T-X); il codice vuoto non e'' un orfano';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-003') = 1, 'GAT-003: un esito KO';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-005') = 1, 'GAT-005: lettura in giorno diverso';
  ASSERT (SELECT count(*) FROM dq.quarantine WHERE batch_id = b AND reason_rule = 'GAT-008') = 3, 'tre righe in quarantena GAT-008';
  ASSERT (SELECT count(*) FROM core.gate_reading WHERE import_batch_id = b AND ticket_id IS NULL) = 1, 'un solo orfano nel core';
END $$;

-- ---------- tornelli 2024 (v1, ora locale, esito 1/0) ----------
INSERT INTO dq.import_batch(source_id, file_name, file_sha256, triggered_by)
SELECT source_id, 'torn24.csv', repeat('4', 64), 'test' FROM core.data_source WHERE code = 'TORN_2024';
INSERT INTO staging.stg_gate_reading_v1(batch_id, row_no, data, ora, varco, codice, esito)
SELECT b.batch_id, v.n, v.d, v.o, v.varco, v.cod, v.esito
FROM dq.import_batch b
CROSS JOIN (VALUES
  (1, '20/12/2024', '09:00:02', 'P1 Nord', 'T24-A', '1'),
  (2, '20/12/2024', '09:00:03', 'P1 Nord', 'T24-A', '0')
) AS v(n, d, o, varco, cod, esito)
WHERE b.file_name = 'torn24.csv';
SELECT batch_id AS b_g24 FROM dq.import_batch WHERE file_name = 'torn24.csv' \gset
CALL dq.load_gate_batch(:b_g24);

DO $$
DECLARE b bigint := (SELECT batch_id FROM dq.import_batch WHERE file_name = 'torn24.csv');
BEGIN
  ASSERT (SELECT rows_loaded FROM dq.import_batch WHERE batch_id = b) = 2, '2024: due letture caricate (esito 1/0 riconosciuto)';
  ASSERT (SELECT read_at FROM core.gate_reading WHERE import_batch_id = b AND result = 'OK') = timestamptz '2024-12-20 08:00:02+00', '2024: ora locale convertita in UTC';
  ASSERT (SELECT count(*) FROM core.gate_reading WHERE import_batch_id = b AND result = 'KO') = 1, '2024: esito 0 = KO';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-007') = 1, 'GAT-007 una sola volta per batch';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'GAT-002') = 0, '2024: nessun falso fuori orario';
END $$;

-- ---------- visite stand 2025 ----------
INSERT INTO dq.import_batch(source_id, file_name, file_sha256, triggered_by)
SELECT source_id, 'visite25.csv', repeat('5', 64), 'test' FROM core.data_source WHERE code = 'VISITE_2025';
INSERT INTO staging.stg_stand_visit_hourly(batch_id, row_no, codice_stand, data, ora, scansioni)
SELECT b.batch_id, v.n, v.stand, v.d, v.ora, v.sc
FROM dq.import_batch b
CROSS JOIN (VALUES
  (1, 'P1-A01', '2025-12-19', '09:00', '5'),
  (2, 'P1-A01', '2025-12-19', '10:00', '7'),
  (3, 'P1-A01', '2025-12-19', '10:00', '9'),    -- chiave duplicata: entrambe scartate (VIS-004)
  (4, 'P1-A01', '2025-12-19', '08:00', '3'),    -- prima dell'apertura: caricata e segnalata (VIS-003)
  (5, 'P1-A02', '2025-12-19', '09:00', '4'),    -- stand senza contratto: quarantena
  (6, 'ZZ-Z99', '2025-12-19', '09:00', '4'),    -- stand inesistente: quarantena
  (7, 'P1-A01', '2025-12-19', 'abc',   '4'),    -- ora non valida: quarantena (non deve sparire)
  (8, 'P1-A01', '2025-12-19', '11:00', 'abc')   -- scansioni non numeriche: quarantena (non deve sparire)
) AS v(n, stand, d, ora, sc)
WHERE b.file_name = 'visite25.csv';
SELECT batch_id AS b_v25 FROM dq.import_batch WHERE file_name = 'visite25.csv' \gset
CALL dq.load_stand_visit_batch(:b_v25);

DO $$
DECLARE b bigint := (SELECT batch_id FROM dq.import_batch WHERE file_name = 'visite25.csv');
BEGIN
  ASSERT (SELECT rows_read FROM dq.import_batch WHERE batch_id = b) = 8, 'visite: rows_read';
  ASSERT (SELECT rows_loaded FROM dq.import_batch WHERE batch_id = b) = 2, 'visite: caricate le righe 1 e 4 (l''ora 09:00 e'' riconosciuta)';
  ASSERT (SELECT rows_quarantined FROM dq.import_batch WHERE batch_id = b) = 4, 'visite: quarantena righe 5,6,7,8';
  ASSERT (SELECT rows_rejected FROM dq.import_batch WHERE batch_id = b) = 2, 'visite: scartate le due righe con chiave duplicata';
  ASSERT (SELECT rows_read - rows_loaded - rows_quarantined - rows_rejected FROM dq.import_batch WHERE batch_id = b) = 0, 'visite: nessuna riga persa';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'VIS-004') = 2, 'VIS-004 su entrambe le righe duplicate';
  ASSERT (SELECT count(*) FROM dq.anomaly WHERE batch_id = b AND rule_code = 'VIS-003') >= 1, 'VIS-003 per l''ora prima dell''apertura';
  ASSERT (SELECT sum(scans) FROM core.stand_visit_hourly WHERE import_batch_id = b) = 8, 'scansioni caricate: 5 + 3';
END $$;

-- ---------- rilancio: stesso batch, nessun duplicato e nessun falso positivo ----------
UPDATE dq.import_batch SET status = 'RUNNING', finished_at = NULL WHERE batch_id IN (:b_t25, :b_g25, :b_v25);
CREATE TEMP TABLE _prima AS
SELECT (SELECT count(*) FROM core.ticket) AS tickets, (SELECT count(*) FROM core.gate_reading) AS reads,
       (SELECT count(*) FROM core.stand_visit_hourly) AS visits, (SELECT count(*) FROM dq.anomaly) AS anomalies,
       (SELECT count(*) FROM dq.quarantine) AS quarantine;
CALL dq.load_ticket_batch(:b_t25);
CALL dq.load_gate_batch(:b_g25);
CALL dq.load_stand_visit_batch(:b_v25);

DO $$
DECLARE p _prima%ROWTYPE;
BEGIN
  SELECT * INTO p FROM _prima;
  ASSERT (SELECT count(*) FROM core.ticket) = p.tickets, 'rilancio: biglietti invariati';
  ASSERT (SELECT count(*) FROM core.gate_reading) = p.reads, 'rilancio: letture invariate';
  ASSERT (SELECT count(*) FROM core.stand_visit_hourly) = p.visits, 'rilancio: visite invariate';
  ASSERT (SELECT count(*) FROM dq.anomaly) = p.anomalies, 'rilancio: nessuna anomalia in piu'' (nemmeno falsi duplicati TKT-001)';
  ASSERT (SELECT count(*) FROM dq.quarantine) = p.quarantine, 'rilancio: quarantena invariata';
  ASSERT (SELECT rows_loaded FROM dq.import_batch WHERE file_name = 'tkt25.csv') = 2, 'rilancio: rows_loaded biglietti';
END $$;

\echo 'ingest_gates_visits_smoke: tutti i controlli superati'
ROLLBACK;

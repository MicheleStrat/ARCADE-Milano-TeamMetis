-- Smoke test V5. Eseguire su DB vuoto dopo V1, V2 e V5.
-- Verifica che un biglietto valido entri nel core, mentre duplicato e tipo
-- sconosciuto rimangano tracciati prima del core.
BEGIN;

INSERT INTO dq.import_batch(source_id,file_name,file_sha256,triggered_by)
SELECT source_id,'test_biglietteria_2025.csv',repeat('a',64),'test'
FROM core.data_source WHERE code='BIGL_2025';

INSERT INTO staging.stg_ticket(batch_id,row_no,id_ordine,id_biglietto,data_acquisto,canale,tipo_biglietto,giorno_valido,prezzo,persone,fascia_eta_titolare,provincia,codice_sconto)
SELECT b.batch_id, v.row_no,v.id_ordine,v.id_biglietto,v.data_acquisto,v.canale,v.tipo_biglietto,v.giorno_valido,v.prezzo,v.persone,v.fascia_eta_titolare,v.provincia,v.codice_sconto
FROM dq.import_batch b
CROSS JOIN (VALUES
  (1,'O-TEST-1','T-TEST-1','2025-12-01 10:00:00','ONLINE','INTERO','2025-12-19','20.00','1','25-34','MI',NULL),
  (2,'O-TEST-2','T-TEST-1','2025-12-01 10:00:00','ONLINE','INTERO','2025-12-19','20.00','1','25-34','MI',NULL),
  (3,'O-TEST-3','T-TEST-3','2025-12-01 10:00:00','ONLINE','TIPO SCONOSCIUTO','2025-12-19','20.00','1','25-34','MI',NULL),
  (4,'O-TEST-4','T-TEST-4','2025-12-01 10:00:00','ONLINE','INTERO','2025-12-19','20.00','1','25-34','MI',NULL)
) AS v(row_no,id_ordine,id_biglietto,data_acquisto,canale,tipo_biglietto,giorno_valido,prezzo,persone,fascia_eta_titolare,provincia,codice_sconto)
WHERE b.file_name='test_biglietteria_2025.csv';

SELECT batch_id AS test_batch FROM dq.import_batch WHERE file_name='test_biglietteria_2025.csv' \gset
CALL dq.load_ticket_batch(:test_batch);

DO $$
DECLARE b bigint;
BEGIN
  SELECT batch_id INTO b FROM dq.import_batch WHERE file_name='test_biglietteria_2025.csv';
  IF (SELECT count(*) FROM core.ticket WHERE import_batch_id=b) <> 1 THEN
    RAISE EXCEPTION 'atteso un ticket core: il codice duplicato invalida entrambe le righe';
  END IF;
  IF (SELECT count(*) FROM dq.anomaly WHERE batch_id=b AND rule_code='TKT-001') <> 2 THEN
    RAISE EXCEPTION 'attese due anomalie TKT-001';
  END IF;
  IF (SELECT count(*) FROM dq.quarantine WHERE batch_id=b AND reason_rule='TKT-004') <> 1 THEN
    RAISE EXCEPTION 'attesa una quarantena TKT-004';
  END IF;
  IF (SELECT status FROM dq.import_batch WHERE batch_id=b) <> 'COMPLETED_WITH_ISSUES' THEN
    RAISE EXCEPTION 'atteso batch COMPLETED_WITH_ISSUES';
  END IF;
END $$;

ROLLBACK;

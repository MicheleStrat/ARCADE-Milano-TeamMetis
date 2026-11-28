-- =====================================================================
-- ARCADE Milano - V7: ingestione controllata dei contatti raccolti agli stand
-- (contatti_stand_2025.csv). Team BAD, 8/11/2026. Solo funzioni e procedure.
--
-- Privacy (data-model del BID, principio 7):
--   * l'email NON entra mai nel core: solo sha256(sale || email minuscola);
--   * il sale e' un segreto passato a runtime, mai scritto in file o tabelle;
--   * a fine caricamento la colonna email dello staging viene svuotata (LED-004);
--   * anche in quarantena e nelle anomalie l'email e' sostituita dall'hash.
-- Decisioni BAD dell'8/11 (B-34):
--   * minorenni (14-17): caricati con review_status = PRIVACY_REVIEW e segnalati LED-002
--     (le viste analytics e il portale considerano solo review_status = 'OK');
--   * consenso vuoto = nessun consenso (false), segnalato LED-003;
--   * is_qualified resta false: la definizione di "qualificato" e' del cliente (D9/AS-12).
-- Codice solo ASCII (vedi nota codifica in V6).
-- =====================================================================

INSERT INTO dq.rule (rule_code, area, description, severity, default_action)
VALUES ('LED-007', 'contatti', 'Contatto non interpretabile (codice, istante o email mancanti/non validi)', 'ERROR', 'QUARANTINED')
ON CONFLICT (rule_code) DO NOTHING;

CREATE OR REPLACE PROCEDURE dq.load_stand_lead_batch(p_batch_id bigint, p_salt text)
LANGUAGE plpgsql AS $$
DECLARE v_source smallint; v_edition smallint; v_tz text;
BEGIN
  IF p_salt IS NULL OR length(p_salt) < 12 THEN
    RAISE EXCEPTION 'sale mancante o troppo corto (minimo 12 caratteri)';
  END IF;
  SELECT b.source_id, e.edition_id, s.source_timezone INTO v_source, v_edition, v_tz
    FROM dq.import_batch b JOIN core.data_source s ON s.source_id = b.source_id
    JOIN core.edition e ON e.year = right(s.code, 4)::smallint
   WHERE b.batch_id = p_batch_id AND b.status = 'RUNNING' AND s.kind = 'STAND_LEAD';
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % must be RUNNING STAND_LEAD with a year suffix', p_batch_id; END IF;

  DROP TABLE IF EXISTS _lead;
  CREATE TEMP TABLE _lead ON COMMIT DROP AS
  SELECT s.row_no, dq.norm_text(s.id_contatto) AS lead_code, dq.norm_text(s.codice_stand) AS stand_code,
         dq.norm_text(s.id_espositore) AS exh_code, dq.try_timestamptz(s."timestamp", v_tz) AS captured_at,
         lower(dq.clean_text(s.email)) AS email_norm,
         ab.age_band_id, ab.is_minor, pa.province_id, li.interest_id,
         dq.clean_text(s.interesse) AS interest_raw, dq.try_bool(s.consenso_marketing) AS consent_raw,
         se.stand_edition_id, e.exhibitor_id,
         (SELECT k.exhibitor_id FROM core.contract_stand cs JOIN core.contract k ON k.contract_id = cs.contract_id
           WHERE cs.stand_edition_id = se.stand_edition_id AND cs.released_at IS NULL AND k.status = 'SIGNED' LIMIT 1) AS contract_exhibitor_id,
         to_jsonb(s) - 'email' AS raw_record
    FROM staging.stg_stand_lead s
    LEFT JOIN core.age_band ab       ON ab.code = dq.clean_text(s.fascia_eta)
    LEFT JOIN core.province_alias pa ON pa.alias_norm = dq.norm_text(s.provincia)
    LEFT JOIN core.lead_interest li  ON li.code = lower(dq.clean_text(s.interesse))
    LEFT JOIN core.stand st          ON st.stand_code = dq.norm_text(s.codice_stand)
    LEFT JOIN core.stand_edition se  ON se.stand_id = st.stand_id AND se.edition_id = v_edition
    LEFT JOIN core.exhibitor e       ON e.exhibitor_code = dq.norm_text(s.id_espositore)
   WHERE s.batch_id = p_batch_id;

  ALTER TABLE _lead ADD COLUMN email_hash bytea, ADD COLUMN block_rule text;
  UPDATE _lead SET email_hash = sha256(convert_to(p_salt || email_norm, 'UTF8')) WHERE email_norm ~ '^[^@[:space:]]+@[^@[:space:]]+$';
  UPDATE _lead SET raw_record = raw_record || jsonb_build_object('email_hash', encode(email_hash, 'hex'));

  UPDATE dq.import_batch SET rows_read = (SELECT count(*) FROM _lead) WHERE batch_id = p_batch_id;

  -- Blocchi: righe che non possono entrare nel core (quarantena, mai email in chiaro).
  UPDATE _lead SET block_rule = 'LED-007' WHERE lead_code IS NULL OR captured_at IS NULL OR email_hash IS NULL;
  UPDATE _lead SET block_rule = 'LED-005'
   WHERE block_rule IS NULL AND (stand_edition_id IS NULL OR exhibitor_id IS NULL
         OR contract_exhibitor_id IS NULL OR contract_exhibitor_id <> exhibitor_id);
  PERFORM dq.add_anomaly(p_batch_id, block_rule, row_no, lead_code, jsonb_build_object('stand', stand_code, 'espositore', exh_code))
     FROM _lead WHERE block_rule IS NOT NULL;
  INSERT INTO dq.quarantine (batch_id, source_id, source_row_no, raw_record, reason_rule)
  SELECT p_batch_id, v_source, row_no, raw_record, block_rule FROM _lead WHERE block_rule IS NOT NULL
  ON CONFLICT DO NOTHING;

  -- Segnalazioni sulle righe caricate.
  -- LED-002: minorenni caricati in PRIVACY_REVIEW (decisione B-34), quindi azione LOADED_FLAGGED e non quella di default.
  INSERT INTO dq.anomaly (batch_id, source_id, rule_code, severity, entity, source_row_no, record_ref, detail, action_applied)
  SELECT p_batch_id, v_source, 'LED-002', r.severity, r.area, l.row_no, l.lead_code,
         'caricato con review_status = PRIVACY_REVIEW (decisione BAD B-34), escluso da KPI e portale', 'LOADED_FLAGGED'
    FROM _lead l CROSS JOIN dq.rule r
   WHERE r.rule_code = 'LED-002' AND l.block_rule IS NULL AND l.is_minor
  ON CONFLICT DO NOTHING;
  PERFORM dq.add_anomaly(p_batch_id, 'LED-001', l.row_no, l.lead_code, '{}')
     FROM _lead l WHERE l.block_rule IS NULL
      AND EXISTS (SELECT 1 FROM _lead o WHERE o.row_no <> l.row_no AND o.stand_edition_id = l.stand_edition_id AND o.email_hash = l.email_hash);
  PERFORM dq.add_anomaly(p_batch_id, 'LED-003', l.row_no, l.lead_code, jsonb_build_object('motivo', 'consenso vuoto: caricato come NO'))
     FROM _lead l WHERE l.block_rule IS NULL AND l.consent_raw IS NULL;
  PERFORM dq.add_anomaly(p_batch_id, 'LED-003', NULL, 'LEAD_2025',
          jsonb_build_object('motivo', 'consenso uniforme, nessuna prova',
                             'si', (SELECT count(*) FROM _lead WHERE consent_raw), 'vuoti', (SELECT count(*) FROM _lead WHERE consent_raw IS NULL)));
  PERFORM dq.add_anomaly(p_batch_id, 'LED-006', l.row_no, l.lead_code, '{}')
     FROM _lead l WHERE l.block_rule IS NULL AND l.interest_id IS NULL;

  INSERT INTO core.stand_lead (lead_code, stand_edition_id, exhibitor_id, captured_at, email_hash, age_band_id, province_id,
                               interest_id, marketing_consent, is_qualified, review_status, source_id, import_batch_id)
  SELECT lead_code, stand_edition_id, exhibitor_id, captured_at, email_hash, age_band_id, province_id,
         interest_id, coalesce(consent_raw, false), false,
         CASE WHEN is_minor THEN 'PRIVACY_REVIEW' ELSE 'OK' END, v_source, p_batch_id
    FROM _lead WHERE block_rule IS NULL
  ON CONFLICT (lead_code) DO NOTHING;

  -- LED-004: email ridotte a hash, originali rimosse dallo staging.
  UPDATE staging.stg_stand_lead SET email = NULL WHERE batch_id = p_batch_id;
  PERFORM dq.add_anomaly(p_batch_id, 'LED-004', NULL, 'LEAD_2025',
          jsonb_build_object('email_ridotte_a_hash', (SELECT count(*) FROM _lead WHERE email_hash IS NOT NULL)));

  UPDATE dq.import_batch
     SET rows_loaded = (SELECT count(*) FROM core.stand_lead WHERE import_batch_id = p_batch_id),
         rows_quarantined = (SELECT count(DISTINCT source_row_no) FROM dq.quarantine WHERE batch_id = p_batch_id),
         rows_rejected = 0
   WHERE batch_id = p_batch_id;
  CALL dq.finish_batch(p_batch_id);
END $$;

COMMENT ON PROCEDURE dq.load_stand_lead_batch(bigint, text) IS
 'Carica contatti_stand_2025.csv (V7, team BAD): email solo come sha256(sale||email), staging svuotato, minorenni in PRIVACY_REVIEW.';

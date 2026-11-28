-- =====================================================================
-- ARCADE Milano - V6: ingestione controllata del file commerciale
-- (ARCADE_Commerciale.xlsx: espositori, planimetria, listino 2026,
--  contratti 2024-2025 e righe contratto).
-- Autore: team BAD (8/11/2026), stesso contratto operativo della V5:
--   1. creare un dq.import_batch (sorgente XLSX_COMMERCIALE) e copiare i
--      5 fogli nelle tabelle staging.stg_exhibitor, stg_stand,
--      stg_price_list_item, stg_contract, stg_contract_line;
--   2. CALL dq.load_commercial_batch(batch_id, mappa_alias, utente);
--   3. leggere dq.v_import_quality_report.
-- Non crea tabelle e non cambia lo schema: solo funzioni e procedure.
-- Si puo' rilanciare (CREATE OR REPLACE).
--
-- Numerazione righe: un file = un batch, ma i fogli sono 5 e dq.quarantine
-- e' unica per (batch, riga, regola). Per non far collidere le righe dei
-- fogli, row_no = offset del foglio + riga Excel:
--   Espositori 10000+n, Planimetria 20000+n, Listino 30000+n,
--   Contratti 40000+n, Righe_contratto 50000+n.
--
-- Cosa NON fa (decisioni non prese): prelazioni 2026, stato delle
-- sponsorizzazioni oltre "SOLD", utenti e ruoli applicativi.
-- =====================================================================

-- Nota: il codice usa solo caratteri ASCII (chr(178) = '²', chr(204) = 'Ì'), cosi' funziona anche
-- se il file viene eseguito da un psql Windows con codifica della console diversa da UTF-8.

-- Normalizzazione delle ragioni sociali (core.exhibitor.legal_name_norm e
-- core.exhibitor_alias.alias_norm): maiuscolo, senza punteggiatura, senza
-- forma giuridica. "Bussola Gear S.r.l.s." -> "BUSSOLA GEAR".
CREATE OR REPLACE FUNCTION dq.norm_company(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT NULLIF(btrim(regexp_replace(
           regexp_replace(
             regexp_replace(replace(upper(coalesce(p_value, '')), '.', ''), '[^A-Z0-9 ]', '', 'g'),
             '(^| )(SRLS|SRL|SPA|SNC|SAS|APS|LTD|GMBH|SA)(?= |$)', '', 'g'),
           '[[:space:]]+', ' ', 'g')), '')
$$;

CREATE OR REPLACE FUNCTION dq.try_bool(p_value text)
RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE dq.norm_text(p_value)
           WHEN 'TRUE' THEN true WHEN '1' THEN true WHEN 'SI' THEN true WHEN 'S' || chr(204) THEN true WHEN 'YES' THEN true
           WHEN 'FALSE' THEN false WHEN '0' THEN false WHEN 'NO' THEN false END
$$;

CREATE OR REPLACE PROCEDURE dq.load_commercial_batch(
  p_batch_id     bigint,
  p_alias_map    jsonb DEFAULT NULL,   -- [{"nome":"Bussola Gears.","esp":"ESP013","score":0.96}, ...] gia' confermati
  p_confirmed_by text  DEFAULT NULL)   -- core.app_user.username di chi ha confermato la mappa
LANGUAGE plpgsql AS $$
DECLARE
  v_source smallint; v_user integer; v_ed2026 smallint;
  v_deposit numeric; v_days smallint; v_preempt date; v_note text;
  v_read integer; v_loaded integer; v_quar integer; v_rej integer;
BEGIN
  SELECT b.source_id INTO v_source
    FROM dq.import_batch b JOIN core.data_source s ON s.source_id = b.source_id
   WHERE b.batch_id = p_batch_id AND b.status = 'RUNNING' AND s.kind = 'COMMERCIAL_XLSX';
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % must be RUNNING COMMERCIAL_XLSX', p_batch_id; END IF;

  IF p_alias_map IS NOT NULL AND jsonb_array_length(p_alias_map) > 0 THEN
    SELECT user_id INTO v_user FROM core.app_user WHERE username = p_confirmed_by;
    IF v_user IS NULL THEN
      RAISE EXCEPTION 'mappa alias senza utente valido: % non esiste in core.app_user', p_confirmed_by;
    END IF;
  END IF;

  SELECT (SELECT count(*) FROM staging.stg_exhibitor       WHERE batch_id = p_batch_id)
       + (SELECT count(*) FROM staging.stg_stand           WHERE batch_id = p_batch_id)
       + (SELECT count(*) FROM staging.stg_price_list_item WHERE batch_id = p_batch_id)
       + (SELECT count(*) FROM staging.stg_contract        WHERE batch_id = p_batch_id)
       + (SELECT count(*) FROM staging.stg_contract_line   WHERE batch_id = p_batch_id)
    INTO v_read;
  UPDATE dq.import_batch SET rows_read = v_read WHERE batch_id = p_batch_id;

  -- 1. ESPOSITORI ---------------------------------------------------------
  INSERT INTO core.exhibitor_category (name)
  SELECT DISTINCT dq.clean_text(settore) FROM staging.stg_exhibitor
   WHERE batch_id = p_batch_id AND dq.clean_text(settore) IS NOT NULL
  ON CONFLICT (name) DO NOTHING;

  INSERT INTO core.exhibitor (exhibitor_code, legal_name, legal_name_norm, vat_number, category_id, city)
  SELECT dq.norm_text(s.id_espositore), dq.clean_text(s.ragione_sociale), dq.norm_company(s.ragione_sociale),
         dq.norm_text(s.partita_iva), c.category_id, dq.clean_text(s.citta)
    FROM staging.stg_exhibitor s
    JOIN core.exhibitor_category c ON c.name = dq.clean_text(s.settore)
   WHERE s.batch_id = p_batch_id
  ON CONFLICT (exhibitor_code) DO NOTHING;

  INSERT INTO core.exhibitor_contact (exhibitor_id, full_name, email, is_primary)
  SELECT e.exhibitor_id, dq.clean_text(s.referente), lower(dq.clean_text(s.email_referente)), true
    FROM staging.stg_exhibitor s
    JOIN core.exhibitor e ON e.exhibitor_code = dq.norm_text(s.id_espositore)
   WHERE s.batch_id = p_batch_id AND dq.clean_text(s.referente) IS NOT NULL AND dq.clean_text(s.email_referente) IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM core.exhibitor_contact x WHERE x.exhibitor_id = e.exhibitor_id AND x.is_primary);

  -- 2. STAND E OCCUPAZIONE PER EDIZIONE -----------------------------------
  INSERT INTO core.stand (stand_code, pavilion_id, sqm, position_type, first_edition_id)
  SELECT dq.norm_text(s.codice_stand), p.pavilion_id, dq.try_numeric(s.mq), dq.norm_text(s.posizione), e.edition_id
    FROM staging.stg_stand s
    JOIN core.pavilion p ON p.code = dq.norm_text(s.padiglione)
    JOIN core.edition  e ON e.year = dq.try_numeric(s.attivo_dal)::smallint
   WHERE s.batch_id = p_batch_id
  ON CONFLICT (stand_code) DO NOTHING;

  -- Uno stand esiste in ogni edizione a partire da attivo_dal (2024: 115, 2025 e 2026: 130).
  INSERT INTO core.stand_edition (stand_id, edition_id)
  SELECT st.stand_id, e.edition_id
    FROM core.stand st
    JOIN core.edition fe ON fe.edition_id = st.first_edition_id
    JOIN core.edition e  ON e.year >= fe.year
  ON CONFLICT (stand_id, edition_id) DO NOTHING;

  -- 3. LISTINO 2026 (fornito dal cliente) ---------------------------------
  SELECT edition_id INTO v_ed2026 FROM core.edition WHERE year = 2026;
  SELECT dq.try_numeric(prezzo_unitario_eur), dq.clean_text(note) INTO v_deposit, v_note
    FROM staging.stg_price_list_item WHERE batch_id = p_batch_id AND dq.norm_text(codice) = 'COND-ACCONTO';
  v_days := (regexp_match(coalesce(v_note, ''), '([0-9]+) giorni'))[1]::smallint;
  SELECT CASE WHEN m IS NOT NULL THEN make_date(m[3]::int,
           array_position(ARRAY['gennaio','febbraio','marzo','aprile','maggio','giugno','luglio',
                                'agosto','settembre','ottobre','novembre','dicembre'], lower(m[2])), m[1]::int) END
    INTO v_preempt
    FROM (SELECT regexp_match(dq.clean_text(note), '([0-9]{1,2}) ([A-Za-z]+) ([0-9]{4})') AS m
            FROM staging.stg_price_list_item WHERE batch_id = p_batch_id AND dq.norm_text(codice) = 'COND-PRELAZ') x;

  INSERT INTO core.price_list (edition_id, origin, status, deposit_pct, balance_days_before, preemption_deadline, notes)
  VALUES (v_ed2026, 'CLIENT_LIST', 'PUBLISHED', v_deposit, v_days, v_preempt, 'Listino_2026 di ARCADE_Commerciale.xlsx')
  ON CONFLICT (edition_id) DO NOTHING;

  DROP TABLE IF EXISTS _item;
  CREATE TEMP TABLE _item ON COMMIT DROP AS
  SELECT s.row_no, dq.norm_text(s.codice) AS code, dq.clean_text(s.voce) AS name,
         CASE WHEN dq.norm_text(s.codice) LIKE 'SPAZIO-%' THEN 'SPACE'
              WHEN dq.norm_text(s.codice) LIKE 'MAGG-%'   THEN 'SURCHARGE'
              WHEN dq.norm_text(s.codice) LIKE 'SP-%'     THEN 'SPONSORSHIP'
              WHEN dq.norm_text(s.codice) LIKE 'EX-%'     THEN 'EXTRA' END AS item_type,
         CASE WHEN dq.norm_text(s.unita) IN ('M' || chr(178),'M2','MQ')  THEN 'SQM'
              WHEN dq.norm_text(s.unita) LIKE '%SU AREA%'    THEN 'PCT_OF_SPACE'
              WHEN dq.norm_text(s.unita) = 'PACCHETTO'       THEN 'PACKAGE'
              WHEN dq.norm_text(s.unita) IN ('CAD.','CAD')   THEN 'EACH' END AS unit,
         dq.try_numeric(s.prezzo_unitario_eur) AS value,
         dq.try_numeric(s.disponibilita) AS max_q, dq.clean_text(s.note) AS notes
    FROM staging.stg_price_list_item s
   WHERE s.batch_id = p_batch_id AND dq.norm_text(s.codice) NOT LIKE 'COND-%';
  IF EXISTS (SELECT 1 FROM _item WHERE item_type IS NULL OR unit IS NULL OR value IS NULL) THEN
    RAISE EXCEPTION 'listino 2026: voci con tipo, unita o prezzo non interpretabili: %',
      (SELECT string_agg(code, ', ') FROM _item WHERE item_type IS NULL OR unit IS NULL OR value IS NULL);
  END IF;

  INSERT INTO core.price_item (price_list_id, code, name, item_type, unit, unit_price, pct, pavilion_id, position_type, max_quantity, notes)
  SELECT pl.price_list_id, i.code, i.name, i.item_type, i.unit,
         CASE WHEN i.unit = 'PCT_OF_SPACE' THEN NULL ELSE i.value END,
         CASE WHEN i.unit = 'PCT_OF_SPACE' THEN i.value END,
         CASE WHEN i.item_type = 'SPACE' THEN (SELECT pavilion_id FROM core.pavilion WHERE code = split_part(i.code, '-', 2)) END,
         CASE WHEN i.item_type = 'SURCHARGE' THEN split_part(i.code, '-', 2) END,
         i.max_q::smallint, i.notes
    FROM _item i JOIN core.price_list pl ON pl.edition_id = v_ed2026
  ON CONFLICT (price_list_id, code) DO NOTHING;

  -- 4. CONTRATTI: lettura e risoluzione dell'espositore ---------------------
  -- Alias confermati a mano (contratti 2024 con nome non riconducibile in modo esatto).
  IF v_user IS NOT NULL THEN
    INSERT INTO core.exhibitor_alias (exhibitor_id, alias_norm, source_id, match_method, match_score, confirmed_by, confirmed_at)
    SELECT e.exhibitor_id, dq.norm_company(m->>'nome'), v_source, 'FUZZY_REVIEWED', (m->>'score')::numeric, v_user, now()
      FROM jsonb_array_elements(p_alias_map) m
      JOIN core.exhibitor e ON e.exhibitor_code = dq.norm_text(m->>'esp')
    ON CONFLICT (alias_norm) DO NOTHING;
  END IF;

  DROP TABLE IF EXISTS _ctr;
  CREATE TEMP TABLE _ctr ON COMMIT DROP AS
  SELECT s.row_no, dq.norm_text(s.id_contratto) AS contract_number, ed.edition_id, ed.year,
         dq.norm_text(s.id_espositore) AS exh_code, dq.clean_text(s.ragione_sociale) AS raw_name,
         dq.norm_company(s.ragione_sociale) AS name_norm, dq.norm_text(s.codice_stand) AS stand_code,
         dq.try_date(s.data_firma) AS signed_on, dq.try_numeric(s.imponibile_listino_eur) AS list_amount,
         dq.try_numeric(s.sconto_pct) AS discount_pct, dq.try_numeric(s.imponibile_eur) AS net_amount,
         dq.try_date(s.acconto_scadenza) AS dep_due, dq.try_date(s.acconto_pagato_il) AS dep_paid,
         dq.try_date(s.saldo_scadenza) AS bal_due, dq.try_date(s.saldo_pagato_il) AS bal_paid,
         coalesce(dq.try_bool(s.rinnovo), false) AS is_renewal, to_jsonb(s) AS raw_record,
         NULL::integer AS exhibitor_id, NULL::text AS match_method, NULL::integer AS stand_edition_id,
         NULL::text AS block_rule
    FROM staging.stg_contract s
    LEFT JOIN core.edition ed ON ed.year = dq.try_numeric(s.edizione)::smallint
   WHERE s.batch_id = p_batch_id;

  UPDATE _ctr c SET exhibitor_id = e.exhibitor_id, match_method = 'CODE'
    FROM core.exhibitor e WHERE c.exh_code IS NOT NULL AND e.exhibitor_code = c.exh_code;
  UPDATE _ctr c SET exhibitor_id = e.exhibitor_id,
                    match_method = CASE WHEN c.raw_name = e.legal_name THEN 'EXACT' ELSE 'NORMALIZED' END
    FROM core.exhibitor e WHERE c.exhibitor_id IS NULL AND c.name_norm = e.legal_name_norm;
  UPDATE _ctr c SET exhibitor_id = a.exhibitor_id, match_method = a.match_method
    FROM core.exhibitor_alias a WHERE c.exhibitor_id IS NULL AND a.alias_norm = c.name_norm;
  UPDATE _ctr c SET stand_edition_id = se.stand_edition_id
    FROM core.stand st JOIN core.stand_edition se ON se.stand_id = st.stand_id
   WHERE st.stand_code = c.stand_code AND se.edition_id = c.edition_id;

  -- Blocchi (in ordine di gravita'): nessuno di questi contratti entra nel core.
  UPDATE _ctr SET block_rule = 'COM-002' WHERE exhibitor_id IS NULL;
  UPDATE _ctr SET block_rule = 'COM-005' WHERE block_rule IS NULL AND stand_edition_id IS NULL;
  UPDATE _ctr c SET block_rule = 'COM-003'
   WHERE block_rule IS NULL AND abs(c.list_amount - coalesce((
         SELECT sum(dq.try_numeric(l.importo_eur)) FROM staging.stg_contract_line l
          WHERE l.batch_id = p_batch_id AND dq.norm_text(l.id_contratto) = c.contract_number), -1)) > 0.01;
  UPDATE _ctr c SET block_rule = 'COM-004'
   WHERE block_rule IS NULL AND (
         EXISTS (SELECT 1 FROM _ctr o WHERE o.stand_edition_id = c.stand_edition_id AND o.row_no <> c.row_no AND o.block_rule IS NULL)
      OR EXISTS (SELECT 1 FROM core.contract_stand cs JOIN core.contract k ON k.contract_id = cs.contract_id
                  WHERE cs.stand_edition_id = c.stand_edition_id AND cs.released_at IS NULL AND k.contract_number <> c.contract_number));

  PERFORM dq.add_anomaly(p_batch_id, block_rule, row_no, contract_number,
          jsonb_build_object('ragione_sociale', raw_name, 'stand', stand_code))
     FROM _ctr WHERE block_rule IS NOT NULL;
  INSERT INTO dq.quarantine (batch_id, source_id, source_row_no, raw_record, reason_rule)
  SELECT p_batch_id, v_source, row_no, raw_record, block_rule FROM _ctr WHERE block_rule IN ('COM-002','COM-003','COM-005')
  ON CONFLICT DO NOTHING;
  -- Le righe dei contratti bloccati seguono il contratto: in quarantena con la stessa regola, mai perse.
  INSERT INTO dq.quarantine (batch_id, source_id, source_row_no, raw_record, reason_rule)
  SELECT p_batch_id, v_source, l.row_no, to_jsonb(l), c.block_rule
    FROM staging.stg_contract_line l JOIN _ctr c ON c.contract_number = dq.norm_text(l.id_contratto)
   WHERE l.batch_id = p_batch_id AND c.block_rule IN ('COM-002','COM-003','COM-005')
  ON CONFLICT DO NOTHING;

  -- Contratti 2024 risolti per nome (nessun id ne' P.IVA nel file): caricati e segnalati.
  PERFORM dq.add_anomaly(p_batch_id, 'COM-001', row_no, contract_number,
          jsonb_build_object('ragione_sociale', raw_name, 'metodo', match_method))
     FROM _ctr WHERE block_rule IS NULL AND match_method <> 'CODE';
  INSERT INTO core.exhibitor_alias (exhibitor_id, alias_norm, source_id, match_method, match_score)
  SELECT DISTINCT ON (name_norm) exhibitor_id, name_norm, v_source, match_method, 1
    FROM _ctr WHERE block_rule IS NULL AND match_method IN ('EXACT','NORMALIZED')
  ON CONFLICT (alias_norm) DO NOTHING;

  -- 5. CONTRATTI E ASSEGNAZIONE DEGLI STAND --------------------------------
  INSERT INTO core.contract (contract_number, edition_id, exhibitor_id, status, signed_on, list_amount,
                             discount_pct, net_amount, is_renewal, source_id, import_batch_id)
  SELECT contract_number, edition_id, exhibitor_id, 'SIGNED', signed_on, list_amount,
         discount_pct, net_amount, is_renewal, v_source, p_batch_id
    FROM _ctr WHERE block_rule IS NULL
  ON CONFLICT (contract_number) DO NOTHING;

  INSERT INTO core.contract_stand (contract_id, stand_edition_id, edition_id, assigned_at)
  SELECT k.contract_id, c.stand_edition_id, c.edition_id, (c.signed_on::timestamp AT TIME ZONE 'Europe/Rome')
    FROM _ctr c JOIN core.contract k ON k.contract_number = c.contract_number
   WHERE c.block_rule IS NULL
     AND NOT EXISTS (SELECT 1 FROM core.contract_stand x WHERE x.contract_id = k.contract_id AND x.released_at IS NULL);

  UPDATE core.stand_edition se SET commercial_status = 'SOLD'
   WHERE se.commercial_status <> 'SOLD'
     AND EXISTS (SELECT 1 FROM core.contract_stand cs JOIN core.contract k ON k.contract_id = cs.contract_id
                  WHERE cs.stand_edition_id = se.stand_edition_id AND cs.released_at IS NULL AND k.status = 'SIGNED');

  -- 6. RIGHE: tipo, voce di listino, stand -------------------------------------
  DROP TABLE IF EXISTS _line;
  CREATE TEMP TABLE _line ON COMMIT DROP AS
  SELECT l.row_no, c.contract_number, c.edition_id, c.block_rule, dq.try_numeric(l.riga)::smallint AS line_no,
         dq.norm_text(l.codice_voce) AS src_code, dq.clean_text(l.descrizione) AS description,
         dq.try_numeric(l.quantita) AS quantity, dq.try_numeric(l.prezzo_unitario_eur) AS unit_price,
         dq.try_numeric(l.importo_eur) AS amount, p.code AS pavilion_code, st.position_type,
         CASE WHEN dq.norm_text(l.codice_voce) = 'SPAZIO' THEN 'SPACE'
              WHEN dq.norm_text(l.codice_voce) = 'MAGG'   THEN 'SURCHARGE'
              WHEN dq.norm_text(l.codice_voce) LIKE 'SP-%' THEN 'SPONSORSHIP'
              WHEN dq.norm_text(l.codice_voce) LIKE 'EX-%' THEN 'EXTRA' END AS line_type,
         CASE WHEN dq.norm_text(l.codice_voce) = 'SPAZIO' THEN 'SPAZIO-' || p.code
              WHEN dq.norm_text(l.codice_voce) = 'MAGG'   THEN 'MAGG-' || st.position_type
              ELSE dq.norm_text(l.codice_voce) END AS item_code
    FROM staging.stg_contract_line l
    JOIN _ctr c ON c.contract_number = dq.norm_text(l.id_contratto)
    LEFT JOIN core.stand st ON st.stand_code = c.stand_code
    LEFT JOIN core.pavilion p ON p.pavilion_id = st.pavilion_id
   WHERE l.batch_id = p_batch_id;
  IF EXISTS (SELECT 1 FROM _line WHERE line_type IS NULL OR line_no IS NULL OR quantity IS NULL OR unit_price IS NULL OR amount IS NULL) THEN
    RAISE EXCEPTION 'righe contratto non interpretabili: %',
      (SELECT string_agg(contract_number || '/' || coalesce(line_no::text, '?'), ', ') FROM _line
        WHERE line_type IS NULL OR line_no IS NULL OR quantity IS NULL OR unit_price IS NULL OR amount IS NULL);
  END IF;
  -- Area su cui si calcola la maggiorazione (stesso contratto).
  ALTER TABLE _line ADD COLUMN pct numeric;
  UPDATE _line m SET pct = round(m.amount / NULLIF(a.amount, 0), 4)
    FROM _line a WHERE m.line_type = 'SURCHARGE' AND a.line_type = 'SPACE' AND a.contract_number = m.contract_number;

  -- 7. LISTINI 2024/2025 RICOSTRUITI DALLE RIGHE (AS-06, da validare: D6/Q-04) ---
  INSERT INTO core.price_list (edition_id, origin, status, deposit_pct, balance_days_before, notes)
  SELECT DISTINCT edition_id, 'RECONSTRUCTED_FROM_CONTRACTS', 'ARCHIVED', v_deposit, v_days,
         'Ricostruito dalle righe contratto (AS-06), da validare (D6/Q-04). Acconto e saldo assunti uguali al 2026 (AS-04).'
    FROM _line WHERE edition_id <> v_ed2026
  ON CONFLICT (edition_id) DO NOTHING;

  -- Prezzo di listino ricostruito = valore piu' frequente nelle righe (oggi e' unico per ogni voce).
  INSERT INTO core.price_item (price_list_id, code, name, item_type, unit, unit_price, pct, pavilion_id, position_type, notes)
  SELECT pl.price_list_id, r.item_code,
         coalesce(i26.name, CASE r.line_type WHEN 'SPACE' THEN 'Area espositiva ' || r.item_code
                                             WHEN 'SURCHARGE' THEN 'Maggiorazione stand ' || lower(r.position_type)
                                             ELSE r.description END),
         r.line_type,
         CASE r.line_type WHEN 'SPACE' THEN 'SQM' WHEN 'SURCHARGE' THEN 'PCT_OF_SPACE'
                          ELSE coalesce(i26.unit, CASE r.line_type WHEN 'SPONSORSHIP' THEN 'PACKAGE' ELSE 'EACH' END) END,
         CASE WHEN r.line_type <> 'SURCHARGE' THEN r.v END,
         CASE WHEN r.line_type = 'SURCHARGE' THEN r.v END,
         CASE WHEN r.line_type = 'SPACE' THEN (SELECT pavilion_id FROM core.pavilion WHERE code = r.pavilion_code) END,
         CASE WHEN r.line_type = 'SURCHARGE' THEN r.position_type END,
         'Ricostruito dalle righe contratto'
    FROM (SELECT edition_id, item_code, line_type, min(pavilion_code) AS pavilion_code, min(position_type) AS position_type,
                 min(description) AS description,
                 mode() WITHIN GROUP (ORDER BY CASE WHEN line_type = 'SURCHARGE' THEN pct ELSE unit_price END) AS v
            FROM _line WHERE edition_id <> v_ed2026
           GROUP BY edition_id, item_code, line_type) r
    JOIN core.price_list pl ON pl.edition_id = r.edition_id
    LEFT JOIN core.price_item i26 ON i26.code = r.item_code
          AND i26.price_list_id = (SELECT price_list_id FROM core.price_list WHERE edition_id = v_ed2026)
  ON CONFLICT (price_list_id, code) DO NOTHING;

  -- Riga con prezzo diverso dal listino della sua edizione: caricata e segnalata.
  PERFORM dq.add_anomaly(p_batch_id, 'COM-008', l.row_no, l.contract_number || '/' || l.line_no,
          jsonb_build_object('voce', l.item_code, 'riga', CASE WHEN l.line_type = 'SURCHARGE' THEN l.pct ELSE l.unit_price END,
                             'listino', coalesce(pi.unit_price, pi.pct)))
     FROM _line l JOIN core.price_list pl ON pl.edition_id = l.edition_id
     JOIN core.price_item pi ON pi.price_list_id = pl.price_list_id AND pi.code = l.item_code
    WHERE l.block_rule IS NULL
      AND (CASE WHEN l.line_type = 'SURCHARGE' THEN abs(l.pct - pi.pct) > 0.0001 ELSE l.unit_price <> pi.unit_price END);

  -- 8. RIGHE CONTRATTO E SPONSORIZZAZIONI ---------------------------------------
  INSERT INTO core.contract_line (contract_id, line_no, line_type, price_item_id, source_item_code, description,
                                  quantity, unit_price, amount, contract_stand_id)
  SELECT k.contract_id, l.line_no, l.line_type, pi.price_item_id, l.src_code, l.description,
         l.quantity, l.unit_price, l.amount,
         CASE WHEN l.line_type IN ('SPACE','SURCHARGE') THEN cs.contract_stand_id END
    FROM _line l
    JOIN core.contract k ON k.contract_number = l.contract_number
    JOIN core.price_list pl ON pl.edition_id = l.edition_id
    JOIN core.price_item pi ON pi.price_list_id = pl.price_list_id AND pi.code = l.item_code
    LEFT JOIN core.contract_stand cs ON cs.contract_id = k.contract_id AND cs.released_at IS NULL
   WHERE l.block_rule IS NULL
  ON CONFLICT (contract_id, line_no) DO NOTHING;

  INSERT INTO core.sponsorship (contract_line_id)
  SELECT l.contract_line_id FROM core.contract_line l JOIN core.contract k ON k.contract_id = l.contract_id
   WHERE k.import_batch_id = p_batch_id AND l.line_type = 'SPONSORSHIP'
  ON CONFLICT (contract_line_id) DO NOTHING;

  -- 9. PAGAMENTI: importi derivati dalla regola acconto/saldo (AS-04) -------------
  -- Il file da' solo le date. Dovuto = acconto% x netto e resto a saldo; pagato = dovuto, marcato come assunto.
  INSERT INTO core.payment (contract_id, kind, due_on, due_amount, due_amount_basis, paid_on, paid_amount, paid_amount_is_assumed)
  SELECT k.contract_id, x.kind, x.due_on, x.due_amount, 'RULE_DERIVED', x.paid_on,
         CASE WHEN x.paid_on IS NOT NULL THEN x.due_amount END, x.paid_on IS NOT NULL
    FROM _ctr c
    JOIN core.contract k ON k.contract_number = c.contract_number
    JOIN core.price_list pl ON pl.edition_id = c.edition_id
    CROSS JOIN LATERAL (VALUES
      ('DEPOSIT', c.dep_due, round(c.net_amount * pl.deposit_pct, 2), c.dep_paid),
      ('BALANCE', c.bal_due, c.net_amount - round(c.net_amount * pl.deposit_pct, 2), c.bal_paid)
    ) AS x(kind, due_on, due_amount, paid_on)
   WHERE c.block_rule IS NULL AND x.due_on IS NOT NULL
  ON CONFLICT (contract_id, kind) WHERE kind IN ('DEPOSIT','BALANCE') DO NOTHING;

  PERFORM dq.add_anomaly(p_batch_id, 'COM-006', c.row_no, c.contract_number || '|' || x.kind, '{}')
     FROM _ctr c CROSS JOIN LATERAL (VALUES ('DEPOSIT', c.dep_paid), ('BALANCE', c.bal_paid)) x(kind, paid_on)
    WHERE c.block_rule IS NULL AND x.paid_on IS NULL;
  PERFORM dq.add_anomaly(p_batch_id, 'COM-010', c.row_no, c.contract_number || '|' || x.kind,
          jsonb_build_object('scadenza', x.due_on, 'pagato', x.paid_on))
     FROM _ctr c CROSS JOIN LATERAL (VALUES ('DEPOSIT', c.dep_due, c.dep_paid), ('BALANCE', c.bal_due, c.bal_paid)) x(kind, due_on, paid_on)
    WHERE c.block_rule IS NULL AND x.paid_on > x.due_on;
  PERFORM dq.add_anomaly(p_batch_id, 'COM-007', NULL, 'XLSX_COMMERCIALE',
          jsonb_build_object('pagamenti_assunti', (SELECT count(*) FROM core.payment p JOIN core.contract k USING (contract_id)
                                                     WHERE k.import_batch_id = p_batch_id AND p.paid_amount_is_assumed)));

  -- 10. RINNOVI: flag del cliente senza contratto precedente dello stesso espositore --
  PERFORM dq.add_anomaly(p_batch_id, 'COM-009', c.row_no, c.contract_number, '{}')
     FROM _ctr c JOIN core.contract k ON k.contract_number = c.contract_number
    WHERE c.block_rule IS NULL AND k.is_renewal
      AND NOT EXISTS (SELECT 1 FROM core.contract p JOIN core.edition pe ON pe.edition_id = p.edition_id
                       WHERE p.exhibitor_id = k.exhibitor_id AND pe.year = c.year - 1);

  -- 11. CONTEGGI DEL BATCH (GEN-001: letti = caricati + quarantena + scartati) ----
  SELECT count(DISTINCT source_row_no) INTO v_quar FROM dq.quarantine WHERE batch_id = p_batch_id;
  SELECT count(*) INTO v_rej FROM _ctr WHERE block_rule = 'COM-004';
  v_rej := v_rej + (SELECT count(*) FROM _line WHERE block_rule = 'COM-004');
  SELECT (SELECT count(*) FROM staging.stg_exhibitor s WHERE s.batch_id = p_batch_id
             AND EXISTS (SELECT 1 FROM core.exhibitor e WHERE e.exhibitor_code = dq.norm_text(s.id_espositore)))
       + (SELECT count(*) FROM staging.stg_stand s WHERE s.batch_id = p_batch_id
             AND EXISTS (SELECT 1 FROM core.stand t WHERE t.stand_code = dq.norm_text(s.codice_stand)))
       + (SELECT count(*) FROM staging.stg_price_list_item s WHERE s.batch_id = p_batch_id
             AND (dq.norm_text(s.codice) LIKE 'COND-%' OR EXISTS (SELECT 1 FROM core.price_item i JOIN core.price_list pl USING (price_list_id)
                    WHERE pl.edition_id = v_ed2026 AND i.code = dq.norm_text(s.codice))))
       + (SELECT count(*) FROM _ctr c WHERE EXISTS (SELECT 1 FROM core.contract k WHERE k.contract_number = c.contract_number))
       + (SELECT count(*) FROM _line l WHERE EXISTS (SELECT 1 FROM core.contract k JOIN core.contract_line x USING (contract_id)
                                                     WHERE k.contract_number = l.contract_number AND x.line_no = l.line_no))
    INTO v_loaded;
  UPDATE dq.import_batch SET rows_loaded = v_loaded, rows_quarantined = v_quar, rows_rejected = v_rej
   WHERE batch_id = p_batch_id;
  IF v_read <> v_loaded + v_quar + v_rej THEN
    PERFORM dq.add_anomaly(p_batch_id, 'GEN-001', NULL, 'XLSX_COMMERCIALE',
            jsonb_build_object('letti', v_read, 'caricati', v_loaded, 'quarantena', v_quar, 'scartati', v_rej));
  END IF;
  CALL dq.finish_batch(p_batch_id);
END $$;

COMMENT ON PROCEDURE dq.load_commercial_batch(bigint, jsonb, text) IS
 'Carica ARCADE_Commerciale.xlsx dallo staging al core (V6, team BAD). Contratti 2024 risolti per nome; i nomi non risolti vanno in quarantena COM-002 salvo alias confermati passati in p_alias_map.';

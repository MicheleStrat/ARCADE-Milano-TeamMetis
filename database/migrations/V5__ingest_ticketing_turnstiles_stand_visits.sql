-- =====================================================================
-- ARCADE Milano - V5: ingestione controllata di biglietteria, tornelli
-- e visite stand.  Le procedure leggono SOLO staging e scrivono core/DQ.
--
-- Contratto operativo:
--   1. creare un dq.import_batch e copiare il CSV nella tabella staging;
--   2. CALL dq.load_ticket_batch(...), dq.load_gate_batch(...) oppure
--      dq.load_stand_visit_batch(...);
--   3. leggere dq.v_import_quality_report prima di usare analytics.
--
-- Un batch deve essere RUNNING. Le righe bloccanti restano in staging e
-- vengono copiate in dq.quarantine; le altre entrano nel core con ogni
-- anomalia non bloccante conservata in dq.anomaly.
-- =====================================================================

-- Convenzioni di scrittura:
--  * Nelle espressioni regolari NON si usano le scorciatoie con backslash (\d, \s, \.): con
--    standard_conforming_strings attivo (default) '\\d' significa "backslash + d" e non corrisponde a nulla.
--    Si usano [0-9], [[:space:]] e [.].
--  * Le date italiane GG/MM/AAAA si interpretano sempre con formato esplicito, mai con DateStyle:
--    con il DateStyle predefinito (MDY) '05/12/2025' verrebbe letto come 12 maggio senza errore.

CREATE OR REPLACE FUNCTION dq.clean_text(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT NULLIF(btrim(regexp_replace(p_value, '[[:space:]]+', ' ', 'g')), '')
$$;

CREATE OR REPLACE FUNCTION dq.norm_text(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT upper(dq.clean_text(p_value))
$$;

CREATE OR REPLACE FUNCTION dq.try_date(p_value text)
RETURNS date LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE v text := dq.clean_text(p_value);
BEGIN
  IF v IS NULL THEN RETURN NULL; END IF;
  IF v ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RETURN v::date; END IF;
  IF v ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN RETURN to_date(v, 'DD/MM/YYYY'); END IF;
  -- Seriale Excel (epoca 1899-12-30). Solo valori a 5 cifre, per non scambiare un anno o un numero qualsiasi per una data.
  IF v ~ '^[0-9]{5}([.]0+)?$' THEN RETURN DATE '1899-12-30' + trunc(v::numeric)::integer; END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION dq.try_time(p_value text)
RETURNS time LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE v text := dq.clean_text(p_value);
BEGIN
  IF v IS NULL THEN RETURN NULL; END IF;
  IF v ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$' THEN RETURN v::time; END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION dq.try_numeric(p_value text)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE v text := dq.clean_text(p_value);
BEGIN
  -- CSV italiani: 1.234,56 (la virgola e' il separatore decimale); formati con punto decimale: 1234.56.
  IF v IS NOT NULL AND position(',' IN v) > 0 THEN
    v := replace(replace(v, '.', ''), ',', '.');
  END IF;
  IF v IS NULL OR v !~ '^-?[0-9]+([.][0-9]+)?$' THEN RETURN NULL; END IF;
  RETURN v::numeric;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

-- Istanti: ISO con Z/offset = assoluto; ISO senza fuso e GG/MM/AAAA hh:mm[:ss] = ora locale della sorgente (p_timezone).
CREATE OR REPLACE FUNCTION dq.try_timestamptz(p_value text, p_timezone text)
RETURNS timestamptz LANGUAGE plpgsql STABLE PARALLEL SAFE AS $$
DECLARE v text := dq.clean_text(p_value); m text[];
BEGIN
  IF v IS NULL THEN RETURN NULL; END IF;
  IF v ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}([.][0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' THEN
    RETURN v::timestamptz;
  END IF;
  IF v ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?$' THEN
    RETURN v::timestamp AT TIME ZONE p_timezone;
  END IF;
  m := regexp_match(v, '^([0-9]{2})/([0-9]{2})/([0-9]{4})[T ]([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?$');
  IF m IS NOT NULL THEN
    RETURN make_timestamp(m[3]::int, m[2]::int, m[1]::int, m[4]::int, m[5]::int, COALESCE(m[7], '0')::int)
           AT TIME ZONE p_timezone;
  END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

-- Regola per le letture ai tornelli non interpretabili (varco, istante o esito): GAT-002 resta "fuori orario".
INSERT INTO dq.rule(rule_code, area, description, severity, default_action)
VALUES ('GAT-008', 'tornelli', 'Lettura non interpretabile (varco sconosciuto, istante o esito non validi)', 'ERROR', 'QUARANTINED')
ON CONFLICT (rule_code) DO NOTHING;

-- Registra un'anomalia usando severita', area e azione della regola in dq.rule.
-- Una regola o un batch inesistenti sono un errore di programmazione: eccezione, mai silenzio.
CREATE OR REPLACE FUNCTION dq.add_anomaly(
  p_batch_id bigint, p_rule_code text, p_row_no integer, p_record_ref text,
  p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO dq.anomaly(batch_id, source_id, rule_code, severity, entity, source_row_no, record_ref, detail, action_applied)
  SELECT b.batch_id, b.source_id, r.rule_code, r.severity, r.area, p_row_no, p_record_ref,
         NULLIF(p_detail::text, '{}'), r.default_action
    FROM dq.import_batch b CROSS JOIN dq.rule r
   WHERE b.batch_id = p_batch_id AND r.rule_code = p_rule_code
  ON CONFLICT (batch_id, rule_code, (COALESCE(source_row_no, -1)), (COALESCE(record_ref, ''))) DO NOTHING;
  IF NOT FOUND THEN
    IF NOT EXISTS (SELECT 1 FROM dq.rule WHERE rule_code = p_rule_code) THEN
      RAISE EXCEPTION 'regola DQ % inesistente', p_rule_code;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM dq.import_batch WHERE batch_id = p_batch_id) THEN
      RAISE EXCEPTION 'batch % inesistente', p_batch_id;
    END IF;
  END IF;
END $$;


CREATE OR REPLACE PROCEDURE dq.finish_batch(p_batch_id bigint)
LANGUAGE plpgsql AS $$
DECLARE v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad FROM dq.anomaly a
   JOIN dq.rule r USING (rule_code)
   WHERE a.batch_id = p_batch_id AND r.severity IN ('ERROR','CRITICAL');
  UPDATE dq.import_batch
     SET status = CASE WHEN rows_quarantined > 0 OR rows_rejected > 0 OR v_bad > 0
                       THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
         finished_at = now()
   WHERE batch_id = p_batch_id;
END $$;

-- BIGLIETTERIA ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE dq.load_ticket_batch(p_batch_id bigint)
LANGUAGE plpgsql AS $$
DECLARE v_source smallint; v_edition smallint; v_tz text;
BEGIN
  SELECT b.source_id, e.edition_id, e.timezone INTO v_source, v_edition, v_tz
  FROM dq.import_batch b JOIN core.data_source s ON s.source_id=b.source_id
  JOIN core.edition e ON e.year = right(s.code, 4)::smallint
  WHERE b.batch_id=p_batch_id AND b.status='RUNNING' AND s.kind='TICKETING';
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % must be RUNNING TICKETING with a year suffix', p_batch_id; END IF;

  UPDATE dq.import_batch SET rows_read=(SELECT count(*) FROM staging.stg_ticket WHERE batch_id=p_batch_id)
   WHERE batch_id=p_batch_id;

  DROP TABLE IF EXISTS _ticket_check;
  CREATE TEMP TABLE _ticket_check ON COMMIT DROP AS
  SELECT s.*, dq.clean_text(s.id_biglietto) AS ticket_code, dq.clean_text(s.id_ordine) AS order_code,
         dq.try_timestamptz(s.data_acquisto, v_tz) AS purchased_at,
         dq.try_date(s.giorno_valido) AS valid_day, dq.try_numeric(s.prezzo) AS price_n,
         dq.try_numeric(s.persone)::smallint AS persons_n, tt.ticket_type_id, ab.age_band_id,
         pa.province_id, dc.discount_code_id,
         CASE dq.norm_text(s.canale) WHEN 'ONLINE' THEN 'ONLINE' WHEN 'CASSA' THEN 'BOX_OFFICE'
              WHEN 'BOX OFFICE' THEN 'BOX_OFFICE' WHEN 'PARTNER' THEN 'PARTNER' WHEN 'RIVENDITORE PARTNER' THEN 'PARTNER' END AS channel_code,
         count(*) OVER (PARTITION BY dq.clean_text(s.id_biglietto)) AS duplicate_in_file
  FROM staging.stg_ticket s
  LEFT JOIN core.ticket_type_alias ta ON ta.alias_norm=dq.norm_text(s.tipo_biglietto)
  LEFT JOIN core.ticket_type tt ON tt.ticket_type_id=ta.ticket_type_id
  LEFT JOIN core.age_band ab ON ab.code=dq.clean_text(s.fascia_eta_titolare)
  LEFT JOIN core.province_alias pa ON pa.alias_norm=dq.norm_text(s.provincia)
  LEFT JOIN core.discount_code dc ON dc.code=dq.norm_text(s.codice_sconto)
  WHERE s.batch_id=p_batch_id;

  PERFORM dq.add_anomaly(p_batch_id,'TKT-001',row_no,ticket_code,jsonb_build_object('reason','duplicate ticket code'))
    FROM _ticket_check WHERE ticket_code IS NULL OR duplicate_in_file>1 OR EXISTS (SELECT 1 FROM core.ticket t WHERE t.ticket_code=_ticket_check.ticket_code AND t.import_batch_id IS DISTINCT FROM p_batch_id);
  PERFORM dq.add_anomaly(p_batch_id,'TKT-004',row_no,ticket_code,'{}') FROM _ticket_check WHERE ticket_type_id IS NULL;
  PERFORM dq.add_anomaly(p_batch_id,'TKT-005',row_no,ticket_code,'{}') FROM _ticket_check c
    WHERE valid_day IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.edition_day d WHERE d.edition_id=v_edition AND d.day_date=c.valid_day);
  PERFORM dq.add_anomaly(p_batch_id,'TKT-006',row_no,ticket_code,'{}') FROM _ticket_check
    WHERE order_code IS NULL OR purchased_at IS NULL OR channel_code IS NULL OR price_n IS NULL OR price_n<0 OR persons_n IS NULL OR persons_n<1;
  PERFORM dq.add_anomaly(p_batch_id,'TKT-005',row_no,ticket_code,jsonb_build_object('reason','valid day incompatible with ticket type'))
    FROM _ticket_check c JOIN core.ticket_type tt USING (ticket_type_id)
    WHERE (tt.is_multi_day AND c.valid_day IS NOT NULL) OR (NOT tt.is_multi_day AND c.valid_day IS NULL);
  PERFORM dq.add_anomaly(p_batch_id,'TKT-003',row_no,ticket_code,'{}') FROM _ticket_check WHERE dq.clean_text(provincia) IS NULL;
  PERFORM dq.add_anomaly(p_batch_id,'TKT-002',row_no,ticket_code,'{}') FROM _ticket_check
    WHERE dq.clean_text(provincia) IS NOT NULL AND province_id IS NOT NULL AND dq.norm_text(provincia) <> (SELECT code FROM core.province WHERE province_id=_ticket_check.province_id);
  PERFORM dq.add_anomaly(p_batch_id,'TKT-008',row_no,ticket_code,'{}') FROM _ticket_check WHERE purchased_at::date > valid_day;

  INSERT INTO dq.quarantine(batch_id,source_id,source_row_no,raw_record,reason_rule)
  SELECT p_batch_id,v_source,c.row_no,to_jsonb(c),'TKT-004' FROM _ticket_check c WHERE ticket_type_id IS NULL
  ON CONFLICT DO NOTHING;
  INSERT INTO dq.quarantine(batch_id,source_id,source_row_no,raw_record,reason_rule)
  SELECT p_batch_id,v_source,c.row_no,to_jsonb(c),'TKT-005' FROM _ticket_check c WHERE valid_day IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.edition_day d WHERE d.edition_id=v_edition AND d.day_date=c.valid_day)
  ON CONFLICT DO NOTHING;
  INSERT INTO dq.quarantine(batch_id,source_id,source_row_no,raw_record,reason_rule)
  SELECT p_batch_id,v_source,c.row_no,to_jsonb(c),'TKT-005' FROM _ticket_check c
  JOIN core.ticket_type tt USING (ticket_type_id)
  WHERE (tt.is_multi_day AND c.valid_day IS NOT NULL) OR (NOT tt.is_multi_day AND c.valid_day IS NULL)
  ON CONFLICT DO NOTHING;
  INSERT INTO dq.quarantine(batch_id,source_id,source_row_no,raw_record,reason_rule)
  SELECT p_batch_id,v_source,c.row_no,to_jsonb(c),'TKT-006' FROM _ticket_check c WHERE order_code IS NULL OR purchased_at IS NULL OR channel_code IS NULL OR price_n IS NULL OR price_n<0 OR persons_n IS NULL OR persons_n<1
  ON CONFLICT DO NOTHING;

  INSERT INTO core.ticket_order(order_code,edition_id,channel_id,purchased_at,source_id,import_batch_id)
  SELECT DISTINCT c.order_code,v_edition,ch.channel_id,c.purchased_at,v_source,p_batch_id
  FROM _ticket_check c JOIN core.sales_channel ch ON ch.code=c.channel_code
  WHERE c.ticket_code IS NOT NULL AND c.duplicate_in_file=1 AND c.ticket_type_id IS NOT NULL
    AND c.order_code IS NOT NULL AND c.purchased_at IS NOT NULL AND c.channel_code IS NOT NULL AND c.price_n>=0 AND c.persons_n>=1
    AND NOT EXISTS (SELECT 1 FROM core.ticket_type tt WHERE tt.ticket_type_id=c.ticket_type_id AND ((tt.is_multi_day AND c.valid_day IS NOT NULL) OR (NOT tt.is_multi_day AND c.valid_day IS NULL)))
    AND (c.valid_day IS NULL OR EXISTS (SELECT 1 FROM core.edition_day d WHERE d.edition_id=v_edition AND d.day_date=c.valid_day))
  ON CONFLICT (order_code) DO NOTHING;
  INSERT INTO core.ticket(ticket_code,order_id,edition_id,ticket_type_id,valid_day,price,persons,age_band_id,province_id,discount_code_id,source_id,import_batch_id)
  SELECT c.ticket_code,o.order_id,v_edition,c.ticket_type_id,c.valid_day,c.price_n,c.persons_n,c.age_band_id,c.province_id,c.discount_code_id,v_source,p_batch_id
  FROM _ticket_check c JOIN core.ticket_order o ON o.order_code=c.order_code
  WHERE c.ticket_code IS NOT NULL AND c.duplicate_in_file=1 AND c.ticket_type_id IS NOT NULL
    AND c.order_code IS NOT NULL AND c.purchased_at IS NOT NULL AND c.channel_code IS NOT NULL AND c.price_n>=0 AND c.persons_n>=1
    AND NOT EXISTS (SELECT 1 FROM core.ticket_type tt WHERE tt.ticket_type_id=c.ticket_type_id AND ((tt.is_multi_day AND c.valid_day IS NOT NULL) OR (NOT tt.is_multi_day AND c.valid_day IS NULL)))
    AND (c.valid_day IS NULL OR EXISTS (SELECT 1 FROM core.edition_day d WHERE d.edition_id=v_edition AND d.day_date=c.valid_day))
  ON CONFLICT (ticket_code) DO NOTHING;
  UPDATE dq.import_batch SET rows_loaded=(SELECT count(*) FROM core.ticket WHERE import_batch_id=p_batch_id),
    rows_quarantined=(SELECT count(DISTINCT source_row_no) FROM dq.quarantine WHERE batch_id=p_batch_id),
    rows_rejected=(SELECT count(*) FROM _ticket_check c WHERE c.ticket_code IS NULL OR c.duplicate_in_file>1 OR EXISTS (SELECT 1 FROM core.ticket t WHERE t.ticket_code=c.ticket_code AND t.import_batch_id<>p_batch_id)) WHERE batch_id=p_batch_id;
  CALL dq.finish_batch(p_batch_id);
END $$;

-- TORNELLI -------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dq.load_gate_batch(p_batch_id bigint)
LANGUAGE plpgsql AS $$
DECLARE v_source smallint; v_edition smallint; v_tz text; v_code text; v_edtz text;
BEGIN
  SELECT b.source_id,e.edition_id,s.source_timezone,s.code,e.timezone INTO v_source,v_edition,v_tz,v_code,v_edtz
  FROM dq.import_batch b JOIN core.data_source s ON s.source_id=b.source_id JOIN core.edition e ON e.year=right(s.code,4)::smallint
  WHERE b.batch_id=p_batch_id AND b.status='RUNNING' AND s.kind='TURNSTILE';
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % must be RUNNING TURNSTILE with a year suffix', p_batch_id; END IF;
  DROP TABLE IF EXISTS _gate_check;
  CREATE TEMP TABLE _gate_check ON COMMIT DROP AS
  SELECT x.*, ga.gate_id, t.ticket_id,
         ((x.read_at AT TIME ZONE v_edtz)::time NOT BETWEEN d.opens_at AND d.closes_at) AS outside_hours
  FROM (SELECT s.row_no,dq.clean_text(s.codice) AS ticket_code,dq.try_timestamptz(dq.clean_text(s.data)||' '||dq.clean_text(s.ora),v_tz) AS read_at,
               dq.norm_text(s.varco) AS gate_alias,CASE dq.norm_text(s.esito) WHEN 'OK' THEN 'OK' WHEN '1' THEN 'OK' WHEN 'KO' THEN 'KO' WHEN '0' THEN 'KO' END AS result, to_jsonb(s) raw_record FROM staging.stg_gate_reading_v1 s WHERE s.batch_id=p_batch_id
        UNION ALL SELECT s.row_no,dq.clean_text(s.ticket_code),dq.try_timestamptz(s.timestamp_utc,v_tz),dq.norm_text(s.gate_id),CASE WHEN dq.norm_text(s.result) IN ('OK','KO') THEN dq.norm_text(s.result) END,to_jsonb(s) FROM staging.stg_gate_reading_v2 s WHERE s.batch_id=p_batch_id) x
  LEFT JOIN core.gate_alias ga ON ga.alias_norm=x.gate_alias LEFT JOIN core.ticket t ON t.ticket_code=x.ticket_code
  LEFT JOIN core.edition_day d ON d.edition_id=v_edition AND d.day_date=(x.read_at AT TIME ZONE v_edtz)::date;
  UPDATE dq.import_batch SET rows_read=(SELECT count(*) FROM _gate_check) WHERE batch_id=p_batch_id;
  PERFORM dq.add_anomaly(p_batch_id,'GAT-008',row_no,ticket_code,jsonb_build_object('reason','unmapped gate, missing ticket code or invalid timestamp/result'))
    FROM _gate_check WHERE gate_id IS NULL OR ticket_code IS NULL OR read_at IS NULL OR result IS NULL;
  PERFORM dq.add_anomaly(p_batch_id,'GAT-001',row_no,ticket_code,'{}') FROM _gate_check WHERE ticket_id IS NULL AND ticket_code IS NOT NULL;
  PERFORM dq.add_anomaly(p_batch_id,'GAT-002',row_no,ticket_code,'{}') FROM _gate_check WHERE outside_hours;
  PERFORM dq.add_anomaly(p_batch_id,'GAT-003',row_no,ticket_code,'{}') FROM _gate_check WHERE result='KO';
  PERFORM dq.add_anomaly(p_batch_id,'GAT-005',g.row_no,g.ticket_code,'{}') FROM _gate_check g JOIN core.ticket t ON t.ticket_id=g.ticket_id WHERE t.valid_day IS NOT NULL AND t.valid_day<>(g.read_at AT TIME ZONE v_edtz)::date;
  PERFORM dq.add_anomaly(p_batch_id,'GAT-006',row_no,ticket_code,'{}') FROM _gate_check g JOIN core.ticket_order o ON o.order_id=(SELECT order_id FROM core.ticket WHERE ticket_id=g.ticket_id) WHERE g.read_at<o.purchased_at;
  IF v_code='TORN_2024' THEN PERFORM dq.add_anomaly(p_batch_id,'GAT-007',NULL,v_code,jsonb_build_object('source_timezone',v_tz,'rows',(SELECT count(*) FROM _gate_check))); END IF;
  INSERT INTO dq.quarantine(batch_id,source_id,source_row_no,raw_record,reason_rule)
  SELECT p_batch_id,v_source,row_no,raw_record,'GAT-008' FROM _gate_check WHERE gate_id IS NULL OR ticket_code IS NULL OR read_at IS NULL OR result IS NULL ON CONFLICT DO NOTHING;
  INSERT INTO core.gate_reading(edition_id,gate_id,ticket_code,ticket_id,read_at,result,source_id,import_batch_id,source_row_key)
  -- Chiave naturale della lettura (come sourceRowKey del contratto API): varco|codice|istante UTC; '#n' solo per ripetizioni identiche nello stesso file.
  SELECT v_edition,k.gate_id,k.ticket_code,k.ticket_id,k.read_at,k.result,v_source,p_batch_id,
         k.gate_code||'|'||k.ticket_code||'|'||to_char(k.read_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')||CASE WHEN k.occ>1 THEN '#'||k.occ ELSE '' END
  FROM (SELECT c.*, g.gate_code, row_number() OVER (PARTITION BY c.gate_id,c.ticket_code,c.read_at ORDER BY c.row_no) AS occ
          FROM _gate_check c JOIN core.gate g ON g.gate_id=c.gate_id
         WHERE c.ticket_code IS NOT NULL AND c.read_at IS NOT NULL AND c.result IS NOT NULL) k
  ON CONFLICT DO NOTHING;
  UPDATE dq.import_batch SET rows_loaded=(SELECT count(*) FROM core.gate_reading WHERE import_batch_id=p_batch_id),rows_quarantined=(SELECT count(DISTINCT source_row_no) FROM dq.quarantine WHERE batch_id=p_batch_id),rows_rejected=(SELECT count(*) FROM _gate_check WHERE gate_id IS NOT NULL AND ticket_code IS NOT NULL AND read_at IS NOT NULL AND result IS NOT NULL)-(SELECT count(*) FROM core.gate_reading WHERE import_batch_id=p_batch_id) WHERE batch_id=p_batch_id;
  CALL dq.finish_batch(p_batch_id);
END $$;

-- VISITE STAND AGGREGATE ------------------------------------------------
CREATE OR REPLACE PROCEDURE dq.load_stand_visit_batch(p_batch_id bigint)
LANGUAGE plpgsql AS $$
DECLARE v_source smallint; v_edition smallint; v_tz text;
BEGIN
  SELECT b.source_id,e.edition_id,s.source_timezone INTO v_source,v_edition,v_tz FROM dq.import_batch b JOIN core.data_source s ON s.source_id=b.source_id JOIN core.edition e ON e.year=right(s.code,4)::smallint WHERE b.batch_id=p_batch_id AND b.status='RUNNING' AND s.kind='STAND_SCAN';
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % must be RUNNING STAND_SCAN with a year suffix', p_batch_id; END IF;
  DROP TABLE IF EXISTS _visit_check;
  CREATE TEMP TABLE _visit_check ON COMMIT DROP AS
  SELECT s.row_no,dq.clean_text(s.codice_stand) stand_code,dq.try_date(s.data) visit_date,extract(hour FROM dq.try_time(s.ora))::smallint visit_hour,dq.try_numeric(s.scansioni)::integer scans,to_jsonb(s) raw_record,se.stand_edition_id,
         count(*) OVER (PARTITION BY dq.clean_text(s.codice_stand),dq.try_date(s.data),extract(hour FROM dq.try_time(s.ora))::smallint) duplicate_in_file
  FROM staging.stg_stand_visit_hourly s LEFT JOIN core.stand st ON st.stand_code=dq.clean_text(s.codice_stand) LEFT JOIN core.stand_edition se ON se.stand_id=st.stand_id AND se.edition_id=v_edition WHERE s.batch_id=p_batch_id;
  UPDATE dq.import_batch SET rows_read=(SELECT count(*) FROM _visit_check) WHERE batch_id=p_batch_id;
  PERFORM dq.add_anomaly(p_batch_id,'VIS-004',row_no,stand_code,'{}') FROM _visit_check WHERE duplicate_in_file>1;
  PERFORM dq.add_anomaly(p_batch_id,'VIS-002',row_no,stand_code,'{}') FROM _visit_check v WHERE stand_edition_id IS NULL OR NOT EXISTS (SELECT 1 FROM core.contract_stand cs JOIN core.contract c ON c.contract_id=cs.contract_id AND c.status='SIGNED' WHERE cs.stand_edition_id=v.stand_edition_id AND cs.released_at IS NULL);
  PERFORM dq.add_anomaly(p_batch_id,'VIS-003',row_no,stand_code,'{}') FROM _visit_check v JOIN core.edition_day d ON d.edition_id=v_edition AND d.day_date=v.visit_date WHERE visit_hour<extract(hour FROM d.opens_at) OR visit_hour>extract(hour FROM d.closes_at);
  PERFORM dq.add_anomaly(p_batch_id,'VIS-001',row_no,stand_code,jsonb_build_object('scans',scans)) FROM _visit_check WHERE scans > (SELECT avg(scans)+3*stddev_pop(scans) FROM _visit_check WHERE scans IS NOT NULL);
  INSERT INTO dq.quarantine(batch_id,source_id,source_row_no,raw_record,reason_rule)
  SELECT p_batch_id,v_source,row_no,raw_record,'VIS-002' FROM _visit_check v WHERE stand_edition_id IS NULL OR visit_date IS NULL OR visit_hour IS NULL OR visit_hour NOT BETWEEN 0 AND 23 OR scans IS NULL OR scans<0 OR NOT EXISTS (SELECT 1 FROM core.contract_stand cs JOIN core.contract c ON c.contract_id=cs.contract_id AND c.status='SIGNED' WHERE cs.stand_edition_id=v.stand_edition_id AND cs.released_at IS NULL) ON CONFLICT DO NOTHING;
  INSERT INTO core.stand_visit_hourly(stand_edition_id,visit_date,visit_hour,scans,source_id,import_batch_id)
  SELECT stand_edition_id,visit_date,visit_hour,scans,v_source,p_batch_id FROM _visit_check v WHERE duplicate_in_file=1 AND stand_edition_id IS NOT NULL AND visit_date IS NOT NULL AND visit_hour BETWEEN 0 AND 23 AND scans>=0 AND EXISTS (SELECT 1 FROM core.contract_stand cs JOIN core.contract c ON c.contract_id=cs.contract_id AND c.status='SIGNED' WHERE cs.stand_edition_id=v.stand_edition_id AND cs.released_at IS NULL) ON CONFLICT DO NOTHING;
  UPDATE dq.import_batch SET rows_loaded=(SELECT count(*) FROM core.stand_visit_hourly WHERE import_batch_id=p_batch_id),rows_quarantined=(SELECT count(DISTINCT source_row_no) FROM dq.quarantine WHERE batch_id=p_batch_id),rows_rejected=(SELECT count(*) FROM _visit_check WHERE duplicate_in_file>1) WHERE batch_id=p_batch_id;
  CALL dq.finish_batch(p_batch_id);
END $$;

CREATE OR REPLACE VIEW dq.v_import_quality_report AS
SELECT b.batch_id, s.code AS source_code, b.file_name, b.status, b.rows_read, b.rows_loaded,
       b.rows_quarantined, b.rows_rejected, b.finished_at, r.rule_code, r.severity,
       count(a.anomaly_id) AS anomaly_count
FROM dq.import_batch b JOIN core.data_source s ON s.source_id=b.source_id
LEFT JOIN dq.anomaly a ON a.batch_id=b.batch_id LEFT JOIN dq.rule r ON r.rule_code=a.rule_code
GROUP BY b.batch_id,s.code,b.file_name,b.status,b.rows_read,b.rows_loaded,b.rows_quarantined,b.rows_rejected,b.finished_at,r.rule_code,r.severity;

COMMENT ON VIEW dq.v_import_quality_report IS 'Report da approvare prima di consumare dati reali in analytics. Una riga per batch e regola DQ.';

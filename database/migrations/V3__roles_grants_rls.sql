-- =====================================================================
-- ARCADE Milano - V3: ruoli, grant, Row Level Security
--
-- Modello di accesso (minimo privilegio):
--   arcade_app    sessione STAFF del backend (commerciale/operativo/admin)
--   arcade_portal sessione ESPOSITORE: sola lettura, righe limitate al proprio exhibitor_id
--   arcade_etl    caricamento dati (staging, dq, scrittura core)
--   arcade_bi     Power BI: SOLO schema analytics (nessun accesso a core)
--
-- I ruoli sono NOLOGIN (gruppi). Gli account di login con password NON stanno nel repo:
-- si creano per ambiente, ad es.
--   CREATE ROLE arcade_backend LOGIN PASSWORD '<da secret manager>' IN ROLE arcade_app, arcade_portal;
--   CREATE ROLE arcade_etl_job LOGIN PASSWORD '<...>' IN ROLE arcade_etl;
--   CREATE ROLE arcade_powerbi LOGIN PASSWORD '<...>' IN ROLE arcade_bi;
--
-- Il backend, per una richiesta di un espositore, apre una transazione e fa:
--   SET LOCAL ROLE arcade_portal;
--   SELECT set_config('app.exhibitor_id', '<id dal JWT>', true);
-- Senza il parametro l'accesso e' FAIL-CLOSED: nessuna riga.
-- =====================================================================

DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['arcade_app','arcade_portal','arcade_etl','arcade_bi'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
END $$;

REVOKE ALL ON SCHEMA core, staging, dq FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 1. STAFF (arcade_app)
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA core, dq TO arcade_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core TO arcade_app;
-- audit append-only: nessuna modifica o cancellazione, nemmeno dal backend
REVOKE UPDATE, DELETE ON core.audit_log FROM arcade_app;
GRANT SELECT ON ALL TABLES IN SCHEMA dq TO arcade_app;
GRANT INSERT, UPDATE ON dq.anomaly, dq.quarantine TO arcade_app;   -- presa in carico/risoluzione
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO arcade_app;

-- ---------------------------------------------------------------------
-- 2. ETL (arcade_etl)
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA core, staging, dq TO arcade_etl;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core TO arcade_etl;   -- niente DELETE sul core
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA staging TO arcade_etl;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA dq TO arcade_etl;
REVOKE UPDATE ON core.audit_log FROM arcade_etl;
ALTER DEFAULT PRIVILEGES IN SCHEMA core    GRANT SELECT, INSERT, UPDATE ON TABLES TO arcade_etl;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO arcade_etl;

-- ---------------------------------------------------------------------
-- 3. PORTALE ESPOSITORI (arcade_portal): sola lettura
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA core TO arcade_portal;
-- Dati pubblici (planimetria, listino, calendario): nessuna riga riservata
GRANT SELECT ON core.edition, core.edition_day, core.pavilion, core.stand, core.stand_edition,
                core.exhibitor_category, core.price_list, core.price_item TO arcade_portal;
-- Dati riservati: protetti da RLS (policy sotto)
GRANT SELECT ON core.exhibitor, core.exhibitor_contact, core.contract, core.contract_line,
                core.contract_stand, core.payment, core.sponsorship, core.preemption,
                core.quote, core.quote_line, core.stand_visit_hourly TO arcade_portal;
-- Colonne esplicite: niente visitor_token (pseudonimo) e niente email_hash/is_qualified dei contatti
GRANT SELECT (visit_id, stand_edition_id, device_id, visited_at, source_id) ON core.stand_visit TO arcade_portal;
GRANT SELECT (lead_id, lead_code, stand_edition_id, exhibitor_id, captured_at, age_band_id,
              province_id, interest_id, marketing_consent, review_status) ON core.stand_lead TO arcade_portal;
GRANT SELECT ON core.age_band, core.province, core.lead_interest TO arcade_portal;
-- NESSUN accesso a: app_user, audit_log, gate_reading, ticket*, dq.*, staging.*

-- ---------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
-- Identita' dell'espositore della sessione. NULL se non impostata o vuota => nessuna riga.
CREATE FUNCTION core.current_exhibitor_id() RETURNS integer
LANGUAGE sql STABLE
AS $$ SELECT NULLIF(current_setting('app.exhibitor_id', true), '')::integer $$;

COMMENT ON FUNCTION core.current_exhibitor_id() IS
 'Letta dalle policy RLS. Difesa in profondita'': l''autorizzazione primaria resta nel backend (JWT -> exhibitor_id). '
 'Un SQL injection nella sessione portale potrebbe eseguire SET app.exhibitor_id: per questo il ruolo portale e'' sola lettura e le query usano solo parametri bind.';

-- Abilita RLS e crea la policy staff (accesso pieno) su tutte le tabelle protette
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['exhibitor','exhibitor_contact','contract','contract_line','contract_stand',
                           'payment','sponsorship','preemption','quote','quote_line',
                           'stand_visit','stand_visit_hourly','stand_lead'] LOOP
    EXECUTE format('ALTER TABLE core.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY staff_all ON core.%I FOR ALL TO arcade_app, arcade_etl USING (true) WITH CHECK (true)', t);
  END LOOP;
END $$;

-- Policy portale (solo SELECT). Le EXISTS su tabelle a loro volta protette ereditano il filtro.
CREATE POLICY portal_own ON core.exhibitor         FOR SELECT TO arcade_portal USING (exhibitor_id = core.current_exhibitor_id());
CREATE POLICY portal_own ON core.exhibitor_contact FOR SELECT TO arcade_portal USING (exhibitor_id = core.current_exhibitor_id());
CREATE POLICY portal_own ON core.contract          FOR SELECT TO arcade_portal USING (exhibitor_id = core.current_exhibitor_id());
CREATE POLICY portal_own ON core.preemption        FOR SELECT TO arcade_portal USING (exhibitor_id = core.current_exhibitor_id());
CREATE POLICY portal_own ON core.quote             FOR SELECT TO arcade_portal USING (exhibitor_id = core.current_exhibitor_id());
-- contatti raccolti: solo i propri e solo se non in revisione privacy (es. minori)
CREATE POLICY portal_own ON core.stand_lead        FOR SELECT TO arcade_portal
  USING (exhibitor_id = core.current_exhibitor_id() AND review_status = 'OK');

CREATE POLICY portal_own ON core.contract_line FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.contract c WHERE c.contract_id = contract_line.contract_id));
CREATE POLICY portal_own ON core.contract_stand FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.contract c WHERE c.contract_id = contract_stand.contract_id));
CREATE POLICY portal_own ON core.payment FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.contract c WHERE c.contract_id = payment.contract_id));
CREATE POLICY portal_own ON core.sponsorship FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.contract_line l WHERE l.contract_line_id = sponsorship.contract_line_id));
CREATE POLICY portal_own ON core.quote_line FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.quote q WHERE q.quote_id = quote_line.quote_id));
-- visite: solo degli stand attualmente assegnati al proprio contratto
CREATE POLICY portal_own ON core.stand_visit FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.contract_stand cs
                  WHERE cs.stand_edition_id = stand_visit.stand_edition_id AND cs.released_at IS NULL));
CREATE POLICY portal_own ON core.stand_visit_hourly FOR SELECT TO arcade_portal
  USING (EXISTS (SELECT 1 FROM core.contract_stand cs
                  WHERE cs.stand_edition_id = stand_visit_hourly.stand_edition_id AND cs.released_at IS NULL));

-- Il proprietario delle tabelle (utente di migrazione) bypassa RLS di default: e' voluto
-- (le viste analytics/portal girano con i suoi diritti). Non usare l'owner per il backend.

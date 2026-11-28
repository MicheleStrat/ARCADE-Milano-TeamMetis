-- =====================================================================
-- ARCADE Milano - V14 (team BAD): tabelle della Live leggibili da Power Apps (B-67)
--
-- PERCHE'
--   Il connettore PostgreSQL di Power Apps elenca solo le tabelle, non le viste
--   (verificato il 24/11: non compaiono ne' le viste live della V12/V13 ne' quelle
--   flow della V10, con i permessi a posto). La Live quindi legge COPIE delle viste.
--
-- COME FUNZIONA
--   - live.t_day, t_day_kpi, t_day_pavilion, t_last_readings, t_map_stand: tabelle
--     normali con le stesse colonne delle viste live.v_* (chiave primaria per il connettore).
--   - live.refresh_request: una riga per ogni giorno di fiera + la riga 0.
--     L'app fa un Patch su una riga (campo "richieste" + 1): il trigger ricalcola
--     dalle viste i dati di quel giorno (e sempre l'elenco dei giorni) nella stessa
--     transazione, quindi quando il Patch torna all'app i dati sono gia' aggiornati.
--     Riga 0 = aggiorna solo l'elenco dei giorni.
--   - Un solo ricalcolo alla volta (lock), cosi' due utenti insieme non si pestano i piedi.
--   L'app non scrive mai nelle tabelle t_*: le scrive solo la funzione (SECURITY DEFINER).
--
-- NON CAMBIA: nessuna tabella del core, nessun dato. RIPETIBILE (ricrea le tabelle copia).
-- PREREQUISITI: V11, V12, V13. SOLO CARATTERI ASCII.
-- PER TORNARE INDIETRO:
--   DROP TABLE live.refresh_request, live.t_day, live.t_day_kpi, live.t_day_pavilion,
--              live.t_last_readings, live.t_map_stand;
--   DROP FUNCTION live.refresh(int), live.trg_refresh();
-- =====================================================================

BEGIN;

DROP TABLE IF EXISTS live.refresh_request, live.t_day, live.t_day_kpi, live.t_day_pavilion,
                     live.t_last_readings, live.t_map_stand;

CREATE TABLE live.t_day (
    day_key     integer  PRIMARY KEY,
    edition_id  smallint NOT NULL,
    year        smallint NOT NULL,
    day_date    date     NOT NULL,
    day_number  smallint NOT NULL,
    is_today    boolean  NOT NULL,
    etichetta   text     NOT NULL      -- per il menu Giorno: "Oggi 11/12/2026 - giorno 1" / "20/12/2025 - giorno 2"
);

CREATE TABLE live.t_day_kpi (
    day_key             integer PRIMARY KEY,
    edition_id          smallint,
    year                smallint,
    day_date            date,
    day_number          smallint,
    is_today            boolean,
    aggiornato_alle     text,
    biglietti_venduti   integer,
    biglietti_validati  integer,
    presenza_stima      integer,
    ingressi_ultima_ora integer,
    picco_stima         integer,
    picco_alle          text
);

CREATE TABLE live.t_day_pavilion (
    day_key        integer  NOT NULL,
    pavilion_id    smallint NOT NULL,
    code           text,
    name           text,
    presenza_stima integer,
    PRIMARY KEY (day_key, pavilion_id)
);

CREATE TABLE live.t_last_readings (
    day_key     integer NOT NULL,
    reading_id  bigint  NOT NULL,
    read_at     timestamptz,
    ora         text,
    gate_name   text,
    ticket_code text,
    esito       text,
    PRIMARY KEY (day_key, reading_id)
);

CREATE TABLE live.t_map_stand (
    day_key         integer NOT NULL,
    padiglione      text,
    padiglione_nome text,
    codice          text    NOT NULL,
    mq              numeric(7,2),
    posizione       text,
    stato           text,
    espositore      text,
    fonte           text,
    ora_inizio      integer,
    persone         integer,
    persone_ore     text,
    PRIMARY KEY (day_key, codice)
);

CREATE TABLE live.refresh_request (
    day_key       integer PRIMARY KEY,      -- 0 = solo elenco dei giorni
    richieste     integer NOT NULL DEFAULT 0,
    aggiornato_il timestamptz
);

-- Ricalcola le copie. Gira con i permessi del proprietario (le viste sono security_invoker).
CREATE OR REPLACE FUNCTION live.refresh(p_day integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('live.refresh'));

    DELETE FROM live.t_day;
    INSERT INTO live.t_day (day_key, edition_id, year, day_date, day_number, is_today, etichetta)
    SELECT day_key, edition_id, year, day_date, day_number, is_today,
           CASE WHEN is_today THEN 'Oggi ' ELSE '' END
           || to_char(day_date, 'DD/MM/YYYY') || ' - giorno ' || day_number
    FROM live.v_day;

    IF p_day > 0 THEN
        DELETE FROM live.t_day_kpi       WHERE day_key = p_day;
        DELETE FROM live.t_day_pavilion  WHERE day_key = p_day;
        DELETE FROM live.t_last_readings WHERE day_key = p_day;
        DELETE FROM live.t_map_stand     WHERE day_key = p_day;

        INSERT INTO live.t_day_kpi
        SELECT day_key, edition_id, year, day_date, day_number, is_today, aggiornato_alle,
               biglietti_venduti, biglietti_validati, presenza_stima, ingressi_ultima_ora,
               picco_stima, picco_alle
        FROM live.v_day_kpi WHERE day_key = p_day;

        INSERT INTO live.t_day_pavilion
        SELECT day_key, pavilion_id, code, name, presenza_stima
        FROM live.v_day_pavilion WHERE day_key = p_day;

        INSERT INTO live.t_last_readings
        SELECT day_key, reading_id, read_at, ora, gate_name, ticket_code, esito
        FROM live.v_last_readings WHERE day_key = p_day;

        INSERT INTO live.t_map_stand
        SELECT day_key, padiglione, padiglione_nome, codice, mq, posizione, stato, espositore,
               fonte, ora_inizio, persone, persone_ore
        FROM live.v_map_stand WHERE day_key = p_day;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION live.refresh(integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION live.trg_refresh()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF TG_WHEN = 'BEFORE' THEN
        NEW.aggiornato_il := now();
        RETURN NEW;
    END IF;
    PERFORM live.refresh(NEW.day_key);
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION live.trg_refresh() FROM PUBLIC;

CREATE TRIGGER trg_refresh_stamp BEFORE UPDATE ON live.refresh_request
    FOR EACH ROW EXECUTE FUNCTION live.trg_refresh();
CREATE TRIGGER trg_refresh_run AFTER UPDATE ON live.refresh_request
    FOR EACH ROW EXECUTE FUNCTION live.trg_refresh();

-- Una riga per ogni giorno di fiera di tutte le edizioni (anche futuri: si riempiono quando arrivano) + la riga 0.
INSERT INTO live.refresh_request (day_key)
SELECT 0
UNION
SELECT to_char(day_date, 'YYYYMMDD')::int FROM core.edition_day;

-- Primo riempimento dell'elenco dei giorni.
SELECT live.refresh(0);

-- Permessi: l'app (arcade_app) legge le copie e aggiorna solo refresh_request.
GRANT SELECT ON live.t_day, live.t_day_kpi, live.t_day_pavilion, live.t_last_readings, live.t_map_stand
    TO arcade_app, arcade_bi;
GRANT SELECT, UPDATE ON live.refresh_request TO arcade_app;

COMMIT;

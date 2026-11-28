-- =====================================================================
-- ARCADE Milano - V12 (team BAD): viste per la schermata Live e mappa (B-64)
-- Schema nuovo del BAD "live": solo viste, nessuna tabella, nessun dato cambiato.
-- Ogni vista ha day_key (intero AAAAMMGG) per filtrare il giorno da Power Apps con un
-- confronto tra numeri (i filtri sulle date non sono affidabili nel connettore PostgreSQL, B-50).
-- "Fino a quando" si contano i dati (cutoff): per il giorno di oggi l'ora attuale, per un
-- giorno passato la chiusura. Cosi' i dati demo dell'11/12 compaiono man mano (B-61).
-- Giorni futuri esclusi. Ora di Roma (fuso dell'edizione). Stime come in B-13 (90 min, 15 min).
-- RIPETIBILE. Richiede V11 (schema sensor). Solo caratteri ASCII nel codice.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS live;
COMMENT ON SCHEMA live IS 'Team BAD: viste della schermata Live e mappa del back-office (B-64).';

-- Giorni di fiera di oggi e passati, con l'istante fino a cui contare.
CREATE OR REPLACE VIEW live.v_day
WITH (security_invoker = true) AS
SELECT d.edition_id,
       e.year,
       d.day_date,
       d.day_number,
       to_char(d.day_date, 'YYYYMMDD')::int                         AS day_key,
       (d.day_date + d.opens_at)  AT TIME ZONE e.timezone           AS opens_ts,
       (d.day_date + d.closes_at) AT TIME ZONE e.timezone           AS closes_ts,
       least(now(), (d.day_date + d.closes_at) AT TIME ZONE e.timezone) AS cutoff,
       (d.day_date = (now() AT TIME ZONE e.timezone)::date)          AS is_today,
       e.timezone,
       d.day_date::timestamp AT TIME ZONE e.timezone                  AS day_start,
       (d.day_date + 1)::timestamp AT TIME ZONE e.timezone            AS day_end
FROM core.edition_day d
JOIN core.edition e ON e.edition_id = d.edition_id
WHERE d.day_date <= (now() AT TIME ZONE e.timezone)::date;

-- Letture del giorno fino al cutoff, con padiglione ed esito per la Live (OK / RIENTRO / KO).
CREATE OR REPLACE VIEW live.v_reading
WITH (security_invoker = true) AS
SELECT d.day_key,
       gr.reading_id,
       gr.read_at,
       to_char(gr.read_at AT TIME ZONE d.timezone, 'HH24:MI') AS ora,
       gr.gate_id,
       g.name       AS gate_name,
       g.pavilion_id,
       gr.ticket_code,
       gr.ticket_id,
       gr.result,
       CASE WHEN gr.result = 'KO' THEN 'KO'
            WHEN row_number() OVER (PARTITION BY d.day_key, gr.result, gr.ticket_code ORDER BY gr.read_at, gr.reading_id) = 1 THEN 'OK'
            ELSE 'RIENTRO' END AS esito
FROM live.v_day d
JOIN core.gate_reading gr
  ON gr.edition_id = d.edition_id
 AND gr.read_at >= d.day_start
 AND gr.read_at <  d.day_end
 AND gr.read_at <= d.cutoff
JOIN core.gate g ON g.gate_id = gr.gate_id;

-- Le 4 card della Live, una riga per giorno.
-- Letture direttamente da core.gate_reading per intervallo di tempo (indice su read_at):
-- ogni misura legge solo le righe del giorno, il picco legge le letture una volta sola.
CREATE OR REPLACE VIEW live.v_day_kpi
WITH (security_invoker = true) AS
SELECT d.day_key, d.edition_id, d.year, d.day_date, d.day_number, d.is_today, d.cutoff,
       to_char(d.cutoff AT TIME ZONE d.timezone, 'HH24:MI') AS aggiornato_alle,
       (SELECT count(*) FROM core.ticket t
         WHERE t.edition_id = d.edition_id AND (t.valid_day = d.day_date OR t.valid_day IS NULL))::int AS biglietti_venduti,
       (SELECT count(DISTINCT gr.ticket_id) FROM core.gate_reading gr
         WHERE gr.edition_id = d.edition_id AND gr.result = 'OK' AND gr.ticket_id IS NOT NULL
           AND gr.read_at >= d.day_start AND gr.read_at <= d.cutoff)::int                           AS biglietti_validati,
       (SELECT count(DISTINCT gr.ticket_code) FROM core.gate_reading gr
         WHERE gr.edition_id = d.edition_id AND gr.result = 'OK'
           AND gr.read_at > d.cutoff - interval '90 minutes' AND gr.read_at <= d.cutoff)::int        AS presenza_stima,
       (SELECT count(*) FROM (
            SELECT gr.ticket_code, min(gr.read_at) AS primo
            FROM core.gate_reading gr
            WHERE gr.edition_id = d.edition_id AND gr.result = 'OK'
              AND gr.read_at >= d.day_start AND gr.read_at <= d.cutoff
            GROUP BY gr.ticket_code) x
         WHERE x.primo > d.cutoff - interval '1 hour')::int                                          AS ingressi_ultima_ora,
       pk.picco_stima,
       to_char(pk.picco_alle AT TIME ZONE d.timezone, 'HH24:MI')                                AS picco_alle
FROM live.v_day d
LEFT JOIN LATERAL (
    SELECT b.t AS picco_alle, count(DISTINCT gr.ticket_code)::int AS picco_stima
    FROM generate_series(d.opens_ts + interval '15 minutes', d.cutoff, interval '15 minutes') b(t)
    JOIN core.gate_reading gr
      ON gr.edition_id = d.edition_id AND gr.result = 'OK'
     AND gr.read_at >  b.t - interval '90 minutes'
     AND gr.read_at <= b.t
    GROUP BY b.t
    ORDER BY 2 DESC, 1
    LIMIT 1
) pk ON true;

-- Presenza stimata per padiglione (biglietti distinti entrati nel padiglione negli ultimi 90 minuti).
CREATE OR REPLACE VIEW live.v_day_pavilion
WITH (security_invoker = true) AS
SELECT d.day_key, p.pavilion_id, p.code, p.name,
       coalesce(x.presenza_stima, 0) AS presenza_stima
FROM live.v_day d
CROSS JOIN core.pavilion p
LEFT JOIN LATERAL (
    SELECT count(DISTINCT gr.ticket_code)::int AS presenza_stima
    FROM core.gate_reading gr
    JOIN core.gate g ON g.gate_id = gr.gate_id
    WHERE gr.edition_id = d.edition_id AND g.pavilion_id = p.pavilion_id AND gr.result = 'OK'
      AND gr.read_at > d.cutoff - interval '90 minutes' AND gr.read_at <= d.cutoff
) x ON true;

-- Ultimi 15 passaggi ai varchi del giorno.
CREATE OR REPLACE VIEW live.v_last_readings
WITH (security_invoker = true) AS
SELECT day_key, reading_id, read_at, ora, gate_name, ticket_code, esito
FROM (SELECT r.*, row_number() OVER (PARTITION BY r.day_key ORDER BY r.read_at DESC, r.reading_id DESC) AS n
      FROM live.v_reading r) x
WHERE n <= 15;

-- Affluenza per stand per la mappa: sensori (B-62); per i giorni senza sensori (2024/2025)
-- le visite orarie per stand (escluse le ore prima dell'apertura, riga anomala delle 8, B-14).
CREATE OR REPLACE VIEW live.v_stand_heat
WITH (security_invoker = true) AS
WITH sens AS (
    SELECT d.day_key, sc.stand_id,
           sum(cc.persons)::int AS persone_giorno,
           coalesce(sum(cc.persons) FILTER (WHERE cc.bucket_start > d.cutoff - interval '1 hour'), 0)::int AS persone_ultima_ora
    FROM live.v_day d
    JOIN sensor.camera_count cc
      ON cc.bucket_start >= d.opens_ts AND cc.bucket_start < d.closes_ts AND cc.bucket_start <= d.cutoff
    JOIN sensor.stand_camera sc ON sc.camera_id = cc.camera_id
    GROUP BY 1, 2
), vis AS (
    SELECT d.day_key, se.stand_id,
           sum(v.scans)::int AS persone_giorno,
           coalesce(sum(v.scans) FILTER (WHERE (d.day_date + make_interval(hours => v.visit_hour)) AT TIME ZONE d.timezone
                                                > d.cutoff - interval '1 hour'), 0)::int AS persone_ultima_ora
    FROM live.v_day d
    JOIN core.stand_visit_hourly v ON v.visit_date = d.day_date
    JOIN core.stand_edition se ON se.stand_edition_id = v.stand_edition_id AND se.edition_id = d.edition_id
    WHERE v.visit_hour >= date_part('hour', d.opens_ts AT TIME ZONE d.timezone)
      AND (d.day_date + make_interval(hours => v.visit_hour)) AT TIME ZONE d.timezone < d.cutoff
      AND NOT EXISTS (SELECT 1 FROM sens WHERE sens.day_key = d.day_key)
    GROUP BY 1, 2
)
SELECT x.day_key, x.stand_id, s.stand_code, x.persone_giorno, x.persone_ultima_ora
FROM (SELECT * FROM sens UNION ALL SELECT * FROM vis) x
JOIN core.stand s ON s.stand_id = x.stand_id;

-- Permessi: lettura per l'app e i flussi (arcade_app) e per Power BI (arcade_bi).
GRANT USAGE ON SCHEMA live TO arcade_app, arcade_bi;
GRANT SELECT ON ALL TABLES IN SCHEMA live TO arcade_app, arcade_bi;

-- V13 (BAD) - Dati della Mappa3D nella schermata Live (B-66).
-- Una riga per stand dell'edizione e per giorno di fiera (oggi o passato, da live.v_day):
-- persone allo stand in totale e ora per ora fino al cutoff (adesso per oggi, chiusura per i giorni passati).
-- Fonte: sensori (sensor.camera_count) se nel giorno ce ne sono, altrimenti scansioni allo stand
-- (core.stand_visit_hourly). Ore prima dell'apertura escluse, come in live.v_stand_heat.
-- Solo viste: si puo' rieseguire. Richiede V11 (schema sensor) e V12 (schema live).

CREATE OR REPLACE VIEW live.v_map_stand
WITH (security_invoker = true) AS
WITH d AS (
    SELECT v.day_key, v.edition_id, v.day_date, v.timezone, v.opens_ts, v.closes_ts, v.cutoff,
           extract(hour FROM v.opens_ts AT TIME ZONE v.timezone)::int AS h0,
           -- ultima ora gia' iniziata prima del cutoff (per oggi prima dell'apertura: h1 < h0, nessuna ora)
           CASE WHEN v.cutoff <= v.opens_ts THEN extract(hour FROM v.opens_ts AT TIME ZONE v.timezone)::int - 1
                ELSE extract(hour FROM (v.cutoff - interval '1 microsecond') AT TIME ZONE v.timezone)::int END AS h1
    FROM live.v_day v
), sens AS (
    SELECT d.day_key, sc.stand_id,
           extract(hour FROM cc.bucket_start AT TIME ZONE d.timezone)::int AS ora,
           sum(cc.persons)::int AS n
    FROM d
    JOIN sensor.camera_count cc
      ON cc.bucket_start >= d.opens_ts AND cc.bucket_start < d.closes_ts AND cc.bucket_start < d.cutoff
    JOIN sensor.stand_camera sc ON sc.camera_id = cc.camera_id
    GROUP BY 1, 2, 3
), fonte AS (
    SELECT d.day_key, EXISTS (SELECT 1 FROM sens WHERE sens.day_key = d.day_key) AS sensori
    FROM d
), vis AS (
    SELECT d.day_key, se.stand_id, v.visit_hour::int AS ora, sum(v.scans)::int AS n
    FROM d
    JOIN fonte f ON f.day_key = d.day_key AND NOT f.sensori
    JOIN core.stand_visit_hourly v ON v.visit_date = d.day_date
    JOIN core.stand_edition se ON se.stand_edition_id = v.stand_edition_id AND se.edition_id = d.edition_id
    WHERE v.visit_hour >= d.h0
      AND (d.day_date + make_interval(hours => v.visit_hour)) AT TIME ZONE d.timezone < d.cutoff
    GROUP BY 1, 2, 3
), conte AS (
    SELECT day_key, stand_id, ora, n FROM sens
    UNION ALL
    SELECT day_key, stand_id, ora, n FROM vis
), esp AS (
    -- espositore del contratto firmato che occupa lo stand nell'edizione (se c'e')
    SELECT DISTINCT ON (cs.stand_edition_id) cs.stand_edition_id, e.legal_name
    FROM core.contract_stand cs
    JOIN core.contract c ON c.contract_id = cs.contract_id AND c.status = 'SIGNED'
    JOIN core.exhibitor e ON e.exhibitor_id = c.exhibitor_id
    WHERE cs.released_at IS NULL
    ORDER BY cs.stand_edition_id, c.signed_on DESC NULLS LAST
)
SELECT d.day_key,
       p.code                                            AS padiglione,
       p.name                                            AS padiglione_nome,
       s.stand_code                                      AS codice,
       s.sqm                                             AS mq,
       s.position_type                                   AS posizione,
       se.commercial_status                              AS stato,
       coalesce(esp.legal_name, '')                      AS espositore,
       CASE WHEN f.sensori THEN 'SENSORI' ELSE 'SCANSIONI' END AS fonte,
       d.h0                                              AS ora_inizio,
       coalesce(sum(c.n), 0)::int                        AS persone,
       coalesce(string_agg(coalesce(c.n, 0)::text, ',' ORDER BY h.h), '') AS persone_ore
FROM d
JOIN fonte f ON f.day_key = d.day_key
JOIN core.stand_edition se ON se.edition_id = d.edition_id
JOIN core.stand s ON s.stand_id = se.stand_id
JOIN core.pavilion p ON p.pavilion_id = s.pavilion_id
LEFT JOIN esp ON esp.stand_edition_id = se.stand_edition_id
LEFT JOIN LATERAL generate_series(d.h0, d.h1) h(h) ON true
LEFT JOIN conte c ON c.day_key = d.day_key AND c.stand_id = s.stand_id AND c.ora = h.h
GROUP BY d.day_key, p.code, p.name, s.stand_code, s.sqm, s.position_type, se.commercial_status,
         esp.legal_name, f.sensori, d.h0;

GRANT SELECT ON live.v_map_stand TO arcade_app, arcade_bi;

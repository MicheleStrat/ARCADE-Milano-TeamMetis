-- =====================================================================
-- ARCADE Milano - V11 (team BAD): telecamere di conteggio simulate (B-61, B-62, A-12)
-- Schema nuovo del BAD "sensor": non modifica nessuna tabella di core.
-- Un sensore contapersone davanti a ogni stand (P1-A01-CAM, ...): conta le persone che passano
-- davanti all'ingresso dello stand, ogni 5 minuti, senza immagini (B-62, modificata il 24/11).
-- La tabella stand_camera resta separata: in futuro un sensore potrebbe coprire piu' stand.
-- RIPETIBILE: si puo' eseguire due volte senza errori e senza duplicati.
-- Solo caratteri ASCII nel codice (vedi note dell'8/11 sulla codifica da Windows).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS sensor;
COMMENT ON SCHEMA sensor IS 'Team BAD: telecamere di conteggio simulate (B-62). Dati demo, sostituibili da telecamere vere.';

-- Anagrafica dei sensori: uno davanti a ogni stand fisico.
CREATE TABLE IF NOT EXISTS sensor.camera (
    camera_id    smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    camera_code  text     NOT NULL UNIQUE CHECK (camera_code ~ '^P[0-9]+-[A-Z][0-9]{2}-CAM$'),
    pavilion_id  smallint NOT NULL REFERENCES core.pavilion,
    name         text     NOT NULL
);

-- Ogni stand fisico e' coperto da un solo sensore.
CREATE TABLE IF NOT EXISTS sensor.stand_camera (
    stand_id   integer  PRIMARY KEY REFERENCES core.stand,
    camera_id  smallint NOT NULL REFERENCES sensor.camera
);
CREATE INDEX IF NOT EXISTS ix_stand_camera_camera ON sensor.stand_camera (camera_id);

-- Conteggi: persone passate davanti al sensore nei 5 minuti che iniziano a bucket_start.
CREATE TABLE IF NOT EXISTS sensor.camera_count (
    camera_id     smallint    NOT NULL REFERENCES sensor.camera,
    bucket_start  timestamptz NOT NULL,
    persons       integer     NOT NULL CHECK (persons >= 0),
    source_id     smallint    NOT NULL REFERENCES core.data_source,
    PRIMARY KEY (camera_id, bucket_start),
    CHECK (date_part('second', bucket_start) = 0
           AND (date_part('minute', bucket_start)::int % 5) = 0)
);
CREATE INDEX IF NOT EXISTS ix_camera_count_time ON sensor.camera_count USING brin (bucket_start);

-- Anagrafica ricavata dagli stand esistenti (ripetibile: aggiunge solo quello che manca).
INSERT INTO sensor.camera (camera_code, pavilion_id, name)
SELECT s.stand_code || '-CAM', s.pavilion_id, 'Sensore stand ' || s.stand_code
FROM core.stand s
ON CONFLICT (camera_code) DO NOTHING;

INSERT INTO sensor.stand_camera (stand_id, camera_id)
SELECT s.stand_id, c.camera_id
FROM core.stand s
JOIN sensor.camera c ON c.camera_code = s.stand_code || '-CAM'
ON CONFLICT (stand_id) DO NOTHING;

-- Passaggi per stand, ora per ora (ora di Roma), per la Live e la mappa.
CREATE OR REPLACE VIEW sensor.v_stand_passes_hourly
WITH (security_invoker = true) AS
SELECT sc.stand_id,
       s.stand_code,
       c.camera_code,
       (cc.bucket_start AT TIME ZONE 'Europe/Rome')::date                     AS pass_date,
       date_part('hour', cc.bucket_start AT TIME ZONE 'Europe/Rome')::smallint AS pass_hour,
       sum(cc.persons)::integer                                               AS persons
FROM sensor.stand_camera sc
JOIN core.stand s          ON s.stand_id = sc.stand_id
JOIN sensor.camera c       ON c.camera_id = sc.camera_id
JOIN sensor.camera_count cc ON cc.camera_id = sc.camera_id
GROUP BY 1, 2, 3, 4, 5;

-- Situazione di oggi (ora di Roma) per sensore/stand: totale del giorno e ultima ora.
CREATE OR REPLACE VIEW sensor.v_camera_today
WITH (security_invoker = true) AS
SELECT c.camera_id,
       c.camera_code,
       sc.stand_id,
       s.stand_code,
       c.pavilion_id,
       coalesce(sum(cc.persons), 0)::integer AS persons_today,
       coalesce(sum(cc.persons) FILTER (WHERE cc.bucket_start >= now() - interval '1 hour'), 0)::integer AS persons_last_hour,
       max(cc.bucket_start)                  AS last_bucket
FROM sensor.camera c
JOIN sensor.stand_camera sc ON sc.camera_id = c.camera_id
JOIN core.stand s          ON s.stand_id = sc.stand_id
LEFT JOIN sensor.camera_count cc
       ON cc.camera_id = c.camera_id
      AND (cc.bucket_start AT TIME ZONE 'Europe/Rome')::date = (now() AT TIME ZONE 'Europe/Rome')::date
      AND cc.bucket_start <= now()
GROUP BY c.camera_id, c.camera_code, sc.stand_id, s.stand_code, c.pavilion_id;

-- Permessi: lettura per app/flussi (arcade_app) e Power BI (arcade_bi); scrittura dei conteggi per l'ETL.
GRANT USAGE ON SCHEMA sensor TO arcade_app, arcade_bi, arcade_etl;
GRANT SELECT ON ALL TABLES IN SCHEMA sensor TO arcade_app, arcade_bi, arcade_etl;
GRANT INSERT, UPDATE, DELETE ON sensor.camera_count TO arcade_etl;

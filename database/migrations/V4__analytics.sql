-- =====================================================================
-- ARCADE Milano - V4: schema analytics (stella + KPI) e schema portal
--
-- Regola: OGNI KPI e' definito qui, una volta sola. API, portale e Power BI
-- leggono queste viste: nessuna formula duplicata altrove.
--
-- Convenzioni sui KPI (proposte, da validare - vedi docs/data-model.md):
--   * ricavo = valore CONTRATTUALIZZATO netto sconto, IVA esclusa, solo contratti SIGNED
--   * incassato = somma pagamenti con paid_on (rimborsi sottratti), misura separata
--   * misure di visitatori distinte: venduti, validati, passaggi, ingressi-giorno, presenze STIMATE
--   * i denominatori nulli producono NULL, mai 0
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS portal;

-- ---------------------------------------------------------------------
-- 1. DIMENSIONI
-- ---------------------------------------------------------------------
CREATE VIEW analytics.dim_edition AS
SELECT e.edition_id, e.year, e.name, e.status, e.timezone,
       min(d.day_date) AS first_day, max(d.day_date) AS last_day,
       count(d.day_date)::int AS event_days
FROM core.edition e
LEFT JOIN core.edition_day d USING (edition_id)
GROUP BY e.edition_id;

CREATE VIEW analytics.dim_date AS
SELECT d.edition_id, d.day_date, d.day_number, d.opens_at, d.closes_at,
       extract(isodow FROM d.day_date)::int AS iso_weekday
FROM core.edition_day d;

CREATE VIEW analytics.dim_hour AS
SELECT h::smallint AS hour_of_day, lpad(h::text, 2, '0') || ':00' AS hour_label
FROM generate_series(0, 23) AS h;

CREATE VIEW analytics.dim_pavilion AS
SELECT pavilion_id, code AS pavilion_code, name AS pavilion_name FROM core.pavilion;

-- Stand FISICO (stabile). L'occupazione per edizione e' dim_stand_edition.
CREATE VIEW analytics.dim_stand AS
SELECT s.stand_id, s.stand_code, s.pavilion_id, p.code AS pavilion_code,
       s.sqm, s.position_type
FROM core.stand s JOIN core.pavilion p USING (pavilion_id);

CREATE VIEW analytics.dim_stand_edition AS
SELECT se.stand_edition_id, se.stand_id, se.edition_id, se.commercial_status
FROM core.stand_edition se;

-- Nessun dato di contatto: solo identita' e classificazione.
CREATE VIEW analytics.dim_exhibitor AS
SELECT x.exhibitor_id, x.exhibitor_code, x.legal_name, c.name AS category, x.city
FROM core.exhibitor x JOIN core.exhibitor_category c USING (category_id);

CREATE VIEW analytics.dim_ticket_type AS
SELECT ticket_type_id, code AS ticket_type_code, name AS ticket_type_name, is_free, is_multi_day
FROM core.ticket_type;

CREATE VIEW analytics.dim_channel AS
SELECT channel_id, code AS channel_code, name AS channel_name FROM core.sales_channel;

-- ---------------------------------------------------------------------
-- 2. FATTI
-- ---------------------------------------------------------------------
-- Granularita': 1 riga contratto. Il ricavo si somma SOLO su questo fatto.
-- net_amount_allocated ripartisce lo sconto del contratto pro-quota sulle righe (senza arrotondare),
-- cosi' la somma delle righe coincide esattamente con contract.net_amount.
CREATE VIEW analytics.fact_contract_line AS
SELECT cl.contract_line_id, cl.contract_id, c.edition_id, c.exhibitor_id,
       cs.stand_edition_id, se.stand_id, cl.line_type, cl.price_item_id, cl.quantity,
       cl.amount AS list_amount,
       CASE WHEN c.list_amount > 0 THEN cl.amount * c.net_amount / c.list_amount ELSE 0 END
         AS net_amount_allocated
FROM core.contract_line cl
JOIN core.contract c ON c.contract_id = cl.contract_id AND c.status = 'SIGNED'
LEFT JOIN core.contract_stand cs ON cs.contract_stand_id = cl.contract_stand_id
LEFT JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id;

-- Granularita': 1 pagamento. Misura "incassato"; non sommare al contrattualizzato.
CREATE VIEW analytics.fact_payment AS
SELECT p.payment_id, p.contract_id, c.edition_id, c.exhibitor_id, p.kind,
       p.due_on, p.due_amount, p.paid_on, p.paid_amount, p.paid_amount_is_assumed,
       CASE WHEN p.paid_on IS NULL THEN NULL
            WHEN p.kind = 'REFUND' THEN -p.paid_amount
            ELSE p.paid_amount END AS cash_amount,
       ps.payment_state
FROM core.payment p
JOIN core.contract c ON c.contract_id = p.contract_id AND c.status = 'SIGNED'
JOIN dq.v_payment_status ps ON ps.payment_id = p.payment_id;

-- Granularita': 1 biglietto. "venduti" = COUNT(*); "persone" = SUM(persons).
CREATE VIEW analytics.fact_ticket AS
SELECT t.ticket_id, t.edition_id, t.ticket_type_id, o.channel_id, o.purchased_at,
       t.valid_day, t.price, t.persons, t.age_band_id, t.province_id, t.discount_code_id,
       EXISTS (SELECT 1 FROM core.gate_reading gr
                WHERE gr.ticket_id = t.ticket_id AND gr.result = 'OK') AS is_validated
FROM core.ticket t
JOIN core.ticket_order o ON o.order_id = t.order_id;

-- Granularita': 1 lettura al varco, con giorno/ora LOCALI dell'edizione.
-- is_first_ok_of_day      : primo passaggio OK di un biglietto RISOLTO nel giorno (-> ingressi unici del giorno)
-- is_first_ok_of_day_pav  : idem per padiglione. I passaggi con codice orfano (ticket_id NULL) NON sono
--                           ingressi unici: restano visibili in passes_orphan e nelle presenze stimate.

CREATE VIEW analytics.fact_gate_reading AS
WITH r AS (
  SELECT gr.reading_id, gr.edition_id, gr.gate_id, g.pavilion_id, gr.ticket_id, gr.ticket_code,
         gr.read_at, gr.result, gr.direction,
         (gr.read_at AT TIME ZONE e.timezone)::date AS local_date,
         extract(hour FROM gr.read_at AT TIME ZONE e.timezone)::smallint AS local_hour,
         (gr.ticket_id IS NULL) AS is_orphan
  FROM core.gate_reading gr
  JOIN core.gate g ON g.gate_id = gr.gate_id
  JOIN core.edition e ON e.edition_id = gr.edition_id
)
SELECT r.*,
       (r.result = 'OK' AND NOT r.is_orphan AND row_number() OVER (
            PARTITION BY r.edition_id, r.ticket_code, r.local_date, r.result
            ORDER BY r.read_at, r.reading_id) = 1) AS is_first_ok_of_day,
       (r.result = 'OK' AND NOT r.is_orphan AND row_number() OVER (
            PARTITION BY r.edition_id, r.pavilion_id, r.ticket_code, r.local_date, r.result
            ORDER BY r.read_at, r.reading_id) = 1) AS is_first_ok_of_day_pav
FROM r;

-- Granularita': stand x giorno x ora. Una sola sorgente per cella: se l'app ha eventi
-- puntuali per quella cella vincono, altrimenti vale l'aggregato orario. Mai somma cieca.
-- visits = scansioni/visite, NON contatti qualificati.
CREATE VIEW analytics.fact_stand_visits AS
WITH app AS (
  SELECT sv.stand_edition_id,
         (sv.visited_at AT TIME ZONE e.timezone)::date AS visit_date,
         extract(hour FROM sv.visited_at AT TIME ZONE e.timezone)::smallint AS visit_hour,
         count(*)::int AS visits
  FROM core.stand_visit sv
  JOIN core.stand_edition se ON se.stand_edition_id = sv.stand_edition_id
  JOIN core.edition e ON e.edition_id = se.edition_id
  GROUP BY 1, 2, 3
), legacy AS (
  SELECT h.stand_edition_id, h.visit_date, h.visit_hour, h.scans AS visits
  FROM core.stand_visit_hourly h
  WHERE NOT EXISTS (SELECT 1 FROM app a
                     WHERE a.stand_edition_id = h.stand_edition_id
                       AND a.visit_date = h.visit_date AND a.visit_hour = h.visit_hour)
), u AS (
  SELECT stand_edition_id, visit_date, visit_hour, visits, 'APP'::text AS origin FROM app
  UNION ALL
  SELECT stand_edition_id, visit_date, visit_hour, visits, 'HOURLY_AGGREGATE'::text FROM legacy
)
SELECT u.stand_edition_id, se.stand_id, se.edition_id, own.exhibitor_id,
       u.visit_date, u.visit_hour, u.visits, u.origin
FROM u
JOIN core.stand_edition se ON se.stand_edition_id = u.stand_edition_id
LEFT JOIN LATERAL (
  SELECT c.exhibitor_id
  FROM core.contract_stand cs
  JOIN core.contract c ON c.contract_id = cs.contract_id AND c.status = 'SIGNED'
  WHERE cs.stand_edition_id = u.stand_edition_id AND cs.released_at IS NULL
  LIMIT 1) own ON true;

-- Granularita': 1 contatto. Senza email/hash. Sono contatti RACCOLTI; "qualificato" solo se is_qualified.
CREATE VIEW analytics.fact_stand_lead AS
SELECT l.lead_id, l.stand_edition_id, se.stand_id, se.edition_id, l.exhibitor_id,
       l.captured_at, l.marketing_consent, l.is_qualified, l.review_status,
       l.age_band_id, l.province_id, l.interest_id
FROM core.stand_lead l
JOIN core.stand_edition se ON se.stand_edition_id = l.stand_edition_id;

-- ---------------------------------------------------------------------
-- 3. PRESENZE STIMATE (KPI 2)
-- ---------------------------------------------------------------------
-- METODO "finestra di permanenza": un biglietto e' considerato presente in un padiglione
-- se ha una lettura OK a un varco di quel padiglione negli ultimi p_dwell_minutes.
-- LIMITI (da dichiarare sempre): nessuna uscita registrata; D e' un'ipotesi (default 90',
-- da validare); lo stesso biglietto puo' contare in piu' padiglioni -> NON sommare i padiglioni:
-- la riga con pavilion_id NULL e' il totale evento con biglietti distinti. Conta biglietti, non persone.
-- Risultato = stima, mai un conteggio certo.
CREATE FUNCTION analytics.presence_estimate(
    p_edition smallint, p_dwell_minutes integer DEFAULT 90, p_bucket_minutes integer DEFAULT 15)
RETURNS TABLE (edition_id smallint, pavilion_id smallint, bucket_end timestamptz,
               est_present integer, method text, dwell_minutes integer)
LANGUAGE sql STABLE
AS $$
  WITH ed AS (
    SELECT e.edition_id AS eid, e.timezone AS tz FROM core.edition e WHERE e.edition_id = p_edition
  ), b AS (
    SELECT ed.eid, gs AS bucket_end
    FROM ed
    JOIN core.edition_day d ON d.edition_id = ed.eid
    CROSS JOIN LATERAL generate_series(
         ((d.day_date + d.opens_at)  AT TIME ZONE ed.tz) + make_interval(mins => p_bucket_minutes),
         ((d.day_date + d.closes_at) AT TIME ZONE ed.tz),
         make_interval(mins => p_bucket_minutes)) AS gs
  ), reads AS (
    SELECT gr.ticket_code, g.pavilion_id AS pav, gr.read_at
    FROM core.gate_reading gr
    JOIN core.gate g ON g.gate_id = gr.gate_id
    WHERE gr.edition_id = p_edition AND gr.result = 'OK'
  )
  SELECT b.eid, p.pavilion_id, b.bucket_end,
         (SELECT count(DISTINCT r.ticket_code)::int FROM reads r
           WHERE r.pav = p.pavilion_id
             AND r.read_at >  b.bucket_end - make_interval(mins => p_dwell_minutes)
             AND r.read_at <= b.bucket_end),
         'DWELL_WINDOW'::text, p_dwell_minutes
  FROM b CROSS JOIN core.pavilion p
  UNION ALL
  SELECT b.eid, NULL::smallint, b.bucket_end,
         (SELECT count(DISTINCT r.ticket_code)::int FROM reads r
           WHERE r.read_at >  b.bucket_end - make_interval(mins => p_dwell_minutes)
             AND r.read_at <= b.bucket_end),
         'DWELL_WINDOW'::text, p_dwell_minutes
  FROM b
$$;

-- Parametri di default (D=90', bucket 15'), per le edizioni con letture.
CREATE VIEW analytics.fact_presence_estimate AS
SELECT p.*
FROM core.edition e
CROSS JOIN LATERAL analytics.presence_estimate(e.edition_id) p
WHERE EXISTS (SELECT 1 FROM core.gate_reading gr WHERE gr.edition_id = e.edition_id);

-- Picco STIMATO per giorno e padiglione (NULL = totale evento).
CREATE VIEW analytics.kpi_presence_peak AS
SELECT DISTINCT ON (f.edition_id, (f.bucket_end AT TIME ZONE e.timezone)::date, f.pavilion_id)
       f.edition_id,
       (f.bucket_end AT TIME ZONE e.timezone)::date AS day_date,
       f.pavilion_id,
       f.est_present AS peak_est_present,
       f.bucket_end  AS peak_bucket_end,
       f.method, f.dwell_minutes,
       true AS is_estimate
FROM analytics.fact_presence_estimate f
JOIN core.edition e ON e.edition_id = f.edition_id
ORDER BY f.edition_id, (f.bucket_end AT TIME ZONE e.timezone)::date, f.pavilion_id,
         f.est_present DESC, f.bucket_end;

-- ---------------------------------------------------------------------
-- 4. KPI 1 - VISITATORI (misure distinte)
-- ---------------------------------------------------------------------
CREATE VIEW analytics.kpi_visitors_daily AS
SELECT edition_id, local_date AS day_date,
       count(*)                                          AS passes_total,
       count(*) FILTER (WHERE result = 'OK')             AS passes_ok,
       count(*) FILTER (WHERE result = 'KO')             AS passes_ko,
       count(*) FILTER (WHERE is_orphan)                 AS passes_orphan,
       count(*) FILTER (WHERE is_first_ok_of_day)        AS unique_entries
FROM analytics.fact_gate_reading
GROUP BY edition_id, local_date;

-- tickets_sold        : biglietti venduti (righe). Un Family = 1 biglietto
-- persons_sold        : persone coperte dai biglietti (Family = 4)
-- tickets_validated   : biglietti DISTINTI con almeno un passaggio OK
-- unique_daily_entries: somma giornaliera dei biglietti distinti entrati (un abbonamento 3gg puo' valere 3)
-- passes_total        : letture ai varchi (include KO, orfani, rientri e piu' padiglioni)
-- Visitatori unici (persone) NON calcolabili: nessun identificativo di persona nei dati.
CREATE VIEW analytics.kpi_visitors_edition AS
SELECT e.edition_id, e.year,
       COALESCE(t.tickets_sold, 0)      AS tickets_sold,
       COALESCE(t.persons_sold, 0)      AS persons_sold,
       COALESCE(t.tickets_free, 0)      AS tickets_free,
       COALESCE(t.tickets_validated, 0) AS tickets_validated,
       round(100.0 * t.tickets_validated / NULLIF(t.tickets_sold, 0), 2) AS validation_rate_pct,
       COALESCE(d.unique_daily_entries, 0) AS unique_daily_entries,
       COALESCE(d.passes_total, 0)      AS passes_total,
       COALESCE(d.passes_orphan, 0)     AS passes_orphan
FROM core.edition e
LEFT JOIN (
  SELECT ft.edition_id, count(*) AS tickets_sold, sum(ft.persons) AS persons_sold,
         count(*) FILTER (WHERE ft.price = 0) AS tickets_free,
         count(*) FILTER (WHERE ft.is_validated) AS tickets_validated
  FROM analytics.fact_ticket ft GROUP BY ft.edition_id) t ON t.edition_id = e.edition_id
LEFT JOIN (
  SELECT edition_id, sum(unique_entries) AS unique_daily_entries, sum(passes_total) AS passes_total,
         sum(passes_orphan) AS passes_orphan
  FROM analytics.kpi_visitors_daily GROUP BY edition_id) d ON d.edition_id = e.edition_id;

-- ---------------------------------------------------------------------
-- 5. KPI 3 - SATURAZIONE
-- ---------------------------------------------------------------------
-- Venduto = stand con assegnazione attiva a contratto SIGNED.
-- Commercializzabile = tutti gli stand dell'edizione tranne NOT_SELLABLE.
-- FREE (gratuiti) e RESERVED non sono "venduti": occupancy_pct li include tra gli occupati (decisione da validare).
-- pavilion_id NULL = totale edizione.
CREATE VIEW analytics.kpi_saturation AS
WITH base AS (
  SELECT se.edition_id, s.pavilion_id, s.sqm, se.commercial_status,
         EXISTS (SELECT 1 FROM core.contract_stand cs
                   JOIN core.contract c ON c.contract_id = cs.contract_id AND c.status = 'SIGNED'
                  WHERE cs.stand_edition_id = se.stand_edition_id AND cs.released_at IS NULL) AS is_sold
  FROM core.stand_edition se JOIN core.stand s ON s.stand_id = se.stand_id
)
SELECT edition_id, pavilion_id,
       count(*) FILTER (WHERE commercial_status <> 'NOT_SELLABLE')                    AS stands_sellable,
       count(*) FILTER (WHERE is_sold)                                                AS stands_sold,
       COALESCE(sum(sqm) FILTER (WHERE commercial_status <> 'NOT_SELLABLE'), 0)       AS sqm_sellable,
       COALESCE(sum(sqm) FILTER (WHERE is_sold), 0)                                   AS sqm_sold,
       COALESCE(sum(sqm) FILTER (WHERE commercial_status = 'RESERVED' AND NOT is_sold), 0) AS sqm_reserved,
       COALESCE(sum(sqm) FILTER (WHERE commercial_status = 'FREE'), 0)                AS sqm_free,
       round(100.0 * sum(sqm) FILTER (WHERE is_sold)
             / NULLIF(sum(sqm) FILTER (WHERE commercial_status <> 'NOT_SELLABLE'), 0), 2) AS saturation_pct,
       round(100.0 * sum(sqm) FILTER (WHERE is_sold OR commercial_status = 'FREE')
             / NULLIF(sum(sqm) FILTER (WHERE commercial_status <> 'NOT_SELLABLE'), 0), 2) AS occupancy_pct
FROM base
GROUP BY GROUPING SETS ((edition_id, pavilion_id), (edition_id));

-- ---------------------------------------------------------------------
-- 6. KPI 4 - COMMERCIALE (contrattualizzato, incassato, ricavo/m2)
-- ---------------------------------------------------------------------
-- revenue_per_sqm = (SPACE+SURCHARGE netto sconto) / m2 degli stand venduti.
-- Extra e sponsorizzazioni sono ESCLUSI dal numeratore e riportati a parte.
-- parts_diff deve essere 0: controllo che la ripartizione non perda/duplichi importi.
CREATE VIEW analytics.kpi_commercial_edition AS
SELECT e.edition_id, e.year,
       COALESCE(c.contracts_signed, 0) AS contracts_signed,
       COALESCE(c.exhibitors, 0)       AS exhibitors,
       COALESCE(c.contracted_net, 0)   AS contracted_net,
       COALESCE(f.space_net, 0)        AS space_net,
       COALESCE(f.extras_net, 0)       AS extras_net,
       COALESCE(f.sponsorship_net, 0)  AS sponsorship_net,
       COALESCE(c.contracted_net, 0) - COALESCE(f.space_net, 0) - COALESCE(f.extras_net, 0)
         - COALESCE(f.sponsorship_net, 0) AS parts_diff,
       COALESCE(p.cash_collected, 0)   AS cash_collected,
       sat.sqm_sold,
       round(f.space_net / NULLIF(sat.sqm_sold, 0), 2) AS revenue_per_sqm,
       round(100.0 * p.contracts_deposit_paid / NULLIF(c.contracts_signed, 0), 2) AS deposit_paid_pct,
       q.quotes_sent,
       round(100.0 * q.quotes_converted / NULLIF(q.quotes_sent, 0), 2) AS quote_conversion_pct
FROM core.edition e
LEFT JOIN (SELECT edition_id, count(*) AS contracts_signed, count(DISTINCT exhibitor_id) AS exhibitors,
                  sum(net_amount) AS contracted_net
             FROM core.contract WHERE status = 'SIGNED' GROUP BY edition_id) c USING (edition_id)
LEFT JOIN (SELECT edition_id,
                  sum(net_amount_allocated) FILTER (WHERE line_type IN ('SPACE','SURCHARGE')) AS space_net,
                  sum(net_amount_allocated) FILTER (WHERE line_type = 'EXTRA')               AS extras_net,
                  sum(net_amount_allocated) FILTER (WHERE line_type = 'SPONSORSHIP')         AS sponsorship_net
             FROM analytics.fact_contract_line GROUP BY edition_id) f USING (edition_id)
LEFT JOIN (SELECT edition_id, sum(cash_amount) AS cash_collected,
                  count(DISTINCT contract_id) FILTER (WHERE kind = 'DEPOSIT' AND paid_on IS NOT NULL)
                    AS contracts_deposit_paid
             FROM analytics.fact_payment GROUP BY edition_id) p USING (edition_id)
LEFT JOIN (SELECT edition_id, count(*) FILTER (WHERE status <> 'DRAFT') AS quotes_sent,
                  count(*) FILTER (WHERE status = 'CONVERTED') AS quotes_converted
             FROM core.quote GROUP BY edition_id) q USING (edition_id)
LEFT JOIN analytics.kpi_saturation sat ON sat.edition_id = e.edition_id AND sat.pavilion_id IS NULL;

-- Ricavo di spazio per padiglione (le righe extra/sponsor non hanno padiglione).
CREATE VIEW analytics.kpi_space_revenue_pavilion AS
SELECT sat.edition_id, sat.pavilion_id, sat.sqm_sold, sat.saturation_pct,
       COALESCE(r.space_net, 0) AS space_net,
       round(r.space_net / NULLIF(sat.sqm_sold, 0), 2) AS revenue_per_sqm
FROM analytics.kpi_saturation sat
LEFT JOIN (SELECT f.edition_id, s.pavilion_id, sum(f.net_amount_allocated) AS space_net
             FROM analytics.fact_contract_line f
             JOIN core.stand s ON s.stand_id = f.stand_id
            WHERE f.line_type IN ('SPACE','SURCHARGE')
            GROUP BY f.edition_id, s.pavilion_id) r
       ON r.edition_id = sat.edition_id AND r.pavilion_id = sat.pavilion_id
WHERE sat.pavilion_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 7. KPI PER ESPOSITORE E EDIZIONE (+ KPI 5 e confronto con edizione precedente)
-- ---------------------------------------------------------------------
-- cost_per_qualified_contact = NON CALCOLABILE (costi attribuibili e definizione di "qualificato" non forniti, Q-11): NULL.
-- Indicatore sostitutivo con nome esplicito: contract_value_per_visit = contrattualizzato netto / visite.
CREATE VIEW analytics.kpi_exhibitor_edition AS
WITH ct AS (
  SELECT c.edition_id, e.year, c.exhibitor_id, count(*) AS contracts, sum(c.net_amount) AS contracted_net
  FROM core.contract c JOIN core.edition e ON e.edition_id = c.edition_id
  WHERE c.status = 'SIGNED' GROUP BY c.edition_id, e.year, c.exhibitor_id
), fl AS (
  SELECT edition_id, exhibitor_id,
         sum(net_amount_allocated) FILTER (WHERE line_type IN ('SPACE','SURCHARGE')) AS space_net,
         sum(net_amount_allocated) FILTER (WHERE line_type = 'SPONSORSHIP')         AS sponsorship_net
  FROM analytics.fact_contract_line GROUP BY 1, 2
), sq AS (
  SELECT c.edition_id, c.exhibitor_id, sum(s.sqm) AS sqm
  FROM core.contract_stand cs
  JOIN core.contract c ON c.contract_id = cs.contract_id AND c.status = 'SIGNED'
  JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
  JOIN core.stand s ON s.stand_id = se.stand_id
  WHERE cs.released_at IS NULL GROUP BY 1, 2
), v AS (
  SELECT edition_id, exhibitor_id, sum(visits) AS visits
  FROM analytics.fact_stand_visits WHERE exhibitor_id IS NOT NULL GROUP BY 1, 2
), ld AS (
  SELECT edition_id, exhibitor_id, count(*) AS leads_collected,
         count(*) FILTER (WHERE is_qualified) AS leads_qualified
  FROM analytics.fact_stand_lead WHERE review_status = 'OK' GROUP BY 1, 2
), m AS (
  SELECT ct.edition_id, ct.year, ct.exhibitor_id, ct.contracts, ct.contracted_net,
         fl.space_net, fl.sponsorship_net, sq.sqm,
         round(fl.space_net / NULLIF(sq.sqm, 0), 2) AS revenue_per_sqm,
         v.visits, round(v.visits / NULLIF(sq.sqm, 0), 2) AS visits_per_sqm,
         COALESCE(ld.leads_collected, 0) AS leads_collected,
         COALESCE(ld.leads_qualified, 0) AS leads_qualified,
         round(ct.contracted_net / NULLIF(v.visits, 0), 2) AS contract_value_per_visit,
         NULL::numeric AS cost_per_qualified_contact
  FROM ct
  LEFT JOIN fl USING (edition_id, exhibitor_id)
  LEFT JOIN sq USING (edition_id, exhibitor_id)
  LEFT JOIN v  USING (edition_id, exhibitor_id)
  LEFT JOIN ld USING (edition_id, exhibitor_id)
)
SELECT m.*,
       lag(m.year)           OVER w AS prev_year,
       lag(m.contracted_net) OVER w AS prev_contracted_net,
       round(100.0 * (m.contracted_net - lag(m.contracted_net) OVER w)
             / NULLIF(lag(m.contracted_net) OVER w, 0), 2) AS contracted_net_delta_pct,
       lag(m.visits)         OVER w AS prev_visits,
       round(100.0 * (m.visits - lag(m.visits) OVER w) / NULLIF(lag(m.visits) OVER w, 0), 2) AS visits_delta_pct
FROM m
WINDOW w AS (PARTITION BY m.exhibitor_id ORDER BY m.year);

-- ---------------------------------------------------------------------
-- 8. CONFRONTO TRA EDIZIONI E RINNOVI
-- ---------------------------------------------------------------------
-- Le variazioni sono NULL per le edizioni senza dati (es. 2026 in vendita, senza contratti): niente falsi -100%.
CREATE VIEW analytics.kpi_edition_comparison AS
SELECT c.edition_id, c.year,
       c.contracted_net, c.revenue_per_sqm, c.exhibitors, s.saturation_pct,
       v.tickets_sold, v.tickets_validated, v.unique_daily_entries,
       lag(c.year) OVER w AS prev_year,
       round(100.0 * (NULLIF(c.contracted_net, 0) - lag(c.contracted_net) OVER w)
             / NULLIF(lag(c.contracted_net) OVER w, 0), 2)        AS contracted_net_delta_pct,
       round(100.0 * (c.revenue_per_sqm - lag(c.revenue_per_sqm) OVER w)
             / NULLIF(lag(c.revenue_per_sqm) OVER w, 0), 2)       AS revenue_per_sqm_delta_pct,
       round(100.0 * (NULLIF(v.tickets_sold, 0) - lag(v.tickets_sold) OVER w)
             / NULLIF(lag(v.tickets_sold) OVER w, 0), 2)          AS tickets_sold_delta_pct,
       round(100.0 * (NULLIF(v.unique_daily_entries, 0) - lag(v.unique_daily_entries) OVER w)
             / NULLIF(lag(v.unique_daily_entries) OVER w, 0), 2)  AS unique_entries_delta_pct
FROM analytics.kpi_commercial_edition c
JOIN analytics.kpi_visitors_edition v ON v.edition_id = c.edition_id
LEFT JOIN analytics.kpi_saturation s ON s.edition_id = c.edition_id AND s.pavilion_id IS NULL
WINDOW w AS (ORDER BY c.year);

-- Rinnovo = espositore con contratto SIGNED nell'edizione N che ha contratto SIGNED anche in N+1.
-- NULL quando N+1 non ha ancora contratti (tasso non calcolabile).
CREATE VIEW analytics.kpi_renewal_edition AS
SELECT e.edition_id, e.year,
       count(DISTINCT c.exhibitor_id) AS exhibitors,
       count(DISTINCT c.exhibitor_id) FILTER (WHERE EXISTS (
           SELECT 1 FROM core.contract c2 JOIN core.edition e2 ON e2.edition_id = c2.edition_id
            WHERE c2.exhibitor_id = c.exhibitor_id AND c2.status = 'SIGNED' AND e2.year = e.year + 1)) AS renewed_next,
       CASE WHEN EXISTS (SELECT 1 FROM core.contract c3 JOIN core.edition e3 ON e3.edition_id = c3.edition_id
                          WHERE c3.status = 'SIGNED' AND e3.year = e.year + 1)
            THEN round(100.0 * count(DISTINCT c.exhibitor_id) FILTER (WHERE EXISTS (
                   SELECT 1 FROM core.contract c2 JOIN core.edition e2 ON e2.edition_id = c2.edition_id
                    WHERE c2.exhibitor_id = c.exhibitor_id AND c2.status = 'SIGNED' AND e2.year = e.year + 1))
                 / NULLIF(count(DISTINCT c.exhibitor_id), 0), 2) END AS renewal_rate_pct
FROM core.edition e
JOIN core.contract c ON c.edition_id = e.edition_id AND c.status = 'SIGNED'
GROUP BY e.edition_id, e.year;

-- ---------------------------------------------------------------------
-- 9. QUALITA' DEI DATI (pagina 5 del report) E RICONCILIAZIONE
-- ---------------------------------------------------------------------
CREATE VIEW analytics.kpi_data_quality_batch AS
SELECT b.batch_id, ds.code AS source_code, b.file_name, b.status, b.started_at,
       b.rows_read, b.rows_loaded, b.rows_quarantined, b.rows_rejected,
       COALESCE(a.anomalies, 0)      AS anomalies,
       COALESCE(a.open_anomalies, 0) AS open_anomalies,
       round(100.0 * COALESCE(a.anomalies, 0) / NULLIF(b.rows_read, 0), 2) AS anomaly_pct
FROM dq.import_batch b
JOIN core.data_source ds ON ds.source_id = b.source_id
LEFT JOIN (SELECT batch_id, count(*) AS anomalies,
                  count(*) FILTER (WHERE resolution_status = 'OPEN') AS open_anomalies
             FROM dq.anomaly GROUP BY batch_id) a ON a.batch_id = b.batch_id;

CREATE VIEW analytics.kpi_data_quality_anomaly AS
SELECT ds.code AS source_code, a.rule_code, r.area, a.severity, a.action_applied,
       a.resolution_status, count(*) AS anomalies
FROM dq.anomaly a
JOIN dq.rule r ON r.rule_code = a.rule_code
JOIN core.data_source ds ON ds.source_id = a.source_id
GROUP BY ds.code, a.rule_code, r.area, a.severity, a.action_applied, a.resolution_status;

-- Confronto tra tabelle core e fatti/KPI: stesso fenomeno, stesso numero. Alimenta dq.reconciliation_result.
CREATE VIEW analytics.reconciliation_current AS
SELECT 'REC-02'::text AS check_code, e.edition_id, 'core.ticket'::text AS layer_a,
       (SELECT count(*) FROM core.ticket t WHERE t.edition_id = e.edition_id)::numeric AS value_a,
       'analytics.fact_ticket'::text AS layer_b,
       (SELECT count(*) FROM analytics.fact_ticket f WHERE f.edition_id = e.edition_id)::numeric AS value_b
FROM core.edition e
UNION ALL
SELECT 'REC-03', e.edition_id, 'core.gate_reading',
       (SELECT count(*) FROM core.gate_reading g WHERE g.edition_id = e.edition_id)::numeric,
       'analytics.kpi_visitors_edition.passes_total',
       (SELECT passes_total FROM analytics.kpi_visitors_edition k WHERE k.edition_id = e.edition_id)::numeric
FROM core.edition e
UNION ALL
SELECT 'REC-04', e.edition_id, 'core.contract.list_amount',
       COALESCE((SELECT sum(list_amount) FROM core.contract c WHERE c.edition_id = e.edition_id AND c.status = 'SIGNED'), 0),
       'core.contract_line.amount',
       COALESCE((SELECT sum(l.amount) FROM core.contract_line l JOIN core.contract c ON c.contract_id = l.contract_id
                  WHERE c.edition_id = e.edition_id AND c.status = 'SIGNED'), 0)
FROM core.edition e
UNION ALL
SELECT 'REC-05', e.edition_id, 'core.contract.net_amount',
       COALESCE((SELECT sum(net_amount) FROM core.contract c WHERE c.edition_id = e.edition_id AND c.status = 'SIGNED'), 0),
       'analytics.kpi_commercial_edition.parts',
       (SELECT space_net + extras_net + sponsorship_net FROM analytics.kpi_commercial_edition k WHERE k.edition_id = e.edition_id)
FROM core.edition e
UNION ALL
SELECT 'REC-07', e.edition_id, 'core.stand_edition SOLD',
       (SELECT count(*) FROM core.stand_edition se WHERE se.edition_id = e.edition_id AND se.commercial_status = 'SOLD')::numeric,
       'analytics.kpi_saturation.stands_sold',
       (SELECT stands_sold FROM analytics.kpi_saturation k WHERE k.edition_id = e.edition_id AND k.pavilion_id IS NULL)::numeric
FROM core.edition e;

CREATE VIEW analytics.reconciliation_status AS
SELECT check_code, edition_id, layer_a, value_a, layer_b, value_b,
       CASE WHEN abs(COALESCE(value_a, 0) - COALESCE(value_b, 0)) < 0.005 THEN 'MATCH' ELSE 'MISMATCH' END AS status
FROM analytics.reconciliation_current;

-- ---------------------------------------------------------------------
-- 10. SCHEMA portal: l'UNICA superficie di lettura per l'area espositori
--     Viste con diritti del proprietario + filtro esplicito su exhibitor_id della sessione
--     (fail-closed: sessione senza app.exhibitor_id => nessuna riga). In piu' RLS sulle tabelle base.
-- ---------------------------------------------------------------------
CREATE VIEW portal.v_my_contracts WITH (security_barrier = true) AS
SELECT c.contract_id, c.contract_number, e.year AS edition_year, c.status, c.signed_on,
       c.list_amount, c.discount_pct, c.net_amount, c.is_renewal,
       (SELECT string_agg(s.stand_code, ', ' ORDER BY s.stand_code)
          FROM core.contract_stand cs
          JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
          JOIN core.stand s ON s.stand_id = se.stand_id
         WHERE cs.contract_id = c.contract_id AND cs.released_at IS NULL) AS stands,
       pd.due_on  AS deposit_due_on,  pd.paid_on AS deposit_paid_on,
       pb.due_on  AS balance_due_on,  pb.paid_on AS balance_paid_on
FROM core.contract c
JOIN core.edition e ON e.edition_id = c.edition_id
LEFT JOIN core.payment pd ON pd.contract_id = c.contract_id AND pd.kind = 'DEPOSIT'
LEFT JOIN core.payment pb ON pb.contract_id = c.contract_id AND pb.kind = 'BALANCE'
WHERE c.exhibitor_id = core.current_exhibitor_id();

CREATE VIEW portal.v_my_visits_hourly WITH (security_barrier = true) AS
SELECT e.year AS edition_year, s.stand_code, f.visit_date, f.visit_hour, f.visits, f.origin
FROM analytics.fact_stand_visits f
JOIN core.edition e ON e.edition_id = f.edition_id
JOIN core.stand s ON s.stand_id = f.stand_id
WHERE f.exhibitor_id = core.current_exhibitor_id();

CREATE VIEW portal.v_my_kpi WITH (security_barrier = true) AS
SELECT k.year AS edition_year, k.contracts, k.contracted_net, k.sqm, k.revenue_per_sqm,
       k.visits, k.visits_per_sqm, k.leads_collected, k.leads_qualified,
       k.contract_value_per_visit, k.prev_year, k.contracted_net_delta_pct, k.visits_delta_pct
FROM analytics.kpi_exhibitor_edition k
WHERE k.exhibitor_id = core.current_exhibitor_id();

-- Confronto di mercato SOLO aggregato e anonimo: nessuna riga se nella categoria ci sono meno di 5 espositori.
CREATE VIEW portal.v_benchmark_visits_per_sqm WITH (security_barrier = true) AS
SELECT k.year AS edition_year, x.category,
       count(*) AS exhibitors_in_group,
       round(avg(k.visits_per_sqm), 2) AS avg_visits_per_sqm
FROM analytics.kpi_exhibitor_edition k
JOIN analytics.dim_exhibitor x ON x.exhibitor_id = k.exhibitor_id
WHERE k.visits_per_sqm IS NOT NULL AND core.current_exhibitor_id() IS NOT NULL
GROUP BY k.year, x.category
HAVING count(*) >= 5;

-- ---------------------------------------------------------------------
-- 11. GRANT
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA analytics TO arcade_bi, arcade_app;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO arcade_bi, arcade_app;
GRANT EXECUTE ON FUNCTION analytics.presence_estimate(smallint, integer, integer) TO arcade_app;
-- Power BI: SOLO analytics. Le viste girano con i diritti del proprietario; nessun accesso a core/dq.

GRANT USAGE ON SCHEMA portal TO arcade_portal, arcade_app;
GRANT SELECT ON ALL TABLES IN SCHEMA portal TO arcade_portal, arcade_app;

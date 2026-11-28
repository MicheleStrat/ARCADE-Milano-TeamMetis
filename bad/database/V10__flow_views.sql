-- =====================================================================
-- ARCADE Milano - V10 (team BAD): viste per i flussi Power Automate
--
-- PERCHE'
--   Il connettore PostgreSQL di Power Automate non riesce a filtrare
--   sulle colonne di tipo date ("Get rows" con due_on le '2025-08-01'
--   -> BadRequest), mentre su testo, numeri e booleani funziona.
--   I promemoria BAD-05-03 (pagamenti) e BAD-05-04 (prelazioni) hanno
--   quindi bisogno delle scadenze gia' trasformate in numero di giorni.
--
-- COSA FA
--   1. Schema nuovo "flow", del team BAD, solo per le viste dei flussi
--      (non "analytics", che e' lo schema dei KPI del BID e di Power BI).
--   2. flow.v_payment_due    : un pagamento = una riga, con days_to_due
--      e is_paid.
--   3. flow.v_preemption_due : una prelazione = una riga, con
--      days_to_deadline e is_open.
--   4. SELECT al ruolo arcade_app (ne fa parte arcade_powerapp, l'utente
--      dei flussi, B-48). Nessun accesso per arcade_bi e arcade_portal.
--
-- "OGGI" = data italiana: (now() AT TIME ZONE 'Europe/Rome')::date.
--   Non dipende dal fuso del server (su Azure e' UTC): i giorni cambiano
--   a mezzanotte di Roma, come il fuso di core.edition.
--
-- SICUREZZA
--   Viste con security_invoker: chi le legge usa i SUOI permessi e le
--   policy RLS del core, non quelli del proprietario delle viste.
--
-- ATTENZIONE PER I FLUSSI
--   Le viste contengono anche i pagamenti 2024/2025 (16 non pagati, con
--   giorni molto negativi). Per i promemoria filtrare anche
--   edition_status eq 'SALES_OPEN' (oggi = 2026) e contract_status eq 'SIGNED'.
--
-- NON CAMBIA: nessuna tabella, colonna, vincolo o dato.
-- PREREQUISITI: V1-V4. SOLO CARATTERI ASCII.
--
-- PER TORNARE INDIETRO:
--   DROP SCHEMA flow CASCADE;
-- =====================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS flow;
REVOKE ALL ON SCHEMA flow FROM PUBLIC;
COMMENT ON SCHEMA flow IS
 'Team BAD: viste in sola lettura per i flussi Power Automate (date gia'' convertite in giorni).';

-- ---------------------------------------------------------------------
-- 1. Pagamenti (acconti, saldi, rimborsi)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW flow.v_payment_due
WITH (security_invoker = true) AS
SELECT
    p.payment_id,
    p.contract_id,
    c.contract_number,
    c.status                                         AS contract_status,
    e.year                                           AS edition_year,
    e.status                                         AS edition_status,
    x.exhibitor_id,
    x.exhibitor_code,
    x.legal_name,
    (SELECT string_agg(s.stand_code, ', ' ORDER BY s.stand_code)
       FROM core.contract_stand cs
       JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
       JOIN core.stand s          ON s.stand_id = se.stand_id
      WHERE cs.contract_id = p.contract_id
        AND cs.released_at IS NULL)                  AS stand_codes,
    p.kind,
    p.due_on,
    p.due_amount,
    p.paid_on,
    p.paid_amount,
    (p.due_on - (now() AT TIME ZONE 'Europe/Rome')::date)::integer AS days_to_due,
    (p.paid_on IS NOT NULL)                          AS is_paid
FROM core.payment   p
JOIN core.contract  c ON c.contract_id  = p.contract_id
JOIN core.edition   e ON e.edition_id   = c.edition_id
JOIN core.exhibitor x ON x.exhibitor_id = c.exhibitor_id;

COMMENT ON VIEW flow.v_payment_due IS
 'Promemoria pagamenti (BAD-05-03). days_to_due = due_on - oggi (Europe/Rome), negativo se scaduto. '
 'Per i promemoria: is_paid eq false, days_to_due le 7, edition_status eq ''SALES_OPEN'', contract_status eq ''SIGNED''.';

-- ---------------------------------------------------------------------
-- 2. Prelazioni
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW flow.v_preemption_due
WITH (security_invoker = true) AS
SELECT
    pr.preemption_id,
    pr.exhibitor_id,
    x.exhibitor_code,
    x.legal_name,
    pr.stand_id,
    s.stand_code,
    pr.source_contract_id,
    sc.contract_number                               AS source_contract_number,
    e.year                                           AS for_edition_year,
    e.status                                         AS for_edition_status,
    pr.deadline,
    (pr.deadline - (now() AT TIME ZONE 'Europe/Rome')::date)::integer AS days_to_deadline,
    pr.status,
    (pr.status = 'OPEN')                             AS is_open,
    pr.exercised_contract_id,
    ec.contract_number                               AS exercised_contract_number,
    pr.decided_at
FROM core.preemption pr
JOIN core.exhibitor x  ON x.exhibitor_id = pr.exhibitor_id
JOIN core.stand     s  ON s.stand_id     = pr.stand_id
JOIN core.contract  sc ON sc.contract_id = pr.source_contract_id
JOIN core.edition   e  ON e.edition_id   = pr.for_edition_id
LEFT JOIN core.contract ec ON ec.contract_id = pr.exercised_contract_id;

COMMENT ON VIEW flow.v_preemption_due IS
 'Promemoria prelazioni (BAD-05-04). days_to_deadline = deadline - oggi (Europe/Rome), negativo se scaduta. '
 'is_open = status OPEN (lo stato non passa a EXPIRED da solo). Per i promemoria: is_open eq true, days_to_deadline le 7.';

-- ---------------------------------------------------------------------
-- 3. Permessi
-- ---------------------------------------------------------------------
GRANT USAGE  ON SCHEMA flow TO arcade_app;
GRANT SELECT ON flow.v_payment_due, flow.v_preemption_due TO arcade_app;

COMMIT;

-- ---------------------------------------------------------------------
-- CONTROLLO (sola lettura, da lanciare dopo il COMMIT)
-- ---------------------------------------------------------------------
-- SHOW timezone;
-- SELECT count(*) AS righe, count(*) FILTER (WHERE NOT is_paid) AS non_pagati
--   FROM flow.v_payment_due;                        -- atteso su metiserver2: 396 e 16
-- SELECT count(*) FROM core.payment p
--   LEFT JOIN flow.v_payment_due v USING (payment_id)
--  WHERE v.payment_id IS NULL;                      -- atteso: 0
-- SELECT count(*) FROM flow.v_preemption_due;      -- oggi atteso: 0 (A-18)
-- SELECT has_table_privilege('arcade_powerapp', 'flow.v_payment_due', 'SELECT'),
--        has_table_privilege('arcade_powerbi',  'flow.v_payment_due', 'SELECT');  -- atteso: true, false

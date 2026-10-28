-- =====================================================================
-- ARCADE Milano - V1: schema condiviso (PostgreSQL 16)
-- Schemi:  core    = modello transazionale normalizzato (fonte di verita')
--          staging = copia grezza dei file del cliente (tutto text)
--          dq      = batch di import, regole, anomalie, riconciliazioni
-- Convenzioni: nomi in inglese snake_case, importi numeric(12,2),
--              istanti in timestamptz (UTC), date di calendario in date,
--              PK surrogate identity + business key con UNIQUE.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dq;

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- ricerca fuzzy ragioni sociali

-- ---------------------------------------------------------------------
-- 1. SORGENTI E BATCH DI IMPORTAZIONE (provenienza di ogni dato)
-- ---------------------------------------------------------------------
CREATE TABLE core.data_source (
    source_id        smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             text    NOT NULL UNIQUE,
    description      text    NOT NULL,
    kind             text    NOT NULL CHECK (kind IN
                       ('TICKETING','TURNSTILE','STAND_SCAN','STAND_LEAD',
                        'COMMERCIAL_XLSX','APP','MANUAL')),
    source_timezone  text    NOT NULL DEFAULT 'Europe/Rome',  -- IANA, fuso dei timestamp "naive"
    is_demo          boolean NOT NULL DEFAULT false           -- true = dati sintetici
);
COMMENT ON COLUMN core.data_source.source_timezone IS
 'Fuso con cui interpretare i timestamp privi di offset. 2024 = Europe/Rome, tornelli 2025 = UTC.';

CREATE TABLE dq.import_batch (
    batch_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_id        smallint NOT NULL REFERENCES core.data_source,
    file_name        text     NOT NULL,
    file_sha256      char(64) NOT NULL CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
    status           text     NOT NULL DEFAULT 'RUNNING'
                       CHECK (status IN ('RUNNING','COMPLETED','COMPLETED_WITH_ISSUES','FAILED','SUPERSEDED')),
    started_at       timestamptz NOT NULL DEFAULT now(),
    finished_at      timestamptz,
    rows_read        integer NOT NULL DEFAULT 0 CHECK (rows_read >= 0),
    rows_loaded      integer NOT NULL DEFAULT 0 CHECK (rows_loaded >= 0),
    rows_quarantined integer NOT NULL DEFAULT 0 CHECK (rows_quarantined >= 0),
    rows_rejected    integer NOT NULL DEFAULT 0 CHECK (rows_rejected >= 0),
    run_count        smallint NOT NULL DEFAULT 1,             -- n. di rilanci dello stesso file
    triggered_by     text,
    UNIQUE (source_id, file_sha256),                          -- stesso file = stesso batch (idempotenza)
    CHECK (finished_at IS NULL OR finished_at >= started_at)
);
COMMENT ON TABLE dq.import_batch IS
 'Un file importato = un batch. Il rilancio dello stesso file riusa il batch (run_count+1): nessun duplicato.';

-- ---------------------------------------------------------------------
-- 2. UTENTI, RUOLI, AUDIT
-- ---------------------------------------------------------------------
CREATE TABLE core.app_role (
    role_id     smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    description text NOT NULL
);

-- exhibitor_id e' valorizzato per gli utenti del portale espositori (isolamento dati).
-- FK aggiunta dopo la creazione di core.exhibitor.
CREATE TABLE core.app_user (
    user_id       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      text NOT NULL UNIQUE,
    display_name  text NOT NULL,
    exhibitor_id  integer,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.user_role (
    user_id integer  NOT NULL REFERENCES core.app_user ON DELETE CASCADE,
    role_id smallint NOT NULL REFERENCES core.app_role,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE core.audit_log (
    audit_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    user_id     integer REFERENCES core.app_user,
    action      text NOT NULL,
    entity      text NOT NULL,
    entity_id   text,
    detail      jsonb                       -- mai dati personali non necessari
);
CREATE INDEX ix_audit_log_entity ON core.audit_log (entity, entity_id);
CREATE INDEX ix_audit_log_time   ON core.audit_log USING brin (occurred_at);

-- ---------------------------------------------------------------------
-- 3. EDIZIONI, PADIGLIONI, STAND
-- ---------------------------------------------------------------------
CREATE TABLE core.edition (
    edition_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    year       smallint NOT NULL UNIQUE CHECK (year BETWEEN 2000 AND 2100),
    name       text     NOT NULL,
    status     text     NOT NULL DEFAULT 'PLANNED'
                 CHECK (status IN ('PLANNED','SALES_OPEN','RUNNING','CLOSED')),
    timezone   text     NOT NULL DEFAULT 'Europe/Rome',
    UNIQUE (edition_id, year)
);

-- Giorni di apertura: usati come FK per validare "Giorno valido" dei biglietti.
CREATE TABLE core.edition_day (
    edition_id  smallint NOT NULL REFERENCES core.edition,
    day_date    date     NOT NULL,
    day_number  smallint NOT NULL CHECK (day_number >= 1),
    opens_at    time     NOT NULL,
    closes_at   time     NOT NULL,
    PRIMARY KEY (edition_id, day_date),
    UNIQUE (edition_id, day_number),
    CHECK (closes_at > opens_at)
);

CREATE TABLE core.pavilion (
    pavilion_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text NOT NULL UNIQUE CHECK (code ~ '^P[0-9]+$'),
    name        text NOT NULL
);

-- Stand FISICO (identita' stabile tra le edizioni).
CREATE TABLE core.stand (
    stand_id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    stand_code       text    NOT NULL UNIQUE CHECK (stand_code ~ '^P[0-9]+-[A-Z][0-9]{2}$'),
    pavilion_id      smallint NOT NULL REFERENCES core.pavilion,
    sqm              numeric(7,2) NOT NULL CHECK (sqm > 0),
    position_type    text    NOT NULL CHECK (position_type IN ('LINEA','ANGOLO','PENISOLA','ISOLA')),
    first_edition_id smallint NOT NULL REFERENCES core.edition,   -- "attivo_dal"
    floor_x numeric(8,2), floor_y numeric(8,2),                   -- coordinate planimetria:
    floor_w numeric(8,2), floor_h numeric(8,2)                    -- NON fornite dal cliente
);
CREATE INDEX ix_stand_pavilion ON core.stand (pavilion_id);

-- OCCUPAZIONE di uno stand in una specifica edizione (non confonderla con lo stand).
CREATE TABLE core.stand_edition (
    stand_edition_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    stand_id         integer  NOT NULL REFERENCES core.stand,
    edition_id       smallint NOT NULL REFERENCES core.edition,
    commercial_status text    NOT NULL DEFAULT 'AVAILABLE'
                       CHECK (commercial_status IN ('AVAILABLE','RESERVED','SOLD','FREE','NOT_SELLABLE')),
    reserved_until   timestamptz,
    row_version      integer  NOT NULL DEFAULT 0,                 -- lock ottimistico (JPA @Version)
    UNIQUE (stand_id, edition_id),
    UNIQUE (stand_edition_id, edition_id),                        -- target di FK composite
    CHECK (reserved_until IS NULL OR commercial_status = 'RESERVED')
);
CREATE INDEX ix_stand_edition_edition_status ON core.stand_edition (edition_id, commercial_status);

-- ---------------------------------------------------------------------
-- 4. ESPOSITORI
-- ---------------------------------------------------------------------
CREATE TABLE core.exhibitor_category (
    category_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        text NOT NULL UNIQUE                              -- da "settore"
);

CREATE TABLE core.exhibitor (
    exhibitor_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exhibitor_code  text NOT NULL UNIQUE CHECK (exhibitor_code ~ '^ESP[0-9]{3,}$'),
    legal_name      text NOT NULL,
    legal_name_norm text NOT NULL,                                -- maiuscolo, senza punteggiatura/forma giuridica
    vat_number      text NOT NULL UNIQUE CHECK (vat_number ~ '^[0-9A-Z]{8,14}$'),
    category_id     smallint NOT NULL REFERENCES core.exhibitor_category,
    city            text,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_exhibitor_name_trgm ON core.exhibitor USING gin (legal_name_norm gin_trgm_ops);
COMMENT ON TABLE core.exhibitor IS
 'Identita'' dell''azienda. Nessuno stato "attivo/prospect" memorizzato: si deriva dai contratti.';

ALTER TABLE core.app_user
    ADD CONSTRAINT fk_app_user_exhibitor FOREIGN KEY (exhibitor_id) REFERENCES core.exhibitor;

-- Dati di contatto separati: minimizzazione e permessi dedicati.
CREATE TABLE core.exhibitor_contact (
    contact_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exhibitor_id integer NOT NULL REFERENCES core.exhibitor,
    full_name    text NOT NULL,
    email        text NOT NULL CHECK (email ~ '^[^@\s]+@[^@\s]+$'),
    is_primary   boolean NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX ux_exhibitor_one_primary_contact
    ON core.exhibitor_contact (exhibitor_id) WHERE is_primary;

-- Riconciliazione dei nomi (contratti 2024 senza id_espositore/P.IVA).
CREATE TABLE core.exhibitor_alias (
    alias_id     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exhibitor_id integer  NOT NULL REFERENCES core.exhibitor,
    alias_norm   text     NOT NULL UNIQUE,                        -- un alias punta a UN solo espositore
    source_id    smallint NOT NULL REFERENCES core.data_source,
    match_method text     NOT NULL CHECK (match_method IN ('EXACT','NORMALIZED','FUZZY_REVIEWED','MANUAL')),
    match_score  numeric(4,3) CHECK (match_score BETWEEN 0 AND 1),
    confirmed_by integer  REFERENCES core.app_user,
    confirmed_at timestamptz,
    CHECK (match_method NOT IN ('FUZZY_REVIEWED','MANUAL') OR confirmed_by IS NOT NULL)
);
CREATE INDEX ix_exhibitor_alias_exhibitor ON core.exhibitor_alias (exhibitor_id);

-- ---------------------------------------------------------------------
-- 5. LISTINO (uno per edizione)
-- ---------------------------------------------------------------------
CREATE TABLE core.price_list (
    price_list_id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    edition_id             smallint NOT NULL UNIQUE REFERENCES core.edition,
    origin                 text NOT NULL CHECK (origin IN ('CLIENT_LIST','RECONSTRUCTED_FROM_CONTRACTS')),
    status                 text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
    deposit_pct            numeric(5,4) CHECK (deposit_pct BETWEEN 0 AND 1),     -- COND-ACCONTO
    balance_days_before    smallint     CHECK (balance_days_before >= 0),        -- saldo N gg prima dell'apertura
    preemption_deadline    date,                                                 -- COND-PRELAZ
    notes                  text
);
COMMENT ON COLUMN core.price_list.origin IS
 'RECONSTRUCTED_FROM_CONTRACTS: il cliente ha fornito solo il listino 2026; 2024/2025 si ricostruiscono dalle righe contratto e vanno validati.';

CREATE TABLE core.price_item (
    price_item_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    price_list_id  integer NOT NULL REFERENCES core.price_list,
    code           text    NOT NULL,
    name           text    NOT NULL,
    item_type      text    NOT NULL CHECK (item_type IN ('SPACE','SURCHARGE','SPONSORSHIP','EXTRA')),
    unit           text    NOT NULL CHECK (unit IN ('SQM','PCT_OF_SPACE','PACKAGE','EACH')),
    unit_price     numeric(12,2) CHECK (unit_price >= 0),
    pct            numeric(5,4)  CHECK (pct BETWEEN 0 AND 1),
    pavilion_id    smallint REFERENCES core.pavilion,          -- solo SPACE
    position_type  text CHECK (position_type IN ('LINEA','ANGOLO','PENISOLA','ISOLA')),  -- solo SURCHARGE
    max_quantity   smallint CHECK (max_quantity > 0),          -- disponibilita' (sponsorizzazioni)
    notes          text,
    UNIQUE (price_list_id, code),
    CHECK ((unit = 'PCT_OF_SPACE' AND pct IS NOT NULL AND unit_price IS NULL)
        OR (unit <> 'PCT_OF_SPACE' AND unit_price IS NOT NULL AND pct IS NULL)),
    CHECK ((item_type = 'SPACE')     = (pavilion_id   IS NOT NULL)),
    CHECK ((item_type = 'SURCHARGE') = (position_type IS NOT NULL))
);
CREATE UNIQUE INDEX ux_price_item_space_per_pavilion
    ON core.price_item (price_list_id, pavilion_id) WHERE item_type = 'SPACE';
CREATE UNIQUE INDEX ux_price_item_surcharge_per_position
    ON core.price_item (price_list_id, position_type) WHERE item_type = 'SURCHARGE';

-- ---------------------------------------------------------------------
-- 6. PREVENTIVI E CONTRATTI
-- ---------------------------------------------------------------------
CREATE TABLE core.quote (
    quote_id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quote_number  text     NOT NULL UNIQUE,
    edition_id    smallint NOT NULL REFERENCES core.edition,
    exhibitor_id  integer  NOT NULL REFERENCES core.exhibitor,
    status        text     NOT NULL DEFAULT 'DRAFT'
                    CHECK (status IN ('DRAFT','SENT','CONFIRMED','REJECTED','EXPIRED','CONVERTED')),
    discount_pct  numeric(5,4) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 1),
    list_amount   numeric(12,2) NOT NULL DEFAULT 0 CHECK (list_amount >= 0),
    net_amount    numeric(12,2) NOT NULL DEFAULT 0 CHECK (net_amount >= 0),
    valid_until   date,
    created_by    integer  REFERENCES core.app_user,
    created_at    timestamptz NOT NULL DEFAULT now(),
    row_version   integer  NOT NULL DEFAULT 0,
    UNIQUE (quote_id, edition_id)
);
CREATE INDEX ix_quote_exhibitor ON core.quote (exhibitor_id, edition_id);

CREATE TABLE core.quote_line (
    quote_line_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quote_id         integer NOT NULL REFERENCES core.quote ON DELETE CASCADE,
    line_no          smallint NOT NULL CHECK (line_no >= 1),
    price_item_id    integer NOT NULL REFERENCES core.price_item,
    stand_edition_id integer REFERENCES core.stand_edition,
    description      text NOT NULL,
    quantity         numeric(12,2) NOT NULL CHECK (quantity > 0),
    unit_price       numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    amount           numeric(12,2) NOT NULL CHECK (amount >= 0),
    UNIQUE (quote_id, line_no),
    CHECK (abs(amount - round(quantity * unit_price, 2)) <= 0.01)
);

CREATE TABLE core.contract (
    contract_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_number text    NOT NULL UNIQUE,                       -- es. C2025-0089
    edition_id     smallint NOT NULL REFERENCES core.edition,
    exhibitor_id   integer  NOT NULL REFERENCES core.exhibitor,
    quote_id       integer  UNIQUE REFERENCES core.quote,          -- 1 preventivo -> max 1 contratto
    status         text     NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SIGNED','CANCELLED')),
    signed_on      date,
    list_amount    numeric(12,2) NOT NULL CHECK (list_amount >= 0),   -- imponibile_listino_eur
    discount_pct   numeric(5,4)  NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 1),
    net_amount     numeric(12,2) NOT NULL CHECK (net_amount >= 0),    -- imponibile_eur (netto sconto, IVA esclusa)
    is_renewal     boolean  NOT NULL DEFAULT false,                   -- "rinnovo" (semantica da confermare)
    source_id      smallint REFERENCES core.data_source,
    import_batch_id bigint  REFERENCES dq.import_batch,
    row_version    integer  NOT NULL DEFAULT 0,
    UNIQUE (contract_id, edition_id),                                 -- target di FK composite
    CHECK (status <> 'SIGNED' OR signed_on IS NOT NULL),
    CHECK (abs(net_amount - round(list_amount * (1 - discount_pct), 2)) <= 0.01)
);
-- Regola "1 contratto attivo per espositore/edizione": vera nei dati 2025 (110/110) ma NON
-- confermata dal cliente -> decisione D-07. Se confermata, attivare:
--   CREATE UNIQUE INDEX ux_contract_one_per_exhibitor ON core.contract (edition_id, exhibitor_id)
--     WHERE status <> 'CANCELLED';
CREATE INDEX ix_contract_exhibitor ON core.contract (exhibitor_id, edition_id);
CREATE INDEX ix_contract_edition_status ON core.contract (edition_id, status);

-- Legame contratto <-> stand occupato. L'indice parziale garantisce che uno stand
-- di un'edizione sia assegnato a UN solo contratto attivo (blocco doppia vendita).
CREATE TABLE core.contract_stand (
    contract_stand_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id       integer  NOT NULL,
    stand_edition_id  integer  NOT NULL,
    edition_id        smallint NOT NULL,
    assigned_at       timestamptz NOT NULL DEFAULT now(),
    released_at       timestamptz,
    release_reason    text,
    FOREIGN KEY (contract_id, edition_id)      REFERENCES core.contract (contract_id, edition_id),
    FOREIGN KEY (stand_edition_id, edition_id) REFERENCES core.stand_edition (stand_edition_id, edition_id),
    UNIQUE (contract_stand_id, contract_id),
    CHECK (released_at IS NULL OR released_at >= assigned_at)
);
CREATE UNIQUE INDEX ux_contract_stand_active
    ON core.contract_stand (stand_edition_id) WHERE released_at IS NULL;
CREATE INDEX ix_contract_stand_contract ON core.contract_stand (contract_id);

CREATE TABLE core.contract_line (
    contract_line_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id       integer  NOT NULL,
    line_no           smallint NOT NULL CHECK (line_no >= 1),
    line_type         text     NOT NULL CHECK (line_type IN ('SPACE','SURCHARGE','EXTRA','SPONSORSHIP')),
    price_item_id     integer  NOT NULL REFERENCES core.price_item,
    source_item_code  text,                                          -- codice_voce originale (SPAZIO, MAGG, EX-EL6...)
    description       text     NOT NULL,
    quantity          numeric(12,2) NOT NULL CHECK (quantity > 0),
    unit_price        numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    amount            numeric(12,2) NOT NULL CHECK (amount >= 0),
    contract_stand_id integer,
    FOREIGN KEY (contract_id) REFERENCES core.contract ON DELETE CASCADE,
    FOREIGN KEY (contract_stand_id, contract_id) REFERENCES core.contract_stand (contract_stand_id, contract_id),
    UNIQUE (contract_id, line_no),
    UNIQUE (contract_line_id, contract_id),
    CHECK (abs(amount - round(quantity * unit_price, 2)) <= 0.01),
    CHECK ((line_type IN ('SPACE','SURCHARGE')) = (contract_stand_id IS NOT NULL))
);
CREATE INDEX ix_contract_line_item ON core.contract_line (price_item_id);

CREATE TABLE core.sponsorship (
    sponsorship_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_line_id integer NOT NULL UNIQUE REFERENCES core.contract_line,
    status           text NOT NULL DEFAULT 'SOLD' CHECK (status IN ('SOLD','DELIVERED','CANCELLED')),
    notes            text
);
COMMENT ON TABLE core.sponsorship IS
 'Estende le righe contratto di tipo SPONSORSHIP (tracciamento esecuzione). Il valore economico resta in contract_line: nessun doppio conteggio.';

CREATE TABLE core.payment (
    payment_id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id     integer NOT NULL REFERENCES core.contract,
    kind            text    NOT NULL CHECK (kind IN ('DEPOSIT','BALANCE','REFUND')),
    due_on          date    NOT NULL,
    due_amount      numeric(12,2) NOT NULL CHECK (due_amount >= 0),
    due_amount_basis text   NOT NULL DEFAULT 'RULE_DERIVED'
                      CHECK (due_amount_basis IN ('RULE_DERIVED','CONTRACT_SCHEDULE')),
    paid_on         date,
    paid_amount     numeric(12,2) CHECK (paid_amount >= 0),
    paid_amount_is_assumed boolean NOT NULL DEFAULT false,
    CHECK ((paid_on IS NULL) = (paid_amount IS NULL))
);
COMMENT ON TABLE core.payment IS
 'Un acconto/saldo = una riga. Sono PAGAMENTI su un contratto, non ricavi aggiuntivi: mai sommare a net_amount.';
CREATE UNIQUE INDEX ux_payment_one_deposit_balance
    ON core.payment (contract_id, kind) WHERE kind IN ('DEPOSIT','BALANCE');
CREATE INDEX ix_payment_open_due ON core.payment (due_on) WHERE paid_on IS NULL;

CREATE TABLE core.preemption (
    preemption_id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exhibitor_id         integer  NOT NULL REFERENCES core.exhibitor,
    stand_id             integer  NOT NULL REFERENCES core.stand,
    source_contract_id   integer  NOT NULL REFERENCES core.contract,   -- il contratto che genera il diritto
    for_edition_id       smallint NOT NULL REFERENCES core.edition,
    deadline             date     NOT NULL,
    status               text     NOT NULL DEFAULT 'OPEN'
                           CHECK (status IN ('OPEN','EXERCISED','EXPIRED','WAIVED')),
    exercised_contract_id integer REFERENCES core.contract,
    decided_at           timestamptz,
    UNIQUE (source_contract_id, for_edition_id),
    CHECK ((status = 'EXERCISED') = (exercised_contract_id IS NOT NULL))
);
-- un solo diritto "vivo" per stand ed edizione
CREATE UNIQUE INDEX ux_preemption_live_per_stand
    ON core.preemption (stand_id, for_edition_id) WHERE status IN ('OPEN','EXERCISED');

-- ---------------------------------------------------------------------
-- 7. BIGLIETTERIA
-- ---------------------------------------------------------------------
CREATE TABLE core.sales_channel (
    channel_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code       text NOT NULL UNIQUE,
    name       text NOT NULL
);

CREATE TABLE core.ticket_type (
    ticket_type_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           text NOT NULL UNIQUE,
    name           text NOT NULL,
    is_free        boolean NOT NULL DEFAULT false,
    is_multi_day   boolean NOT NULL DEFAULT false,
    default_persons smallint NOT NULL DEFAULT 1 CHECK (default_persons >= 1)
);
CREATE TABLE core.ticket_type_alias (            -- nomi diversi 2024 vs 2025 -> tipo canonico
    alias_norm     text PRIMARY KEY,
    ticket_type_id smallint NOT NULL REFERENCES core.ticket_type
);

CREATE TABLE core.discount_code (
    discount_code_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             text NOT NULL UNIQUE,
    description      text,
    observed_pct     numeric(5,4) CHECK (observed_pct BETWEEN 0 AND 1)   -- ricavata dai prezzi, da confermare
);

CREATE TABLE core.age_band (
    age_band_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    kind        text NOT NULL CHECK (kind IN ('AGE','FAMILY')),
    min_age     smallint, max_age smallint,
    is_minor    boolean NOT NULL DEFAULT false,
    CHECK (max_age IS NULL OR min_age IS NULL OR max_age >= min_age)
);

CREATE TABLE core.province (
    province_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        char(2) NOT NULL UNIQUE,
    name        text NOT NULL
);
CREATE TABLE core.province_alias (
    alias_norm  text PRIMARY KEY,
    province_id smallint NOT NULL REFERENCES core.province
);

CREATE TABLE core.ticket_order (
    order_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_code   text     NOT NULL UNIQUE,
    edition_id   smallint NOT NULL REFERENCES core.edition,
    channel_id   smallint NOT NULL REFERENCES core.sales_channel,
    purchased_at timestamptz NOT NULL,
    source_id    smallint NOT NULL REFERENCES core.data_source,
    import_batch_id bigint REFERENCES dq.import_batch,
    UNIQUE (order_id, edition_id)
);

CREATE TABLE core.ticket (
    ticket_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_code      text     NOT NULL UNIQUE,                       -- chiave naturale (T24000001)
    order_id         bigint   NOT NULL,
    edition_id       smallint NOT NULL REFERENCES core.edition,
    ticket_type_id   smallint NOT NULL REFERENCES core.ticket_type,
    valid_day        date,                                           -- NULL = abbonamento multi-giorno
    price            numeric(8,2) NOT NULL CHECK (price >= 0),
    persons          smallint NOT NULL CHECK (persons >= 1),         -- 4 per Family: NON sono 4 biglietti
    age_band_id      smallint REFERENCES core.age_band,
    province_id      smallint REFERENCES core.province,
    discount_code_id smallint REFERENCES core.discount_code,
    source_id        smallint NOT NULL REFERENCES core.data_source,
    import_batch_id  bigint REFERENCES dq.import_batch,
    FOREIGN KEY (order_id, edition_id) REFERENCES core.ticket_order (order_id, edition_id),
    FOREIGN KEY (edition_id, valid_day) REFERENCES core.edition_day (edition_id, day_date)
);
CREATE INDEX ix_ticket_order   ON core.ticket (order_id);
CREATE INDEX ix_ticket_edition ON core.ticket (edition_id, ticket_type_id);

-- ---------------------------------------------------------------------
-- 8. VARCHI, LETTURE, DISPOSITIVI, VISITE AGLI STAND
-- ---------------------------------------------------------------------
CREATE TABLE core.gate (
    gate_id        smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gate_code      text NOT NULL UNIQUE,                             -- P1-NORD
    pavilion_id    smallint NOT NULL REFERENCES core.pavilion,
    name           text NOT NULL,
    direction_mode text NOT NULL DEFAULT 'UNKNOWN'
                     CHECK (direction_mode IN ('ENTRY_ONLY','BIDIRECTIONAL','UNKNOWN'))
);
CREATE TABLE core.gate_alias (
    alias_norm text PRIMARY KEY,
    gate_id    smallint NOT NULL REFERENCES core.gate
);

CREATE TABLE core.device (
    device_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_code text NOT NULL UNIQUE,
    kind        text NOT NULL CHECK (kind IN ('TURNSTILE','HAND_SCANNER','MOBILE_APP')),
    gate_id     smallint REFERENCES core.gate,
    notes       text
);

-- Lettura al varco. Si conserva anche quando il biglietto non e' risolto (ticket_id NULL)
-- o l'esito e' KO: niente scarti silenziosi, l'anomalia e' in dq.anomaly.
CREATE TABLE core.gate_reading (
    reading_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    edition_id      smallint NOT NULL REFERENCES core.edition,
    gate_id         smallint NOT NULL REFERENCES core.gate,
    ticket_code     text     NOT NULL,                               -- valore grezzo della sorgente
    ticket_id       bigint   REFERENCES core.ticket,                 -- risolto in ETL, NULL se orfano
    read_at         timestamptz NOT NULL,
    result          text     NOT NULL CHECK (result IN ('OK','KO')),
    direction       text     NOT NULL DEFAULT 'UNKNOWN' CHECK (direction IN ('IN','OUT','UNKNOWN')),
    source_id       smallint NOT NULL REFERENCES core.data_source,
    import_batch_id bigint   REFERENCES dq.import_batch,
    source_row_key  text     NOT NULL,                               -- chiave naturale di riga (idempotenza)
    UNIQUE (source_id, source_row_key)
);
CREATE INDEX ix_gate_reading_gate_time ON core.gate_reading (gate_id, read_at);
CREATE INDEX ix_gate_reading_ticket    ON core.gate_reading (ticket_id, read_at) WHERE ticket_id IS NOT NULL;
CREATE INDEX ix_gate_reading_code      ON core.gate_reading (ticket_code);
CREATE INDEX ix_gate_reading_time_brin ON core.gate_reading USING brin (read_at);

-- Visita puntuale (app di scansione, futura/live). visit_uuid generato dal client = idempotenza.
CREATE TABLE core.stand_visit (
    visit_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visit_uuid       uuid     NOT NULL UNIQUE,
    stand_edition_id integer  NOT NULL REFERENCES core.stand_edition,
    device_id        integer  REFERENCES core.device,
    visited_at       timestamptz NOT NULL,
    visitor_token    text,                                           -- pseudonimo, mai dati anagrafici
    source_id        smallint NOT NULL REFERENCES core.data_source,
    import_batch_id  bigint   REFERENCES dq.import_batch
);
CREATE INDEX ix_stand_visit_stand_time ON core.stand_visit (stand_edition_id, visited_at);

-- Visite aggregate per ora (unico dato disponibile per il 2025). NON si "inventano" eventi puntuali.
CREATE TABLE core.stand_visit_hourly (
    stand_edition_id integer  NOT NULL REFERENCES core.stand_edition,
    visit_date       date     NOT NULL,
    visit_hour       smallint NOT NULL CHECK (visit_hour BETWEEN 0 AND 23),
    scans            integer  NOT NULL CHECK (scans >= 0),
    source_id        smallint NOT NULL REFERENCES core.data_source,
    import_batch_id  bigint   REFERENCES dq.import_batch,
    PRIMARY KEY (stand_edition_id, visit_date, visit_hour)
);
COMMENT ON TABLE core.stand_visit_hourly IS
 'Granularita'': stand x giorno x ora. Una scansione = visita, NON contatto qualificato. Non sommare con stand_visit senza dedup per sorgente.';

-- Contatti raccolti dall'espositore. L'email in chiaro NON entra nel core: solo hash.
CREATE TABLE core.lead_interest (
    interest_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text NOT NULL UNIQUE
);
CREATE TABLE core.stand_lead (
    lead_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lead_code        text     NOT NULL UNIQUE,                      -- L2500001
    stand_edition_id integer  NOT NULL REFERENCES core.stand_edition,
    exhibitor_id     integer  NOT NULL REFERENCES core.exhibitor,
    captured_at      timestamptz NOT NULL,
    email_hash       bytea    NOT NULL CHECK (octet_length(email_hash) = 32),  -- sha256(salt||email)
    age_band_id      smallint REFERENCES core.age_band,
    province_id      smallint REFERENCES core.province,
    interest_id      smallint REFERENCES core.lead_interest,
    marketing_consent boolean NOT NULL,
    is_qualified     boolean  NOT NULL DEFAULT false,               -- criterio da definire con il cliente
    review_status    text     NOT NULL DEFAULT 'OK'
                       CHECK (review_status IN ('OK','PRIVACY_REVIEW')),
    source_id        smallint NOT NULL REFERENCES core.data_source,
    import_batch_id  bigint   REFERENCES dq.import_batch
);
CREATE INDEX ix_stand_lead_stand ON core.stand_lead (stand_edition_id);
CREATE INDEX ix_stand_lead_exhibitor ON core.stand_lead (exhibitor_id);
CREATE INDEX ix_stand_lead_email ON core.stand_lead (stand_edition_id, email_hash);

-- ---------------------------------------------------------------------
-- 9. QUALITA' DEI DATI
-- ---------------------------------------------------------------------
CREATE TABLE dq.rule (
    rule_code      text PRIMARY KEY,
    area           text NOT NULL,
    description    text NOT NULL,
    severity       text NOT NULL CHECK (severity IN ('INFO','WARNING','ERROR','CRITICAL')),
    default_action text NOT NULL CHECK (default_action IN
                     ('NONE','LOADED_FLAGGED','AUTO_CORRECTED','QUARANTINED','REJECTED'))
);

CREATE TABLE dq.anomaly (
    anomaly_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id          bigint   REFERENCES dq.import_batch,
    source_id         smallint NOT NULL REFERENCES core.data_source,
    rule_code         text     NOT NULL REFERENCES dq.rule,
    severity          text     NOT NULL CHECK (severity IN ('INFO','WARNING','ERROR','CRITICAL')),
    entity            text     NOT NULL,                             -- tabella/foglio interessato
    source_row_no     integer,
    record_ref        text,                                          -- chiave di business del record
    source_record     jsonb,                                         -- riga originale (mai email in chiaro)
    detail            text,
    action_applied    text     NOT NULL CHECK (action_applied IN
                        ('NONE','LOADED_FLAGGED','AUTO_CORRECTED','QUARANTINED','REJECTED')),
    resolution_status text     NOT NULL DEFAULT 'OPEN'
                        CHECK (resolution_status IN ('OPEN','ACKNOWLEDGED','RESOLVED','WONT_FIX')),
    detected_at       timestamptz NOT NULL DEFAULT now(),
    resolved_by       integer  REFERENCES core.app_user,
    resolved_at       timestamptz,
    resolution_note   text,
    CHECK (resolution_status IN ('OPEN','ACKNOWLEDGED') OR resolved_at IS NOT NULL)
);
-- Idempotenza: rilanciare lo stesso batch non duplica la stessa anomalia.
CREATE UNIQUE INDEX ux_anomaly_idempotent
    ON dq.anomaly (batch_id, rule_code, COALESCE(source_row_no, -1), COALESCE(record_ref, ''));
CREATE INDEX ix_anomaly_open ON dq.anomaly (severity, rule_code) WHERE resolution_status = 'OPEN';

CREATE TABLE dq.quarantine (
    quarantine_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id      bigint   NOT NULL REFERENCES dq.import_batch,
    source_id     smallint NOT NULL REFERENCES core.data_source,
    source_row_no integer  NOT NULL,
    raw_record    jsonb    NOT NULL,
    reason_rule   text     NOT NULL REFERENCES dq.rule,
    status        text     NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','RELEASED','DISCARDED')),
    decided_by    integer  REFERENCES core.app_user,
    decided_at    timestamptz,
    UNIQUE (batch_id, source_row_no, reason_rule)
);

CREATE TABLE dq.reconciliation_check (
    check_code  text PRIMARY KEY,
    description text NOT NULL,
    measure     text NOT NULL                                         -- KPI/misura confrontata
);
CREATE TABLE dq.reconciliation_result (
    result_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    check_code text NOT NULL REFERENCES dq.reconciliation_check,
    run_at     timestamptz NOT NULL DEFAULT now(),
    edition_id smallint REFERENCES core.edition,
    layer_a    text NOT NULL, value_a numeric(18,2),                  -- es. 'staging' / 'core'
    layer_b    text NOT NULL, value_b numeric(18,2),                  -- es. 'core' / 'analytics'
    status     text NOT NULL CHECK (status IN ('MATCH','MISMATCH','EXPECTED_DIFF'))
);

-- external_id_map: riconciliazione di identificativi esterni non nativi del core
CREATE TABLE core.external_id_map (
    source_id     smallint NOT NULL REFERENCES core.data_source,
    entity_type   text     NOT NULL,
    external_id   text     NOT NULL,
    internal_id   bigint   NOT NULL,
    PRIMARY KEY (source_id, entity_type, external_id)
);

-- ---------------------------------------------------------------------
-- 10. STAGING (copia grezza, tutto text; nessun vincolo di dominio)
-- ---------------------------------------------------------------------
CREATE TABLE staging.stg_exhibitor (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    id_espositore text, ragione_sociale text, partita_iva text, settore text,
    citta text, referente text, email_referente text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_stand (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    codice_stand text, padiglione text, nome_padiglione text, mq text, posizione text, attivo_dal text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_price_list_item (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    codice text, voce text, unita text, prezzo_unitario_eur text, disponibilita text, note text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_contract (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    id_contratto text, edizione text, id_espositore text, ragione_sociale text, partita_iva text,
    codice_stand text, data_firma text, imponibile_listino_eur text, sconto_pct text,
    imponibile_eur text, acconto_scadenza text, acconto_pagato_il text, saldo_scadenza text,
    saldo_pagato_il text, rinnovo text,                  -- date = seriali Excel (testo numerico)
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_contract_line (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    id_contratto text, riga text, codice_voce text, descrizione text,
    quantita text, prezzo_unitario_eur text, importo_eur text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_ticket (                   -- biglietteria 2024 e 2025 (stesso tracciato, sep ';')
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    id_ordine text, id_biglietto text, data_acquisto text, canale text, tipo_biglietto text,
    giorno_valido text, prezzo text, persone text, fascia_eta_titolare text, provincia text,
    codice_sconto text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_gate_reading_v1 (          -- tornelli 2024: data;ora;varco;codice;esito (ora locale)
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    data text, ora text, varco text, codice text, esito text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_gate_reading_v2 (          -- tornelli 2025: timestamp_utc,ticket_code,gate_id,result
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    timestamp_utc text, ticket_code text, gate_id text, result text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_stand_lead (               -- contiene EMAIL IN CHIARO: svuotare dopo il caricamento
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    id_contatto text, codice_stand text, id_espositore text, "timestamp" text, email text,
    fascia_eta text, provincia text, consenso_marketing text, interesse text,
    UNIQUE (batch_id, row_no)
);
CREATE TABLE staging.stg_stand_visit_hourly (
    stg_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES dq.import_batch, row_no integer NOT NULL,
    codice_stand text, data text, ora text, scansioni text,
    UNIQUE (batch_id, row_no)
);
COMMENT ON TABLE staging.stg_stand_lead IS
 'PII: l''email viene trasformata in hash nel core e la colonna email va azzerata a fine caricamento (retention staging da decidere con il referente privacy).';

-- ---------------------------------------------------------------------
-- 11. VISTE DI CONTROLLO (riconciliazione interna)
-- ---------------------------------------------------------------------
-- Stato commerciale incoerente con le assegnazioni attive.
CREATE VIEW dq.v_stand_status_mismatch AS
SELECT se.stand_edition_id, se.edition_id, se.commercial_status,
       (cs.stand_edition_id IS NOT NULL) AS has_active_contract
FROM core.stand_edition se
LEFT JOIN core.contract_stand cs
       ON cs.stand_edition_id = se.stand_edition_id AND cs.released_at IS NULL
WHERE (se.commercial_status = 'SOLD') <> (cs.stand_edition_id IS NOT NULL);

-- Somma righe <> imponibile di listino del contratto.
CREATE VIEW dq.v_contract_amount_mismatch AS
SELECT c.contract_id, c.contract_number, c.list_amount, s.lines_total
FROM core.contract c
JOIN (SELECT contract_id, sum(amount) AS lines_total
        FROM core.contract_line GROUP BY contract_id) s USING (contract_id)
WHERE abs(c.list_amount - s.lines_total) > 0.01;

-- Pagamenti oltre scadenza o pagati in ritardo (informativo, non e' un errore dati).
CREATE VIEW dq.v_payment_status AS
SELECT p.payment_id, p.contract_id, p.kind, p.due_on, p.paid_on,
       CASE WHEN p.paid_on IS NULL AND p.due_on <  current_date THEN 'OVERDUE'
            WHEN p.paid_on IS NULL                              THEN 'DUE'
            WHEN p.paid_on >  p.due_on                          THEN 'PAID_LATE'
            ELSE 'PAID' END AS payment_state
FROM core.payment p;

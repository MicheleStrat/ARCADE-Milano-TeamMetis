-- =====================================================================
-- ARCADE Milano - V6: riserva degli stand legata al preventivo e chiavi di idempotenza (B3a)
-- RIPETIBILE: Docker la esegue all'avvio di un volume nuovo e Flyway, che parte dal riferimento
-- alla versione 5, puo' rieseguirla. Ogni istruzione deve restare innocua alla seconda volta.
-- =====================================================================

-- Quale preventivo ha riservato lo stand (serve in conversione per riconoscere la propria riserva).
ALTER TABLE core.stand_edition
    ADD COLUMN IF NOT EXISTS reserved_by_quote_id integer REFERENCES core.quote (quote_id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stand_edition_reserved_by') THEN
    ALTER TABLE core.stand_edition ADD CONSTRAINT ck_stand_edition_reserved_by
      CHECK (reserved_by_quote_id IS NULL OR commercial_status = 'RESERVED');
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_stand_edition_reserved_by
    ON core.stand_edition (reserved_by_quote_id) WHERE reserved_by_quote_id IS NOT NULL;

-- Chiavi di idempotenza: stessa chiave = stessa risposta per 24 ore. Si salvano solo i successi.
CREATE TABLE IF NOT EXISTS core.idempotency_key (
    idempotency_key_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    principal       text NOT NULL,                 -- utente del token (sub)
    operation       text NOT NULL,                 -- createQuote | convertQuoteToContract
    idem_key        text NOT NULL,
    request_hash    text NOT NULL,                 -- SHA-256 del contenuto canonico della richiesta
    response_status smallint,
    response_body   text,                          -- risposta identica byte per byte
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (principal, operation, idem_key)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON core.idempotency_key TO arcade_app;

# B3a — Percorso "contratto venduto": piano di implementazione

> **Per chi esegue (agenti):** SOTTO-SKILL OBBLIGATORIA: usa `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans` per eseguire il piano task per task. I passaggi usano la sintassi con caselle (`- [ ]`) per tenere traccia dell'avanzamento.

**Obiettivo:** dal backend si crea un preventivo con prezzi calcolati dal server e stand riservati, lo si invia e conferma, e lo si converte in contratto con acconto e saldo; con idempotenza e senza doppia vendita.

**Architettura:** pacchetto `commercial/` nel backend di B2. I controller sono sottili; `QuoteService` e `ContractService` eseguono tutto in una transazione in scrittura (`ScopedDb.write`, ruolo `arcade_app`); `PricingCalculator` è una funzione pura; `StandReservation` blocca gli stand in ordine fisso; `IdempotencyService` salva la risposta di successo nella stessa transazione. Una migrazione V6 aggiunge `reserved_by_quote_id` e la tabella delle chiavi.

**Tecnologie:** Java 25, Spring Boot 3.5.7, Spring JDBC (`JdbcClient`), Flyway, PostgreSQL 16, JUnit 5, MockMvc, Testcontainers 2.0.5.

**Specifica:** [docs/superpowers/specs/2026-11-16-b3a-contratto-venduto-design.md](../specs/2026-11-16-b3a-contratto-venduto-design.md)

## Vincoli globali

- Contratto API: `docs/api/openapi.yaml` (nomi dei campi, ruoli, intestazioni `Idempotency-Key` e `If-Match`). Base `/api/v1`.
- Ruoli: `ADMIN` e `COMMERCIAL` su preventivi e conversione; `ADMIN`, `COMMERCIAL`, `OPS` su `GET /contracts/{id}`.
- Nessun JPA: solo `JdbcClient` con SQL scritto a mano e parametri bind. Nessun testo preso dal client dentro l'SQL.
- Gli stand si bloccano con `SELECT … FOR UPDATE` **in ordine di `stand_edition_id`**.
- Importi `BigDecimal` con due decimali, arrotondamento `HALF_UP`, IVA esclusa.
- Errori: `application/problem+json` con `code` stabile e `traceId`. Codici nuovi ammessi solo come modifica compatibile: `EDITION_DATES_MISSING` (422), `PRICE_LIST_CONDITIONS_MISSING` (422), `INVALID_STATE_TRANSITION` (409), `STAND_NOT_SELLABLE` (422).
- Chiave idempotente con contenuto diverso: `409 DUPLICATE_REQUEST` (codice già nel contratto).
- **Le migrazioni dopo V5 devono essere ripetibili** (`IF NOT EXISTS`, vincoli protetti da `DO`): Docker le esegue all'avvio di un volume nuovo e Flyway, che parte dal riferimento alla versione 5, le riesegue.
- Nessun segreto o dato personale nel repository né nei log.
- Messaggi di commit in italiano, senza `Co-Authored-By` e senza riferimenti a Claude.

## Verifiche richieste dalla revisione (Review Focus)

| # | Caso | Test (task) |
|---|---|---|
| 1 | Due preventivi con gli stessi due stand in ordine opposto non vanno in stallo (un solo 201, nessun 500) | `ConcurrencyApiTest` (Task 8) |
| 2 | Molte richieste con la stessa chiave in parallelo producono un solo preventivo e la stessa risposta | `ConcurrencyApiTest` (Task 8) |
| 3 | Numeri di preventivo distinti quando si creano preventivi in parallelo | `ConcurrencyApiTest` (Task 8) |
| 4 | Una riserva scaduta ripresa da un altro preventivo fa fallire la conversione del primo (409), senza lasciare nulla | `ConvertApiTest` (Task 7) |
| 5 | Se la conversione fallisce (date mancanti) non resta nulla: preventivo ancora `CONFIRMED`, stand ancora `RESERVED`, nessun contratto | `ConvertApiTest` (Task 7) |
| 6 | Una chiave di più di 24 ore con contenuto diverso riparte; una richiesta fallita non consuma la chiave | `CreateQuoteApiTest` (Task 5) |

## Struttura dei file

```
database/migrations/V6__commercial_idempotency_and_reservation.sql
backend/src/main/java/it/arcade/backend/
  error/FieldError.java  ValidationErrors.java            (nuovi)
  error/ApiException.java  Problem.java  ProblemWriter.java  RestExceptionHandler.java   (modificati)
  db/ScopedDb.java                                         (nuovo metodo write)
  config/SecurityConfig.java                               (nuove regole)
  commercial/
    QuoteProperties.java  ContractProperties.java
    dto/  QuoteLineInput  QuoteCreate  DocumentLine  Quote  ContractFromQuote  ContractStandRef  Payment  Contract
    PricingCalculator.java  (con PriceItem, StandInfo, PricedLine, PricedQuote)
    IdempotencyService.java
    NumberGenerator.java
    StandReservation.java
    PriceListRepository.java  QuoteRepository.java  ContractRepository.java
    QuoteService.java  ContractService.java
    QuoteController.java  ContractController.java
backend/src/test/resources/db/testdata/V901__test_commercial_data.sql
backend/src/test/java/it/arcade/backend/
  support/Fixtures.java  CommercialApiTest.java  PostgresSupport.java (modificato)
  db/SchemaV6Test.java
  commercial/PricingCalculatorTest  CreateQuoteApiTest  QuoteTransitionsApiTest  ConvertApiTest  ConcurrencyApiTest
```

---

## Task 1: Migrazione V6, dati di prova e aggiornamento dei test esistenti

**Deliverable:** V6 si applica da zero e sopra V5, è ripetibile; il database di prova ha listino, edizioni di prova e un aiuto per creare stand. La suite di B2 resta verde.

**Files:**
- Create: `database/migrations/V6__commercial_idempotency_and_reservation.sql`
- Create: `backend/src/test/resources/db/testdata/V901__test_commercial_data.sql`
- Create: `backend/src/test/java/it/arcade/backend/support/Fixtures.java`
- Create: `backend/src/test/java/it/arcade/backend/db/SchemaV6Test.java`
- Modify: `backend/src/test/java/it/arcade/backend/support/PostgresSupport.java`, `db/ScopedDbTest.java`, `api/EditionsApiTest.java`, `config/BaselineExistingSchemaStrategyTest.java`

**Interfaces:**
- Produces: `Fixtures.edition(int year)` → `int` editionId; `Fixtures.priceItem(int year, String code)` → `int`; `Fixtures.newStand(int year, String pavilionCode, String sqm, String position)` → `int` standEditionId (stand nuovo, `AVAILABLE`); `Fixtures.owner()` → `JdbcTemplate` superutente.
- Dati di prova: edizione **2098** (`SALES_OPEN`, giorni 18–20/12/2098, listino `PUBLISHED`, acconto 30 %, saldo 30 giorni prima) ed edizione **2099** (`SALES_OPEN`, **senza giorni**, listino `PUBLISHED`). Voci: `SP-P1` (100,00/mq, padiglione P1), `SP-P2` (80,00/mq, P2), `MAG-ANGOLO` 10 %, `MAG-PENISOLA` 15 %, `MAG-ISOLA` 20 %, `EX-EL6` (EXTRA, 50,00 cad.), `SPN-GOLD` (SPONSORSHIP, 5000,00, massimo 1). La 2099 ha solo `SP-P1` e `MAG-ANGOLO`.

- [ ] **Step 1: Crea il ramo**

```bash
git switch -c b3a-contratto-venduto BID
git add docs/superpowers/specs/2026-11-16-b3a-contratto-venduto-design.md docs/superpowers/plans/2026-11-16-b3a-contratto-venduto.md
git commit -m "Specifica e piano di B3a (percorso contratto venduto)"
```

- [ ] **Step 2: Scrivi i test che falliscono**

`backend/src/test/java/it/arcade/backend/support/Fixtures.java`:

```java
package it.arcade.backend.support;

import java.math.BigDecimal;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.jdbc.core.JdbcTemplate;

/** Aiuti per i test: lavorano come superutente sul database di prova. */
public final class Fixtures {

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Fixtures() {}

    public static JdbcTemplate owner() {
        return PostgresSupport.owner();
    }

    public static int edition(int year) {
        return owner().queryForObject("SELECT edition_id FROM core.edition WHERE year = ?", Integer.class, year);
    }

    public static int priceItem(int year, String code) {
        return owner().queryForObject("""
                SELECT pi.price_item_id FROM core.price_item pi
                  JOIN core.price_list pl ON pl.price_list_id = pi.price_list_id
                  JOIN core.edition e ON e.edition_id = pl.edition_id
                 WHERE e.year = ? AND pi.code = ?""", Integer.class, year, code);
    }

    /** Crea uno stand nuovo e la sua occupazione nell'edizione (AVAILABLE). Restituisce stand_edition_id. */
    public static int newStand(int year, String pavilionCode, String sqm, String position) {
        int n = SEQ.getAndIncrement();
        String code = String.format("%s-%c%02d", pavilionCode, (char) ('A' + (n / 100) % 26), n % 100);
        owner().update("""
                INSERT INTO core.stand (stand_code, pavilion_id, sqm, position_type, first_edition_id)
                VALUES (?, (SELECT pavilion_id FROM core.pavilion WHERE code = ?), ?, ?,
                        (SELECT min(edition_id) FROM core.edition))""",
                code, pavilionCode, new BigDecimal(sqm), position);
        return owner().queryForObject("""
                INSERT INTO core.stand_edition (stand_id, edition_id)
                SELECT s.stand_id, ? FROM core.stand s WHERE s.stand_code = ?
                RETURNING stand_edition_id""", Integer.class, edition(year), code);
    }
}
```

`backend/src/test/java/it/arcade/backend/db/SchemaV6Test.java`:

```java
package it.arcade.backend.db;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.support.Fixtures;
import it.arcade.backend.support.PostgresSupport;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

class SchemaV6Test {

    private final JdbcTemplate owner = Fixtures.owner();

    @Test
    void la_colonna_della_riserva_esiste() {
        Integer n = owner.queryForObject("""
                SELECT count(*) FROM information_schema.columns
                 WHERE table_schema = 'core' AND table_name = 'stand_edition'
                   AND column_name = 'reserved_by_quote_id'""", Integer.class);
        assertThat(n).isEqualTo(1);
    }

    @Test
    void reserved_by_quote_id_richiede_lo_stato_reserved() {
        int standEdition = Fixtures.newStand(2098, "P1", "10.00", "LINEA");
        // lo stand e' AVAILABLE: indicare un preventivo che lo riserva viola il vincolo
        assertThatThrownBy(() -> owner.update(
                "UPDATE core.stand_edition SET reserved_by_quote_id = 1 WHERE stand_edition_id = ?", standEdition))
                .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
    }

    @Test
    void la_chiave_idempotente_e_unica_per_utente_operazione_e_chiave() {
        owner.update("INSERT INTO core.idempotency_key (principal, operation, idem_key, request_hash) "
                + "VALUES ('u', 'op', 'chiave-unica-1', 'h')");
        assertThatThrownBy(() -> owner.update("INSERT INTO core.idempotency_key "
                + "(principal, operation, idem_key, request_hash) VALUES ('u', 'op', 'chiave-unica-1', 'h2')"))
                .hasMessageContaining("duplicate key");
    }

    @Test
    void la_migrazione_si_puo_rieseguire_senza_errori() throws Exception {
        String sql = java.nio.file.Files.readString(java.nio.file.Path.of(
                "../database/migrations/V6__commercial_idempotency_and_reservation.sql"));
        owner.execute(sql);
        owner.execute(sql);
        assertThat(PostgresSupport.DB.isRunning()).isTrue();
    }
}
```

- [ ] **Step 3: Esegui e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest=SchemaV6Test test
```

Atteso: i test falliscono (la colonna e la tabella non esistono, e il file V6 manca).

- [ ] **Step 4: Scrivi la migrazione ripetibile**

`database/migrations/V6__commercial_idempotency_and_reservation.sql`:

```sql
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
```

- [ ] **Step 5: Aggiorna i dati di prova e i test esistenti**

`backend/src/test/resources/db/testdata/V901__test_commercial_data.sql`:

```sql
-- SOLO PER I TEST (B3a). Edizioni di prova con anni lontani, per non toccare le edizioni vere.
-- 2098: con giorni di apertura PROVVISORI DI PROVA. 2099: senza giorni (serve a provare EDITION_DATES_MISSING).
INSERT INTO core.edition (year, name, status) VALUES
 (2098, 'Edizione di prova con date', 'SALES_OPEN'),
 (2099, 'Edizione di prova senza date', 'SALES_OPEN');

INSERT INTO core.edition_day (edition_id, day_date, day_number, opens_at, closes_at)
SELECT e.edition_id, d.day_date, d.n, '09:00', '17:30'
FROM core.edition e
JOIN (VALUES (DATE '2098-12-18', 1), (DATE '2098-12-19', 2), (DATE '2098-12-20', 3)) AS d(day_date, n) ON true
WHERE e.year = 2098;

INSERT INTO core.price_list (edition_id, origin, status, deposit_pct, balance_days_before)
SELECT edition_id, 'CLIENT_LIST', 'PUBLISHED', 0.3000, 30 FROM core.edition WHERE year IN (2098, 2099);

INSERT INTO core.price_item (price_list_id, code, name, item_type, unit, unit_price, pct, pavilion_id, position_type, max_quantity)
SELECT pl.price_list_id, v.code, v.name, v.item_type, v.unit, v.unit_price, v.pct,
       (SELECT pavilion_id FROM core.pavilion WHERE code = v.pav), v.pos, v.maxq
FROM core.price_list pl
JOIN core.edition e ON e.edition_id = pl.edition_id
JOIN (VALUES
  ('SP-P1',        'Spazio padiglione 1',   'SPACE',       'SQM',          100.00, NULL::numeric, 'P1',          NULL,        NULL::int),
  ('SP-P2',        'Spazio padiglione 2',   'SPACE',       'SQM',           80.00, NULL,          'P2',          NULL,        NULL),
  ('MAG-ANGOLO',   'Maggiorazione angolo',  'SURCHARGE',   'PCT_OF_SPACE',  NULL,  0.1000,        NULL::text,    'ANGOLO',    NULL),
  ('MAG-PENISOLA', 'Maggiorazione penisola','SURCHARGE',   'PCT_OF_SPACE',  NULL,  0.1500,        NULL,          'PENISOLA',  NULL),
  ('MAG-ISOLA',    'Maggiorazione isola',   'SURCHARGE',   'PCT_OF_SPACE',  NULL,  0.2000,        NULL,          'ISOLA',     NULL),
  ('EX-EL6',       'Allaccio elettrico',    'EXTRA',       'EACH',          50.00, NULL,          NULL,          NULL,        NULL),
  ('SPN-GOLD',     'Sponsor gold',          'SPONSORSHIP', 'PACKAGE',     5000.00, NULL,          NULL,          NULL,        1)
) AS v(code, name, item_type, unit, unit_price, pct, pav, pos, maxq)
  ON (e.year = 2098 OR v.code IN ('SP-P1', 'MAG-ANGOLO'))
WHERE e.year IN (2098, 2099);
```

In `PostgresSupport.java` **rimuovi** la riga `r.add("spring.datasource.hikari.maximum-pool-size", () -> "1"); ...`. In `ScopedDbTest.java` sostituisci il metodo `database` con:

```java
    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
        registry.add("spring.datasource.hikari.maximum-pool-size", () -> "1"); // forza il riuso della connessione
    }
```

In `EditionsApiTest.java` le edizioni ora sono 5 (le tre vere più 2098 e 2099): cambia `jsonPath("$.length()").value(3)` in `value(5)` (due occorrenze). In `BaselineExistingSchemaStrategyTest.java` la versione corrente ora è la 6:

- primo test: `isEqualTo("6")` e `hasSize(6)`;
- secondo test: crea il database fino alla V5 con `Flyway.configure()...target("5").load().migrate()` (simula il volume creato quando V6 non c'era), dopo la baseline si aspetta versione `"6"` e `applied()` di dimensione 2 (riferimento + V6);
- **nuovo terzo test** `suVolumeCreatoConTutteLeMigrazioniLaV6RipetibileNonDaErrori`: `flyway(pg).migrate()` completo, `DROP TABLE flyway_schema_history`, strategia, versione `"6"`, `applied()` di dimensione 2.

- [ ] **Step 6: Esegui tutta la suite**

```bash
./mvnw -q test
```

Atteso: tutti i test passano (i 31 di B2, con gli aggiornamenti sopra, più 4 di `SchemaV6Test`).

- [ ] **Step 7: Commit**

```bash
cd ..
git add database backend
git commit -m "B3a: migrazione V6 ripetibile, dati di prova commerciali e aggiornamento dei test"
```

---

## Task 2: Errori con `errors[]`, codici del contratto e `ScopedDb.write`

**Deliverable:** gli errori di validazione escono con `errors[]`; i codici di formato sono quelli del contratto (`VALIDATION_ERROR`); `ScopedDb.write` esegue in lettura e scrittura con il ruolo staff e annulla tutto in caso di eccezione.

**Files:**
- Create: `backend/src/main/java/it/arcade/backend/error/FieldError.java`, `ValidationErrors.java`
- Modify: `error/ApiException.java`, `error/Problem.java`, `error/ProblemWriter.java`, `error/RestExceptionHandler.java`, `db/ScopedDb.java`, `security/DevTokenController.java`
- Test: `db/ScopedDbTest.java`, `security/DevTokenApiTest.java`

**Interfaces:**
- Produces: `FieldError(String field, String message)`; `ValidationErrors.add(field, message)` / `throwIfAny()` (lancia `422 VALIDATION_ERROR` con `errors[]`); `ApiException.conflict(code, title)`, `.unprocessable(code, title)`, `.badRequest(code, title)`, `.validation(List<FieldError>)`, accessor `errors()`; `ScopedDb.write(Function<JdbcClient,T>)` → `T`.

- [ ] **Step 1: Scrivi i test che falliscono**

In `ScopedDbTest.java` aggiungi (e gli import `static org.assertj.core.api.Assertions.assertThat` esistono già):

```java
    @Test
    void write_usa_il_ruolo_staff_e_annulla_tutto_se_c_e_un_errore() {
        String ruolo = db.write(j -> j.sql("SELECT current_user").query(String.class).single());
        assertThat(ruolo).isEqualTo("arcade_app");

        assertThatThrownBy(() -> db.write(j -> {
            j.sql("INSERT INTO core.idempotency_key (principal, operation, idem_key, request_hash) "
                    + "VALUES ('t','t','chiave-rollback-1','h')").update();
            throw new IllegalStateException("errore voluto");
        })).isInstanceOf(IllegalStateException.class);

        Integer righe = PostgresSupport.owner().queryForObject(
                "SELECT count(*) FROM core.idempotency_key WHERE idem_key = 'chiave-rollback-1'", Integer.class);
        assertThat(righe).isZero();
    }
```

Il gestore dei parametri non convertibili (`/quotes/abc` → 400) si prova nel Task 5, quando esiste `/quotes/{quoteId}`.

In `DevTokenApiTest.java` sostituisci le tre occorrenze di `"INVALID_REQUEST"` con `"VALIDATION_ERROR"`.

- [ ] **Step 2: Esegui e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest='ScopedDbTest,DevTokenApiTest' test
```

Atteso: `ScopedDbTest` non compila (`write` non esiste); dopo aver aggiunto solo la firma vuota, `DevTokenApiTest` fallisce perché il codice è `INVALID_REQUEST`.

- [ ] **Step 3: Scrivi il codice**

`backend/src/main/java/it/arcade/backend/error/FieldError.java`:

```java
package it.arcade.backend.error;

/** Errore su un campo (schema `FieldError` di docs/api/openapi.yaml). */
public record FieldError(String field, String message) {}
```

`backend/src/main/java/it/arcade/backend/error/ValidationErrors.java`:

```java
package it.arcade.backend.error;

import java.util.ArrayList;
import java.util.List;

/** Raccoglie gli errori sui campi e li lancia insieme come 422 VALIDATION_ERROR. */
public final class ValidationErrors {

    private final List<FieldError> errors = new ArrayList<>();

    public void add(String field, String message) {
        errors.add(new FieldError(field, message));
    }

    public boolean isEmpty() {
        return errors.isEmpty();
    }

    public void throwIfAny() {
        if (!errors.isEmpty()) {
            throw ApiException.validation(errors);
        }
    }
}
```

`error/ApiException.java` (sostituisci l'intero file):

```java
package it.arcade.backend.error;

import java.util.List;
import org.springframework.http.HttpStatus;

/** Errore previsto dell'API: diventa una risposta problem+json con questo codice stabile. */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final List<FieldError> errors;

    public ApiException(HttpStatus status, String code, String title, String detail) {
        this(status, code, title, detail, null);
    }

    public ApiException(HttpStatus status, String code, String title, String detail, List<FieldError> errors) {
        super(detail != null ? detail : title);
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.errors = errors;
    }

    public static ApiException notFound(String code, String title) {
        return new ApiException(HttpStatus.NOT_FOUND, code, title, null);
    }

    public static ApiException forbidden() {
        return new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Ruolo non autorizzato", null);
    }

    public static ApiException conflict(String code, String title) {
        return new ApiException(HttpStatus.CONFLICT, code, title, null);
    }

    public static ApiException unprocessable(String code, String title) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, code, title, null);
    }

    public static ApiException badRequest(String code, String title) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, title, null);
    }

    public static ApiException validation(List<FieldError> errors) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_ERROR", "Dati non validi", null, errors);
    }

    public HttpStatus status() { return status; }
    public String code() { return code; }
    public String title() { return title; }
    public String detail() { return detail; }
    public List<FieldError> errors() { return errors; }
}
```

`error/Problem.java` (sostituisci):

```java
package it.arcade.backend.error;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.List;

/** Corpo degli errori (schema `Problem` di docs/api/openapi.yaml). */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record Problem(String type, String title, int status, String code, String detail, String traceId,
                      List<FieldError> errors) {}
```

In `error/ProblemWriter.java` sostituisci il metodo `problem` con due versioni:

```java
    public Problem problem(HttpStatus status, String code, String title, String detail) {
        return problem(status, code, title, detail, null);
    }

    public Problem problem(HttpStatus status, String code, String title, String detail, List<FieldError> errors) {
        return new Problem("about:blank", title, status.value(), code, detail,
                MDC.get(RequestIdFilter.MDC_KEY), errors);
    }
```

e aggiungi `import java.util.List;`. In `error/RestExceptionHandler.java`:

- il metodo `api` diventa:

```java
    @ExceptionHandler(ApiException.class)
    ResponseEntity<Problem> api(ApiException e) {
        return ResponseEntity.status(e.status()).contentType(PROBLEM)
                .body(problems.problem(e.status(), e.code(), e.title(), e.detail(), e.errors()));
    }
```

- in `unreadable` cambia il codice `"INVALID_REQUEST"` in `"VALIDATION_ERROR"`; in `codeFor` cambia `case BAD_REQUEST -> "INVALID_REQUEST";` in `case BAD_REQUEST -> "VALIDATION_ERROR";`;
- aggiungi il gestore dei parametri non convertibili (`/quotes/abc`):

```java
    @ExceptionHandler(org.springframework.beans.TypeMismatchException.class)
    ResponseEntity<Problem> typeMismatch(org.springframework.beans.TypeMismatchException e) {
        return reply(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Parametro non valido", null);
    }
```

In `security/DevTokenController.java` cambia in `invalid(...)`: `"INVALID_REQUEST"` → `"VALIDATION_ERROR"`.

In `db/ScopedDb.java` aggiungi (accanto a `read`):

```java
    private final TransactionTemplate writeTx;
```

assegnalo nel costruttore con `this.writeTx = new TransactionTemplate(transactionManager);` e aggiungi il metodo:

```java
    /** Transazione in lettura e scrittura con il ruolo staff. Qualsiasi eccezione annulla tutto. */
    public <T> T write(Function<JdbcClient, T> work) {
        return writeTx.execute(status -> {
            jdbc.sql("SET LOCAL ROLE " + DbRole.STAFF.sqlName()).update();
            return work.apply(jdbc);
        });
    }
```

- [ ] **Step 2: Esegui la suite**

```bash
./mvnw -q test
```

Atteso: tutti i test passano.

- [ ] **Step 3: Commit**

```bash
cd ..
git add backend
git commit -m "B3a: errori con errors[], codici del contratto e ScopedDb.write"
```

---

## Task 3: DTO e calcolo dei prezzi

**Deliverable:** `PricingCalculator` calcola righe, maggiorazioni, totale e netto con numeri esatti, senza database.

**Files:**
- Create: `backend/src/main/java/it/arcade/backend/commercial/dto/*.java` (8 record)
- Create: `backend/src/main/java/it/arcade/backend/commercial/PricingCalculator.java`
- Test: `backend/src/test/java/it/arcade/backend/commercial/PricingCalculatorTest.java`

**Interfaces:**
- Produces:
  - `PricingCalculator.PriceItem(int priceItemId, String code, String name, String itemType, String unit, BigDecimal unitPrice, BigDecimal pct, Integer pavilionId, String positionType, Integer maxQuantity)`
  - `PricingCalculator.StandInfo(int standEditionId, String standCode, int pavilionId, BigDecimal sqm, String positionType)`
  - `PricingCalculator.PricedLine(String lineType, int priceItemId, Integer standEditionId, String description, BigDecimal quantity, BigDecimal unitPrice, BigDecimal amount)`
  - `PricingCalculator.PricedQuote(List<PricedLine> lines, BigDecimal listAmount, BigDecimal netAmount)`
  - `PricingCalculator.calculate(List<QuoteLineInput> inputs, Map<Integer,PriceItem> items, Map<Integer,StandInfo> stands, BigDecimal discountPct)` → `PricedQuote`; lancia `422 VALIDATION_ERROR` con `errors[]`.

- [ ] **Step 1: Scrivi i record DTO**

Tutti in `package it.arcade.backend.commercial.dto;`. Nomi dei campi come in `docs/api/openapi.yaml`.

```java
// QuoteLineInput.java
public record QuoteLineInput(Integer priceItemId, Integer standEditionId, BigDecimal quantity, String description) {}

// QuoteCreate.java
public record QuoteCreate(Integer editionId, Integer exhibitorId, BigDecimal discountPct, LocalDate validUntil,
                          List<QuoteLineInput> lines) {}

// DocumentLine.java
public record DocumentLine(int lineNo, String lineType, int priceItemId, Integer standEditionId, String standCode,
                           String description, BigDecimal quantity, BigDecimal unitPrice, BigDecimal amount) {}

// Quote.java
public record Quote(int quoteId, String quoteNumber, int editionId, int exhibitorId, String status,
                    BigDecimal discountPct, BigDecimal listAmount, BigDecimal netAmount, LocalDate validUntil,
                    OffsetDateTime createdAt, int rowVersion, List<DocumentLine> lines) {
    public Quote withLines(List<DocumentLine> newLines) {
        return new Quote(quoteId, quoteNumber, editionId, exhibitorId, status, discountPct, listAmount, netAmount,
                validUntil, createdAt, rowVersion, newLines);
    }
}

// ContractFromQuote.java
public record ContractFromQuote(LocalDate signedOn, Boolean isRenewal) {}

// ContractStandRef.java
public record ContractStandRef(int standEditionId, String standCode, BigDecimal sqm) {}

// Payment.java
public record Payment(int paymentId, int contractId, String kind, LocalDate dueOn, BigDecimal dueAmount,
                      String dueAmountBasis, LocalDate paidOn, BigDecimal paidAmount, boolean paidAmountIsAssumed,
                      String state) {}

// Contract.java
public record Contract(int contractId, String contractNumber, int editionId, int exhibitorId, Integer quoteId,
                       String status, LocalDate signedOn, BigDecimal listAmount, BigDecimal discountPct,
                       BigDecimal netAmount, boolean isRenewal, int rowVersion, List<ContractStandRef> stands,
                       List<DocumentLine> lines, List<Payment> payments) {}
```

(ogni file con gli `import java.math.BigDecimal; java.time.*; java.util.List` che servono.)

- [ ] **Step 2: Scrivi il test che fallisce**

`backend/src/test/java/it/arcade/backend/commercial/PricingCalculatorTest.java`:

```java
package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.commercial.PricingCalculator.PriceItem;
import it.arcade.backend.commercial.PricingCalculator.PricedQuote;
import it.arcade.backend.commercial.PricingCalculator.StandInfo;
import it.arcade.backend.commercial.dto.QuoteLineInput;
import it.arcade.backend.error.ApiException;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class PricingCalculatorTest {

    private static BigDecimal d(String v) { return new BigDecimal(v); }

    private static final PriceItem SP1 = new PriceItem(1, "SP-P1", "Spazio P1", "SPACE", "SQM", d("100.00"), null, 1, null, null);
    private static final PriceItem MAG_ANG = new PriceItem(2, "MAG-ANGOLO", "Maggiorazione angolo", "SURCHARGE", "PCT_OF_SPACE", null, d("0.1000"), null, "ANGOLO", null);
    private static final PriceItem EXTRA = new PriceItem(3, "EX-EL6", "Allaccio", "EXTRA", "EACH", d("50.00"), null, null, null, null);
    private static final PriceItem SPN = new PriceItem(4, "SPN-GOLD", "Sponsor", "SPONSORSHIP", "PACKAGE", d("5000.00"), null, null, null, 1);
    private static final Map<Integer, PriceItem> ITEMS = Map.of(1, SP1, 2, MAG_ANG, 3, EXTRA, 4, SPN);

    private static final StandInfo ANGOLO = new StandInfo(10, "P1-A01", 1, d("10.00"), "ANGOLO");
    private static final StandInfo LINEA = new StandInfo(11, "P1-A02", 1, d("12.50"), "LINEA");
    private static final StandInfo P2 = new StandInfo(12, "P2-B01", 2, d("10.00"), "LINEA");
    private static final Map<Integer, StandInfo> STANDS = Map.of(10, ANGOLO, 11, LINEA, 12, P2);

    private static QuoteLineInput space(int standEditionId) { return new QuoteLineInput(1, standEditionId, null, null); }
    private static QuoteLineInput extra(String qty) { return new QuoteLineInput(3, null, d(qty), null); }

    @Test
    void spazio_con_maggiorazione_extra_e_sconto() {
        PricedQuote q = PricingCalculator.calculate(List.of(space(10), extra("2")), ITEMS, STANDS, d("0.1"));

        assertThat(q.lines()).hasSize(3);
        assertThat(q.lines().get(0).lineType()).isEqualTo("SPACE");
        assertThat(q.lines().get(0).amount()).isEqualByComparingTo("1000.00");
        assertThat(q.lines().get(1).lineType()).isEqualTo("SURCHARGE");
        assertThat(q.lines().get(1).amount()).isEqualByComparingTo("100.00");
        assertThat(q.lines().get(1).standEditionId()).isEqualTo(10);
        assertThat(q.lines().get(2).amount()).isEqualByComparingTo("100.00");
        assertThat(q.listAmount()).isEqualByComparingTo("1200.00");
        assertThat(q.netAmount()).isEqualByComparingTo("1080.00");
    }

    @Test
    void stand_in_linea_non_ha_maggiorazione_e_la_metratura_decide_la_quantita() {
        PricedQuote q = PricingCalculator.calculate(List.of(space(11)), ITEMS, STANDS, null);

        assertThat(q.lines()).hasSize(1);
        assertThat(q.lines().get(0).quantity()).isEqualByComparingTo("12.50");
        assertThat(q.lines().get(0).amount()).isEqualByComparingTo("1250.00");
        assertThat(q.netAmount()).isEqualByComparingTo("1250.00");
    }

    @Test
    void il_netto_si_arrotonda_a_due_decimali() {
        PricedQuote q = PricingCalculator.calculate(List.of(extra("1")), ITEMS, STANDS, d("0.3333"));

        assertThat(q.netAmount()).isEqualByComparingTo("33.34"); // 50 x 0.6667 = 33.335 -> 33.34
    }

    @Test
    void voce_di_un_altro_padiglione_e_rifiutata() {
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(12)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).errors().get(0).field()).isEqualTo("lines[0].priceItemId"));
    }

    @Test
    void le_maggiorazioni_non_si_inviano_dal_client() {
        assertThatThrownBy(() -> PricingCalculator.calculate(
                List.of(new QuoteLineInput(2, null, d("1"), null)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void stand_ripetuto_stand_mancante_e_voce_sconosciuta_sono_errori() {
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(10), space(10)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(99)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> PricingCalculator.calculate(
                List.of(new QuoteLineInput(77, null, d("1"), null)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void la_quantita_oltre_il_massimo_della_sponsorizzazione_e_rifiutata() {
        assertThatThrownBy(() -> PricingCalculator.calculate(
                List.of(new QuoteLineInput(4, null, d("2"), null)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void maggiorazione_mancante_nel_listino_e_un_errore() {
        Map<Integer, PriceItem> senza = Map.of(1, SP1);
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(10)), senza, STANDS, null))
                .isInstanceOf(ApiException.class);
    }
}
```

- [ ] **Step 3: Esegui e verifica che fallisca**

```bash
cd backend
./mvnw -q -Dtest=PricingCalculatorTest test
```

Atteso: errore di compilazione (`PricingCalculator` non esiste).

- [ ] **Step 4: Scrivi `PricingCalculator`**

`backend/src/main/java/it/arcade/backend/commercial/PricingCalculator.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.dto.QuoteLineInput;
import it.arcade.backend.error.ValidationErrors;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/** Calcolo dei prezzi di un preventivo: funzione pura, senza accesso al database. */
public final class PricingCalculator {

    public record PriceItem(int priceItemId, String code, String name, String itemType, String unit,
                            BigDecimal unitPrice, BigDecimal pct, Integer pavilionId, String positionType,
                            Integer maxQuantity) {}

    public record StandInfo(int standEditionId, String standCode, int pavilionId, BigDecimal sqm,
                            String positionType) {}

    public record PricedLine(String lineType, int priceItemId, Integer standEditionId, String description,
                             BigDecimal quantity, BigDecimal unitPrice, BigDecimal amount) {}

    public record PricedQuote(List<PricedLine> lines, BigDecimal listAmount, BigDecimal netAmount) {}

    private PricingCalculator() {}

    private static BigDecimal money(BigDecimal v) {
        return v.setScale(2, RoundingMode.HALF_UP);
    }

    public static PricedQuote calculate(List<QuoteLineInput> inputs, Map<Integer, PriceItem> items,
                                        Map<Integer, StandInfo> stands, BigDecimal discountPct) {
        ValidationErrors errors = new ValidationErrors();
        Map<String, PriceItem> surcharges = new HashMap<>();
        items.values().stream().filter(i -> "SURCHARGE".equals(i.itemType()))
                .forEach(i -> surcharges.put(i.positionType(), i));

        List<PricedLine> lines = new ArrayList<>();
        Set<Integer> seenStands = new HashSet<>();

        for (int i = 0; i < inputs.size(); i++) {
            QuoteLineInput in = inputs.get(i);
            String f = "lines[" + i + "]";
            if (in == null || in.priceItemId() == null) {
                errors.add(f + ".priceItemId", "obbligatorio");
                continue;
            }
            PriceItem item = items.get(in.priceItemId());
            if (item == null) {
                errors.add(f + ".priceItemId", "voce non presente nel listino dell'edizione");
                continue;
            }
            switch (item.itemType()) {
                case "SPACE" -> addSpace(in, item, f, stands, surcharges, seenStands, lines, errors);
                case "SURCHARGE" -> errors.add(f + ".priceItemId", "le maggiorazioni sono calcolate dal server");
                default -> addOther(in, item, f, lines, errors);
            }
        }
        errors.throwIfAny();

        BigDecimal list = money(lines.stream().map(PricedLine::amount).reduce(BigDecimal.ZERO, BigDecimal::add));
        BigDecimal d = discountPct == null ? BigDecimal.ZERO : discountPct;
        BigDecimal net = money(list.multiply(BigDecimal.ONE.subtract(d)));
        return new PricedQuote(lines, list, net);
    }

    private static void addSpace(QuoteLineInput in, PriceItem item, String f, Map<Integer, StandInfo> stands,
                                 Map<String, PriceItem> surcharges, Set<Integer> seenStands,
                                 List<PricedLine> lines, ValidationErrors errors) {
        if (in.standEditionId() == null) {
            errors.add(f + ".standEditionId", "obbligatorio per le voci di tipo SPACE");
            return;
        }
        StandInfo stand = stands.get(in.standEditionId());
        if (stand == null) {
            errors.add(f + ".standEditionId", "stand non trovato nell'edizione");
            return;
        }
        if (!seenStands.add(in.standEditionId())) {
            errors.add(f + ".standEditionId", "stand ripetuto nel preventivo");
            return;
        }
        if (!Objects.equals(item.pavilionId(), stand.pavilionId())) {
            errors.add(f + ".priceItemId", "la voce non e' del padiglione dello stand");
            return;
        }
        BigDecimal spaceAmount = money(stand.sqm().multiply(item.unitPrice()));
        String description = in.description() != null ? in.description() : "Spazio " + stand.standCode();
        lines.add(new PricedLine("SPACE", item.priceItemId(), stand.standEditionId(), description,
                stand.sqm(), item.unitPrice(), spaceAmount));

        if (!"LINEA".equals(stand.positionType())) {
            PriceItem sur = surcharges.get(stand.positionType());
            if (sur == null) {
                errors.add(f + ".priceItemId", "manca la maggiorazione per la posizione " + stand.positionType());
                return;
            }
            BigDecimal surAmount = money(spaceAmount.multiply(sur.pct()));
            lines.add(new PricedLine("SURCHARGE", sur.priceItemId(), stand.standEditionId(),
                    sur.name() + " " + stand.standCode(), BigDecimal.ONE.setScale(2), surAmount, surAmount));
        }
    }

    private static void addOther(QuoteLineInput in, PriceItem item, String f, List<PricedLine> lines,
                                 ValidationErrors errors) {
        BigDecimal q = in.quantity();
        if (q == null || q.signum() <= 0) {
            errors.add(f + ".quantity", "deve essere maggiore di zero");
            return;
        }
        if (item.maxQuantity() != null && q.compareTo(BigDecimal.valueOf(item.maxQuantity())) > 0) {
            errors.add(f + ".quantity", "oltre la quantita' massima (" + item.maxQuantity() + ")");
            return;
        }
        String description = in.description() != null ? in.description() : item.name();
        lines.add(new PricedLine(item.itemType(), item.priceItemId(), null, description, q, item.unitPrice(),
                money(q.multiply(item.unitPrice()))));
    }
}
```

- [ ] **Step 5: Esegui il test**

```bash
./mvnw -q -Dtest=PricingCalculatorTest test
```

Atteso: `Tests run: 7, Failures: 0, Errors: 0`. Il test dell'arrotondamento: `50 × 0,6667 = 33,335` → `33,34` con `HALF_UP`.

- [ ] **Step 6: Commit**

```bash
cd ..
git add backend
git commit -m "B3a: DTO del contratto e calcolo dei prezzi del preventivo"
```

---

## Task 4: Servizio di idempotenza e numerazione

**Deliverable:** `IdempotencyService.run` esegue un'operazione con chiave: la prima volta salva la risposta, le ripetizioni la restituiscono, un contenuto diverso dà `409 DUPLICATE_REQUEST`, una chiave scaduta riparte, una richiesta fallita non consuma la chiave. `NumberGenerator` produce numeri progressivi per anno.

**Files:**
- Create: `commercial/IdempotencyService.java`, `commercial/NumberGenerator.java`
- Test: `backend/src/test/java/it/arcade/backend/commercial/IdempotencyServiceTest.java`

**Interfaces:**
- Consumes: `ScopedDb.write`, `ApiException` (Task 2).
- Produces:
  - `IdempotencyService.run(String principal, String operation, String key, Object hashInput, Function<JdbcClient, Created> work)` → `Result`
  - `IdempotencyService.Created(int status, Object body)`; `IdempotencyService.Result(int status, String body, boolean replayed)`
  - `NumberGenerator.next(JdbcClient jdbc, String prefix, int year, String table, String column)` → `String` (es. `Q2098-0001`)

- [ ] **Step 1: Scrivi il test che fallisce**

`backend/src/test/java/it/arcade/backend/commercial/IdempotencyServiceTest.java`:

```java
package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.commercial.IdempotencyService.Created;
import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.support.Fixtures;
import it.arcade.backend.support.PostgresSupport;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest
class IdempotencyServiceTest {

    @Autowired IdempotencyService idem;
    @Autowired ScopedDb db;
    @Autowired NumberGenerator numbers;

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
    }

    private static String key() { return UUID.randomUUID().toString(); }

    @Test
    void la_prima_volta_esegue_e_la_seconda_restituisce_la_risposta_salvata() {
        String k = key();
        AtomicInteger eseguite = new AtomicInteger();

        Result a = idem.run("u", "op", k, List.of("x"), j -> { eseguite.incrementAndGet(); return new Created(201, List.of("ok")); });
        Result b = idem.run("u", "op", k, List.of("x"), j -> { eseguite.incrementAndGet(); return new Created(201, List.of("altro")); });

        assertThat(eseguite.get()).isEqualTo(1);
        assertThat(a.replayed()).isFalse();
        assertThat(b.replayed()).isTrue();
        assertThat(b.status()).isEqualTo(201);
        assertThat(b.body()).isEqualTo(a.body());
    }

    @Test
    void stessa_chiave_con_contenuto_diverso_da_409_duplicate_request() {
        String k = key();
        idem.run("u", "op", k, List.of("x"), j -> new Created(201, "ok"));

        assertThatThrownBy(() -> idem.run("u", "op", k, List.of("diverso"), j -> new Created(201, "ok")))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).code()).isEqualTo("DUPLICATE_REQUEST"));
    }

    @Test
    void una_richiesta_fallita_non_consuma_la_chiave() {
        String k = key();
        assertThatThrownBy(() -> idem.run("u", "op", k, List.of("x"), j -> { throw ApiException.conflict("X", "x"); }))
                .isInstanceOf(ApiException.class);

        Result r = idem.run("u", "op", k, List.of("x"), j -> new Created(201, "ok"));
        assertThat(r.replayed()).isFalse();
    }

    @Test
    void una_chiave_di_piu_di_24_ore_riparte_anche_con_contenuto_diverso() {
        String k = key();
        idem.run("u", "op", k, List.of("x"), j -> new Created(201, "prima"));
        Fixtures.owner().update("UPDATE core.idempotency_key SET created_at = now() - interval '25 hours' "
                + "WHERE idem_key = ?", k);

        Result r = idem.run("u", "op", k, List.of("diverso"), j -> new Created(201, "seconda"));
        assertThat(r.replayed()).isFalse();
        assertThat(r.body()).contains("seconda");
    }

    @Test
    void chiavi_di_utenti_o_operazioni_diverse_non_si_scontrano() {
        String k = key();
        idem.run("u1", "op", k, List.of("x"), j -> new Created(201, "1"));
        Result r = idem.run("u2", "op", k, List.of("x"), j -> new Created(201, "2"));
        assertThat(r.replayed()).isFalse();
    }

    @Test
    void la_chiave_deve_avere_da_8_a_64_caratteri() {
        assertThatThrownBy(() -> idem.run("u", "op", "corta", List.of("x"), j -> new Created(201, "ok")))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).status().value()).isEqualTo(400));
        assertThatThrownBy(() -> idem.run("u", "op", null, List.of("x"), j -> new Created(201, "ok")))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void i_numeri_sono_progressivi_per_anno() {
        String a = db.write(j -> numbers.next(j, "Q", 2090, "core.quote", "quote_number"));
        assertThat(a).isEqualTo("Q2090-0001");
        db.write(j -> {
            j.sql("INSERT INTO core.quote (quote_number, edition_id, exhibitor_id) VALUES ('Q2090-0007', ?, ?)")
                    .param(Fixtures.edition(2098))
                    .param(Fixtures.owner().queryForObject("SELECT min(exhibitor_id) FROM core.exhibitor", Integer.class))
                    .update();
            return null;
        });
        String b = db.write(j -> numbers.next(j, "Q", 2090, "core.quote", "quote_number"));
        assertThat(b).isEqualTo("Q2090-0008");
    }
}
```

- [ ] **Step 2: Esegui e verifica che fallisca**

```bash
cd backend
./mvnw -q -Dtest=IdempotencyServiceTest test
```

Atteso: errore di compilazione (le due classi non esistono).

- [ ] **Step 3: Scrivi il codice**

`backend/src/main/java/it/arcade/backend/commercial/NumberGenerator.java`:

```java
package it.arcade.backend.commercial;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/** Numeri progressivi per anno (es. Q2026-0001). Chiamare dentro una transazione in scrittura. */
@Component
public class NumberGenerator {

    /** `table` e `column` sono costanti del codice, mai testo del client. */
    public String next(JdbcClient jdbc, String prefix, int year, String table, String column) {
        // Blocco consultivo per tabella e anno: due richieste parallele non prendono lo stesso numero.
        jdbc.sql("SELECT 1 FROM (SELECT pg_advisory_xact_lock(hashtext(:k))) t")
                .param("k", table + ":" + year).query(Integer.class).single();
        int next = jdbc.sql("SELECT COALESCE(MAX(CAST(substring(" + column + " from '[0-9]+$') AS integer)), 0) + 1 "
                        + "FROM " + table + " WHERE " + column + " LIKE :p")
                .param("p", prefix + year + "-%").query(Integer.class).single();
        return String.format("%s%d-%04d", prefix, year, next);
    }
}
```

`backend/src/main/java/it/arcade/backend/commercial/IdempotencyService.java`:

```java
package it.arcade.backend.commercial;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.function.Function;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/**
 * Stessa chiave = stessa risposta per 24 ore. La chiave si inserisce nella stessa transazione
 * dell'operazione: se l'operazione fallisce, annulla anche la chiave (si salvano solo i successi).
 * Due richieste con la stessa chiave in parallelo: la seconda attende l'indice univoco e poi
 * riceve la risposta salvata.
 */
@Service
public class IdempotencyService {

    public record Created(int status, Object body) {}

    public record Result(int status, String body, boolean replayed) {}

    private record Row(long id, String hash, Integer status, String body, boolean expired) {}

    private final ScopedDb db;
    private final ObjectMapper mapper;

    public IdempotencyService(ScopedDb db, ObjectMapper mapper) {
        this.db = db;
        this.mapper = mapper;
    }

    /** `hashInput` identifica la richiesta (operazione, risorsa e contenuto): deve avere ordine stabile (List, record). */
    public Result run(String principal, String operation, String key, Object hashInput,
                      Function<JdbcClient, Created> work) {
        if (key == null || key.length() < 8 || key.length() > 64) {
            throw ApiException.badRequest("VALIDATION_ERROR", "Idempotency-Key obbligatoria (da 8 a 64 caratteri)");
        }
        String hash = hash(hashInput);
        return db.write(jdbc -> {
            Long id = jdbc.sql("""
                            INSERT INTO core.idempotency_key (principal, operation, idem_key, request_hash)
                            VALUES (:p, :o, :k, :h)
                            ON CONFLICT (principal, operation, idem_key) DO NOTHING
                            RETURNING idempotency_key_id""")
                    .param("p", principal).param("o", operation).param("k", key).param("h", hash)
                    .query(Long.class).optional().orElse(null);
            if (id == null) {
                Row row = jdbc.sql("""
                                SELECT idempotency_key_id, request_hash, response_status, response_body,
                                       (created_at < now() - interval '24 hours') AS expired
                                  FROM core.idempotency_key
                                 WHERE principal = :p AND operation = :o AND idem_key = :k FOR UPDATE""")
                        .param("p", principal).param("o", operation).param("k", key)
                        .query((rs, n) -> new Row(rs.getLong(1), rs.getString(2), rs.getObject(3, Integer.class),
                                rs.getString(4), rs.getBoolean(5)))
                        .single();
                if (row.expired()) {
                    jdbc.sql("""
                                    UPDATE core.idempotency_key
                                       SET request_hash = :h, response_status = NULL, response_body = NULL,
                                           created_at = now()
                                     WHERE idempotency_key_id = :id""")
                            .param("h", hash).param("id", row.id()).update();
                    id = row.id();
                } else if (!row.hash().equals(hash)) {
                    throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REQUEST",
                            "Stessa Idempotency-Key con contenuto diverso", null);
                } else if (row.status() == null) {
                    throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REQUEST",
                            "Richiesta con questa chiave ancora in corso", null);
                } else {
                    return new Result(row.status(), row.body(), true);
                }
            }
            Created created = work.apply(jdbc);
            String body = json(created.body());
            jdbc.sql("""
                            UPDATE core.idempotency_key SET response_status = :s, response_body = :b
                             WHERE idempotency_key_id = :id""")
                    .param("s", created.status()).param("b", body).param("id", id).update();
            return new Result(created.status(), body, false);
        });
    }

    private String json(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Risposta non serializzabile", e);
        }
    }

    private String hash(Object input) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(json(input).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
```

- [ ] **Step 4: Esegui il test**

```bash
./mvnw -q -Dtest=IdempotencyServiceTest test
```

Atteso: `Tests run: 7, Failures: 0, Errors: 0`.

- [ ] **Step 5: Commit**

```bash
cd ..
git add backend
git commit -m "B3a: idempotenza delle richieste e numerazione progressiva"
```

---

## Task 5: Creazione del preventivo e riserva degli stand

**Deliverable:** `POST /quotes` e `GET /quotes/{id}` funzionano con prezzi del server, riserva degli stand, 409 e idempotenza; ruoli applicati.

**Files:**
- Create: `commercial/QuoteProperties.java`, `ContractProperties.java`, `PriceListRepository.java`, `QuoteRepository.java`, `StandReservation.java`, `QuoteService.java`, `QuoteController.java`
- Modify: `config/SecurityConfig.java`, `backend/src/main/resources/application.yml`
- Create (test): `support/CommercialApiTest.java`, `commercial/CreateQuoteApiTest.java`; modify `api/ErrorHandlingApiTest.java`

**Interfaces:**
- Consumes: `PricingCalculator` e DTO (Task 3), `IdempotencyService`, `NumberGenerator` (Task 4), `ScopedDb.write/read`, `ValidationErrors` (Task 2), `Fixtures` (Task 1).
- Produces:
  - `QuoteRepository.find(JdbcClient, int quoteId)` → `Optional<Quote>`
  - `StandReservation.LockedStand(int standEditionId, String commercialStatus, boolean reservationActive, Integer reservedByQuoteId)`; `StandReservation.lock(JdbcClient, Collection<Integer> ids)` → `List<LockedStand>` ordinata per id; `StandReservation.reserve(JdbcClient, List<LockedStand>, int quoteId)`; `StandReservation.assertOwnedBy(List<LockedStand>, int quoteId)`
  - `PriceListRepository.load(JdbcClient, int editionId)` → `Optional<PriceListData>`; `PriceListData(int priceListId, String status, BigDecimal depositPct, Integer balanceDaysBefore, Map<Integer,PriceItem> items)`
  - `QuoteService.create(String principal, String key, QuoteCreate req)` → `IdempotencyService.Result`
  - `CommercialApiTest` (base): `staff()`, `quoteBody(int year, int exhibitorId, double discount, List<Map<String,Object>> lines)`, `spaceLine(int year, int standEditionId)`, `extraLine(int year, int qty)`, `postQuote(String key, Object body)` → `ResultActions`, `createdQuote(...)` → `JsonNode`, `key()`.

- [ ] **Step 1: Scrivi la base dei test e i test che falliscono**

`backend/src/test/java/it/arcade/backend/support/CommercialApiTest.java`:

```java
package it.arcade.backend.support;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.security.Role;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/** Aiuti per i test dei preventivi e dei contratti. */
public abstract class CommercialApiTest extends ApiTest {

    protected static final int YEAR = 2098;

    @Autowired protected ObjectMapper json;

    protected String staff() { return bearer(null, Role.COMMERCIAL); }

    protected static String key() { return UUID.randomUUID().toString(); }

    protected int espositore() { return exhibitorId("ESP901"); }

    protected Map<String, Object> spaceLine(int year, int standEditionId) {
        return Map.of("priceItemId", Fixtures.priceItem(year, "SP-P1"), "standEditionId", standEditionId, "quantity", 1);
    }

    protected Map<String, Object> extraLine(int year, int qty) {
        return Map.of("priceItemId", Fixtures.priceItem(year, "EX-EL6"), "quantity", qty);
    }

    protected Map<String, Object> quoteBody(int year, int exhibitorId, double discount, List<Map<String, Object>> lines) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("editionId", Fixtures.edition(year));
        body.put("exhibitorId", exhibitorId);
        body.put("discountPct", discount);
        body.put("lines", lines);
        return body;
    }

    protected ResultActions postQuote(String key, Object body) throws Exception {
        return mvc.perform(post("/quotes")
                .header(HttpHeaders.AUTHORIZATION, staff())
                .header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(body)));
    }

    protected JsonNode read(ResultActions r) throws Exception {
        return json.readTree(r.andReturn().getResponse().getContentAsString());
    }

    protected JsonNode createdQuote(int year, int exhibitorId, double discount, List<Map<String, Object>> lines)
            throws Exception {
        return read(postQuote(key(), quoteBody(year, exhibitorId, discount, lines)).andExpect(status().isCreated()));
    }

    protected ResultActions getQuote(int quoteId) throws Exception {
        return mvc.perform(get("/quotes/" + quoteId).header(HttpHeaders.AUTHORIZATION, staff()));
    }
}
```

`backend/src/test/java/it/arcade/backend/commercial/CreateQuoteApiTest.java`:

```java
package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.security.Role;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

class CreateQuoteApiTest extends CommercialApiTest {

    @Test
    void calcola_i_prezzi_e_riserva_lo_stand() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "ANGOLO");

        JsonNode q = createdQuote(YEAR, espositore(), 0.1, List.of(spaceLine(YEAR, stand), extraLine(YEAR, 2)));

        assertThat(q.get("status").asText()).isEqualTo("DRAFT");
        assertThat(q.get("quoteNumber").asText()).startsWith("Q2098-");
        assertThat(q.get("lines")).hasSize(3);
        assertThat(q.get("listAmount").decimalValue()).isEqualByComparingTo("1200.00");
        assertThat(q.get("netAmount").decimalValue()).isEqualByComparingTo("1080.00");
        assertThat(q.get("rowVersion").asInt()).isZero();
        assertThat(Fixtures.owner().queryForMap(
                "SELECT commercial_status, reserved_by_quote_id FROM core.stand_edition WHERE stand_edition_id = ?",
                stand))
                .containsEntry("commercial_status", "RESERVED")
                .containsEntry("reserved_by_quote_id", q.get("quoteId").asInt());
    }

    @Test
    void uno_stand_gia_riservato_risponde_409_e_non_crea_nulla() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        createdQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("STAND_ALREADY_RESERVED"));
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void uno_stand_venduto_risponde_409() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Fixtures.owner().update("UPDATE core.stand_edition SET commercial_status = 'SOLD' WHERE stand_edition_id = ?", stand);

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("STAND_ALREADY_SOLD"));
    }

    @Test
    void uno_stand_non_vendibile_risponde_422() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Fixtures.owner().update("UPDATE core.stand_edition SET commercial_status = 'NOT_SELLABLE' WHERE stand_edition_id = ?", stand);

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("STAND_NOT_SELLABLE"));
    }

    @Test
    void una_riserva_scaduta_puo_essere_ripresa_da_un_altro_preventivo() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        createdQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));
        Fixtures.owner().update("UPDATE core.stand_edition SET reserved_until = now() - interval '1 hour' "
                + "WHERE stand_edition_id = ?", stand);

        JsonNode second = createdQuote(YEAR, exhibitorId("ESP902"), 0, List.of(spaceLine(YEAR, stand)));

        assertThat(Fixtures.owner().queryForObject(
                "SELECT reserved_by_quote_id FROM core.stand_edition WHERE stand_edition_id = ?", Integer.class, stand))
                .isEqualTo(second.get("quoteId").asInt());
    }

    @Test
    void i_dati_non_validi_rispondono_422_con_errors() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P2", "10.00", "LINEA");

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)))) // voce SP-P1 su stand P2
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.errors[0].field").value("lines[0].priceItemId"));
        postQuote(key(), quoteBody(YEAR, espositore(), 1.5, List.of(extraLine(YEAR, 1))))
                .andExpect(status().isUnprocessableEntity());
        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of()))
                .andExpect(status().isUnprocessableEntity());
        postQuote(key(), quoteBody(YEAR, 999999, 0, List.of(extraLine(YEAR, 1))))
                .andExpect(status().isUnprocessableEntity());
        postQuote(key(), quoteBody(2024, espositore(), 0, List.of(extraLine(YEAR, 1)))) // edizione chiusa
                .andExpect(status().isUnprocessableEntity());
    }

    @Test
    void senza_idempotency_key_risponde_400() throws Exception {
        mvc.perform(post("/quotes").header(HttpHeaders.AUTHORIZATION, staff())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1))))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void la_ripetizione_con_la_stessa_chiave_restituisce_la_prima_risposta() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        String k = key();
        Map<String, Object> body = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));

        JsonNode first = read(postQuote(k, body).andExpect(status().isCreated()));
        JsonNode second = read(postQuote(k, body).andExpect(status().isCreated())
                .andExpect(header().string("Idempotent-Replayed", "true")));

        assertThat(second).isEqualTo(first);
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void la_stessa_chiave_con_contenuto_diverso_risponde_409_duplicate_request() throws Exception {
        String k = key();
        createdQuote(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)));
        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)))).andExpect(status().isCreated());

        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 2))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("DUPLICATE_REQUEST"));
    }

    @Test
    void una_richiesta_fallita_non_consuma_la_chiave_e_una_chiave_vecchia_riparte() throws Exception {
        String k = key();
        postQuote(k, quoteBody(YEAR, espositore(), 1.5, List.of(extraLine(YEAR, 1)))) // non valida
                .andExpect(status().isUnprocessableEntity());
        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)))).andExpect(status().isCreated());

        Fixtures.owner().update("UPDATE core.idempotency_key SET created_at = now() - interval '25 hours' "
                + "WHERE idem_key = ?", k);
        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 3)))) // contenuto diverso, chiave scaduta
                .andExpect(status().isCreated());
    }

    @Test
    void il_dettaglio_si_legge_e_un_id_inesistente_o_non_numerico_da_errore() throws Exception {
        JsonNode q = createdQuote(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)));

        getQuote(q.get("quoteId").asInt()).andExpect(status().isOk())
                .andExpect(jsonPath("$.quoteNumber").value(q.get("quoteNumber").asText()));
        getQuote(999999).andExpect(status().isNotFound());
        mvc.perform(get("/quotes/abc").header(HttpHeaders.AUTHORIZATION, staff()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void solo_admin_e_commercial_possono_creare_e_leggere_preventivi() throws Exception {
        String body = json.writeValueAsString(quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1))));
        for (Role ruolo : List.of(Role.EXHIBITOR, Role.OPS, Role.SCANNER)) {
            mvc.perform(post("/quotes").header(HttpHeaders.AUTHORIZATION, bearer(espositore(), ruolo))
                            .header("Idempotency-Key", key()).contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isForbidden());
        }
        mvc.perform(post("/quotes").header("Idempotency-Key", key()).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/quotes").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN))
                        .header("Idempotency-Key", key()).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated());
    }
}
```

- [ ] **Step 2: Esegui e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest=CreateQuoteApiTest test
```

Atteso: i test falliscono con `403` (nessuna regola per `/quotes` in `SecurityConfig`) o `404`.

- [ ] **Step 3: Scrivi le proprietà e i repository**

`commercial/QuoteProperties.java`:

```java
package it.arcade.backend.commercial;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Assunzione da confermare coi product owner: durata della riserva degli stand. */
@ConfigurationProperties(prefix = "arcade.quote")
public record QuoteProperties(@DefaultValue("14") int reservationDays) {}
```

`commercial/ContractProperties.java`:

```java
package it.arcade.backend.commercial;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Assunzione da confermare coi product owner (domanda D34): giorni tra la firma e la scadenza dell'acconto. */
@ConfigurationProperties(prefix = "arcade.contract")
public record ContractProperties(@DefaultValue("15") int depositDueDays) {}
```

`commercial/PriceListRepository.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.PricingCalculator.PriceItem;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class PriceListRepository {

    public record PriceListData(int priceListId, String status, BigDecimal depositPct, Integer balanceDaysBefore,
                                Map<Integer, PriceItem> items) {}

    public Optional<PriceListData> load(JdbcClient jdbc, int editionId) {
        return jdbc.sql("SELECT price_list_id, status, deposit_pct, balance_days_before "
                        + "FROM core.price_list WHERE edition_id = :e")
                .param("e", editionId)
                .query((rs, n) -> new Object[] {rs.getInt(1), rs.getString(2), rs.getBigDecimal(3),
                        rs.getObject(4, Integer.class)})
                .optional()
                .map(h -> new PriceListData((Integer) h[0], (String) h[1], (BigDecimal) h[2], (Integer) h[3],
                        items(jdbc, (Integer) h[0])));
    }

    private Map<Integer, PriceItem> items(JdbcClient jdbc, int priceListId) {
        Map<Integer, PriceItem> items = new LinkedHashMap<>();
        jdbc.sql("""
                        SELECT price_item_id, code, name, item_type, unit, unit_price, pct, pavilion_id,
                               position_type, max_quantity
                          FROM core.price_item WHERE price_list_id = :pl ORDER BY price_item_id""")
                .param("pl", priceListId)
                .query(rs -> {
                    items.put(rs.getInt("price_item_id"), new PriceItem(rs.getInt("price_item_id"),
                            rs.getString("code"), rs.getString("name"), rs.getString("item_type"),
                            rs.getString("unit"), rs.getBigDecimal("unit_price"), rs.getBigDecimal("pct"),
                            rs.getObject("pavilion_id", Integer.class), rs.getString("position_type"),
                            rs.getObject("max_quantity", Integer.class)));
                });
        return items;
    }
}
```

`commercial/QuoteRepository.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.PricingCalculator.PricedLine;
import it.arcade.backend.commercial.dto.DocumentLine;
import it.arcade.backend.commercial.dto.Quote;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class QuoteRepository {

    public Optional<Quote> find(JdbcClient jdbc, int quoteId) {
        return jdbc.sql("""
                        SELECT quote_id, quote_number, edition_id, exhibitor_id, status, discount_pct, list_amount,
                               net_amount, valid_until, created_at, row_version
                          FROM core.quote WHERE quote_id = :id""")
                .param("id", quoteId)
                .query((rs, n) -> new Quote(rs.getInt("quote_id"), rs.getString("quote_number"),
                        rs.getInt("edition_id"), rs.getInt("exhibitor_id"), rs.getString("status"),
                        rs.getBigDecimal("discount_pct"), rs.getBigDecimal("list_amount"),
                        rs.getBigDecimal("net_amount"), rs.getObject("valid_until", LocalDate.class),
                        rs.getObject("created_at", OffsetDateTime.class), rs.getInt("row_version"), List.of()))
                .optional()
                .map(q -> q.withLines(lines(jdbc, quoteId)));
    }

    private List<DocumentLine> lines(JdbcClient jdbc, int quoteId) {
        return jdbc.sql("""
                        SELECT l.line_no, i.item_type AS line_type, l.price_item_id, l.stand_edition_id, s.stand_code,
                               l.description, l.quantity, l.unit_price, l.amount
                          FROM core.quote_line l
                          JOIN core.price_item i ON i.price_item_id = l.price_item_id
                          LEFT JOIN core.stand_edition se ON se.stand_edition_id = l.stand_edition_id
                          LEFT JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE l.quote_id = :id ORDER BY l.line_no""")
                .param("id", quoteId)
                .query((rs, n) -> new DocumentLine(rs.getInt("line_no"), rs.getString("line_type"),
                        rs.getInt("price_item_id"), rs.getObject("stand_edition_id", Integer.class),
                        rs.getString("stand_code"), rs.getString("description"), rs.getBigDecimal("quantity"),
                        rs.getBigDecimal("unit_price"), rs.getBigDecimal("amount")))
                .list();
    }

    public int insert(JdbcClient jdbc, String number, int editionId, int exhibitorId, BigDecimal discountPct,
                      BigDecimal listAmount, BigDecimal netAmount, LocalDate validUntil, int defaultDays) {
        return jdbc.sql("""
                        INSERT INTO core.quote (quote_number, edition_id, exhibitor_id, status, discount_pct,
                                                list_amount, net_amount, valid_until)
                        VALUES (:num, :ed, :ex, 'DRAFT', :d, :l, :n,
                                COALESCE(CAST(:vu AS date), CURRENT_DATE + CAST(:days AS integer)))
                        RETURNING quote_id""")
                .param("num", number).param("ed", editionId).param("ex", exhibitorId).param("d", discountPct)
                .param("l", listAmount).param("n", netAmount).param("vu", validUntil).param("days", defaultDays)
                .query(Integer.class).single();
    }

    public void insertLine(JdbcClient jdbc, int quoteId, int lineNo, PricedLine l) {
        jdbc.sql("""
                        INSERT INTO core.quote_line (quote_id, line_no, price_item_id, stand_edition_id, description,
                                                     quantity, unit_price, amount)
                        VALUES (:q, :n, :pi, :se, :desc, :qty, :up, :amt)""")
                .param("q", quoteId).param("n", lineNo).param("pi", l.priceItemId())
                .param("se", l.standEditionId()).param("desc", l.description()).param("qty", l.quantity())
                .param("up", l.unitPrice()).param("amt", l.amount()).update();
    }
}
```

`commercial/StandReservation.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.error.ApiException;
import java.util.Collection;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/** Blocco e cambio di stato degli stand. Gli stand si bloccano SEMPRE in ordine di id: niente stalli. */
@Component
public class StandReservation {

    public record LockedStand(int standEditionId, String commercialStatus, boolean reservationActive,
                              Integer reservedByQuoteId) {}

    private final QuoteProperties properties;

    public StandReservation(QuoteProperties properties) {
        this.properties = properties;
    }

    public List<LockedStand> lock(JdbcClient jdbc, Collection<Integer> ids) {
        if (ids.isEmpty()) {
            return List.of();
        }
        return jdbc.sql("""
                        SELECT stand_edition_id, commercial_status,
                               (reserved_until IS NOT NULL AND reserved_until > now()) AS reservation_active,
                               reserved_by_quote_id
                          FROM core.stand_edition WHERE stand_edition_id IN (:ids)
                         ORDER BY stand_edition_id FOR UPDATE""")
                .param("ids", ids)
                .query((rs, n) -> new LockedStand(rs.getInt("stand_edition_id"), rs.getString("commercial_status"),
                        rs.getBoolean("reservation_active"), rs.getObject("reserved_by_quote_id", Integer.class)))
                .list();
    }

    /** Riserva gli stand per il preventivo: SOLD/RESERVED attiva -> 409, FREE/NOT_SELLABLE -> 422. */
    public void reserve(JdbcClient jdbc, List<LockedStand> stands, int quoteId) {
        for (LockedStand s : stands) {
            switch (s.commercialStatus()) {
                case "SOLD" -> throw ApiException.conflict("STAND_ALREADY_SOLD", "Stand gia' assegnato a un contratto");
                case "FREE", "NOT_SELLABLE" ->
                        throw ApiException.unprocessable("STAND_NOT_SELLABLE", "Stand non commercializzabile");
                case "RESERVED" -> {
                    if (s.reservationActive()) {
                        throw ApiException.conflict("STAND_ALREADY_RESERVED", "Stand riservato da un altro preventivo");
                    }
                }
                default -> { }
            }
        }
        for (LockedStand s : stands) {
            jdbc.sql("""
                            UPDATE core.stand_edition
                               SET commercial_status = 'RESERVED',
                                   reserved_until = now() + make_interval(days => :days),
                                   reserved_by_quote_id = :q,
                                   row_version = row_version + 1
                             WHERE stand_edition_id = :id""")
                    .param("days", properties.reservationDays()).param("q", quoteId)
                    .param("id", s.standEditionId()).update();
        }
    }

    /** In conversione ogni stand deve essere ancora riservato da QUESTO preventivo. */
    public void assertOwnedBy(List<LockedStand> stands, int quoteId) {
        for (LockedStand s : stands) {
            if ("SOLD".equals(s.commercialStatus())) {
                throw ApiException.conflict("STAND_ALREADY_SOLD", "Stand gia' assegnato a un contratto");
            }
            if (!"RESERVED".equals(s.commercialStatus()) || !java.util.Objects.equals(s.reservedByQuoteId(), quoteId)) {
                if ("RESERVED".equals(s.commercialStatus())) {
                    throw ApiException.conflict("STAND_ALREADY_RESERVED", "Stand riservato da un altro preventivo");
                }
                throw ApiException.conflict("INVALID_STATE_TRANSITION", "La riserva dello stand non e' piu' valida");
            }
        }
    }
}
```

- [ ] **Step 4: Scrivi il servizio e il controller**

`commercial/QuoteService.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.IdempotencyService.Created;
import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.commercial.PriceListRepository.PriceListData;
import it.arcade.backend.commercial.PricingCalculator.PricedQuote;
import it.arcade.backend.commercial.PricingCalculator.StandInfo;
import it.arcade.backend.commercial.StandReservation.LockedStand;
import it.arcade.backend.commercial.dto.Quote;
import it.arcade.backend.commercial.dto.QuoteCreate;
import it.arcade.backend.commercial.dto.QuoteLineInput;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.error.ValidationErrors;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class QuoteService {

    private static final int MAX_LINES = 200;

    private final ScopedDb db;
    private final IdempotencyService idempotency;
    private final NumberGenerator numbers;
    private final PriceListRepository priceLists;
    private final QuoteRepository quotes;
    private final StandReservation stands;
    private final QuoteProperties properties;

    public QuoteService(ScopedDb db, IdempotencyService idempotency, NumberGenerator numbers,
                        PriceListRepository priceLists, QuoteRepository quotes, StandReservation stands,
                        QuoteProperties properties) {
        this.db = db;
        this.idempotency = idempotency;
        this.numbers = numbers;
        this.priceLists = priceLists;
        this.quotes = quotes;
        this.stands = stands;
        this.properties = properties;
    }

    public Result create(String principal, String key, QuoteCreate req) {
        validateShape(req);
        return idempotency.run(principal, "createQuote", key, List.of("createQuote", req),
                jdbc -> new Created(201, doCreate(jdbc, req)));
    }

    public Quote get(int quoteId, it.arcade.backend.db.DbRole role) {
        return db.read(role, null, jdbc -> quotes.find(jdbc, quoteId))
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Preventivo non trovato"));
    }

    private void validateShape(QuoteCreate req) {
        ValidationErrors v = new ValidationErrors();
        if (req == null) {
            throw ApiException.badRequest("VALIDATION_ERROR", "Corpo della richiesta mancante");
        }
        if (req.editionId() == null) v.add("editionId", "obbligatorio");
        if (req.exhibitorId() == null) v.add("exhibitorId", "obbligatorio");
        if (req.discountPct() != null
                && (req.discountPct().signum() < 0 || req.discountPct().compareTo(BigDecimal.ONE) > 0)) {
            v.add("discountPct", "deve essere tra 0 e 1");
        }
        if (req.validUntil() != null && req.validUntil().isBefore(LocalDate.now())) {
            v.add("validUntil", "non puo' essere nel passato");
        }
        if (req.lines() == null || req.lines().isEmpty()) {
            v.add("lines", "almeno una riga");
        } else if (req.lines().size() > MAX_LINES) {
            throw new ApiException(org.springframework.http.HttpStatus.PAYLOAD_TOO_LARGE, "PAYLOAD_TOO_LARGE",
                    "Troppe righe (massimo " + MAX_LINES + ")", null);
        }
        v.throwIfAny();
    }

    private Quote doCreate(JdbcClient jdbc, QuoteCreate req) {
        ValidationErrors v = new ValidationErrors();
        Map<String, Object> edition = jdbc.sql("SELECT year, status FROM core.edition WHERE edition_id = :id")
                .param("id", req.editionId())
                .query((rs, n) -> Map.<String, Object>of("year", rs.getInt("year"), "status", rs.getString("status")))
                .optional().orElse(null);
        if (edition == null) {
            v.add("editionId", "edizione inesistente");
        } else if (!"SALES_OPEN".equals(edition.get("status"))) {
            v.add("editionId", "l'edizione non e' in vendita");
        }
        Integer exhibitors = jdbc.sql("SELECT count(*) FROM core.exhibitor WHERE exhibitor_id = :id")
                .param("id", req.exhibitorId()).query(Integer.class).single();
        if (exhibitors == 0) {
            v.add("exhibitorId", "espositore inesistente");
        }
        v.throwIfAny();

        PriceListData priceList = priceLists.load(jdbc, req.editionId()).orElse(null);
        if (priceList == null || !"PUBLISHED".equals(priceList.status())) {
            v.add("editionId", "listino non pubblicato per l'edizione");
            v.throwIfAny();
        }

        List<Integer> standIds = req.lines().stream().map(QuoteLineInput::standEditionId)
                .filter(java.util.Objects::nonNull).distinct().sorted().toList();
        Map<Integer, StandInfo> standInfo = loadStandInfo(jdbc, standIds, req.editionId());

        PricedQuote priced = PricingCalculator.calculate(req.lines(), priceList.items(), standInfo, req.discountPct());

        // Blocco degli stand in ordine di id, poi il preventivo: stesso ordine in ogni richiesta.
        List<LockedStand> locked = stands.lock(jdbc, new TreeSet<>(standInfo.keySet()));
        int year = (Integer) edition.get("year");
        String number = numbers.next(jdbc, "Q", year, "core.quote", "quote_number");
        BigDecimal discount = req.discountPct() == null ? BigDecimal.ZERO : req.discountPct();
        int quoteId = quotes.insert(jdbc, number, req.editionId(), req.exhibitorId(), discount,
                priced.listAmount(), priced.netAmount(), req.validUntil(), properties.reservationDays());
        int lineNo = 1;
        for (var line : priced.lines()) {
            quotes.insertLine(jdbc, quoteId, lineNo++, line);
        }
        stands.reserve(jdbc, locked, quoteId);
        return quotes.find(jdbc, quoteId).orElseThrow();
    }

    private Map<Integer, StandInfo> loadStandInfo(JdbcClient jdbc, List<Integer> ids, int editionId) {
        Map<Integer, StandInfo> map = new HashMap<>();
        if (ids.isEmpty()) {
            return map;
        }
        jdbc.sql("""
                        SELECT se.stand_edition_id, s.stand_code, s.pavilion_id, s.sqm, s.position_type
                          FROM core.stand_edition se JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE se.stand_edition_id IN (:ids) AND se.edition_id = :ed""")
                .param("ids", ids).param("ed", editionId)
                .query(rs -> {
                    map.put(rs.getInt("stand_edition_id"), new StandInfo(rs.getInt("stand_edition_id"),
                            rs.getString("stand_code"), rs.getInt("pavilion_id"), rs.getBigDecimal("sqm"),
                            rs.getString("position_type")));
                });
        return map;
    }
}
```

Nota per chi esegue: `StandInfo` dei soli stand trovati; gli id non trovati sono segnalati dal calcolatore come `lines[i].standEditionId`.

`commercial/QuoteController.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.commercial.dto.Quote;
import it.arcade.backend.commercial.dto.QuoteCreate;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.security.CurrentUser;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class QuoteController {

    private final QuoteService quotes;

    public QuoteController(QuoteService quotes) {
        this.quotes = quotes;
    }

    static ResponseEntity<String> toResponse(Result r) {
        ResponseEntity.BodyBuilder b = ResponseEntity.status(r.status()).contentType(MediaType.APPLICATION_JSON);
        if (r.replayed()) {
            b.header("Idempotent-Replayed", "true");
        }
        return b.body(r.body());
    }

    @PostMapping("/quotes")
    public ResponseEntity<String> create(@AuthenticationPrincipal Jwt jwt,
                                         @RequestHeader(name = "Idempotency-Key", required = false) String key,
                                         @RequestBody QuoteCreate body) {
        return toResponse(quotes.create(jwt.getSubject(), key, body));
    }

    @GetMapping("/quotes/{quoteId}")
    public Quote get(@AuthenticationPrincipal Jwt jwt, @PathVariable int quoteId) {
        return quotes.get(quoteId, DbRole.forUser(CurrentUser.from(jwt)));
    }
}
```

In `config/SecurityConfig.java`, nel blocco `authorizeHttpRequests`, **prima** di `.anyRequest().denyAll()` aggiungi:

```java
                        .requestMatchers(org.springframework.http.HttpMethod.POST, "/quotes", "/quotes/*/send",
                                "/quotes/*/confirm", "/quotes/*/contract").hasAnyRole("ADMIN", "COMMERCIAL")
                        .requestMatchers(org.springframework.http.HttpMethod.GET, "/quotes/*")
                                .hasAnyRole("ADMIN", "COMMERCIAL")
                        .requestMatchers(org.springframework.http.HttpMethod.GET, "/contracts/*")
                                .hasAnyRole("ADMIN", "COMMERCIAL", "OPS")
```

In `application.yml` aggiungi in fondo:

```yaml
  quote:
    reservation-days: 14          # ASSUNZIONE da confermare coi product owner
  contract:
    deposit-due-days: 15          # ASSUNZIONE da confermare (domanda D34)
```

sotto la chiave `arcade:` esistente (stesso livello di `jwt`).

- [ ] **Step 5: Esegui i test**

```bash
./mvnw -q -Dtest=CreateQuoteApiTest test
```

Atteso: `Tests run: 11, Failures: 0, Errors: 0`. Se `GET /quotes/abc` non risponde 400, controlla il gestore `TypeMismatchException` del Task 2.

- [ ] **Step 6: Esegui tutta la suite e fai il commit**

```bash
./mvnw -q test
cd ..
git add backend
git commit -m "B3a: creazione del preventivo con prezzi del server, riserva degli stand e idempotenza"
```

---

## Task 6: Invio e conferma del preventivo

**Deliverable:** `POST /quotes/{id}/send` e `/confirm` con `If-Match`, passaggi di stato e scadenza.

**Files:**
- Modify: `commercial/QuoteService.java`, `commercial/QuoteController.java`
- Test: `backend/src/test/java/it/arcade/backend/commercial/QuoteTransitionsApiTest.java`

**Interfaces:**
- Consumes: `QuoteRepository.find`, `ScopedDb.write`, `CommercialApiTest` (Task 5).
- Produces: `QuoteService.transition(int quoteId, String ifMatch, String from, String to)` → `Quote`.

- [ ] **Step 1: Scrivi il test che fallisce**

`backend/src/test/java/it/arcade/backend/commercial/QuoteTransitionsApiTest.java`:

```java
package it.arcade.backend.commercial;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.test.web.servlet.ResultActions;

class QuoteTransitionsApiTest extends CommercialApiTest {

    private ResultActions transition(int quoteId, String azione, Object ifMatch) throws Exception {
        var req = post("/quotes/" + quoteId + "/" + azione).header(HttpHeaders.AUTHORIZATION, staff());
        if (ifMatch != null) {
            req = req.header("If-Match", ifMatch);
        }
        return mvc.perform(req);
    }

    private JsonNode nuovo() throws Exception {
        return createdQuote(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)));
    }

    @Test
    void il_percorso_bozza_inviato_confermato_aggiorna_stato_e_versione() throws Exception {
        int id = nuovo().get("quoteId").asInt();

        transition(id, "send", 0).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SENT")).andExpect(jsonPath("$.rowVersion").value(1));
        transition(id, "confirm", "\"1\"").andExpect(status().isOk()) // anche con le virgolette
                .andExpect(jsonPath("$.status").value("CONFIRMED")).andExpect(jsonPath("$.rowVersion").value(2));
    }

    @Test
    void una_versione_non_attuale_risponde_409_optimistic_lock_conflict() throws Exception {
        int id = nuovo().get("quoteId").asInt();
        transition(id, "send", 0).andExpect(status().isOk());

        transition(id, "confirm", 0)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("OPTIMISTIC_LOCK_CONFLICT"));
    }

    @Test
    void un_passaggio_non_permesso_risponde_409_invalid_state_transition() throws Exception {
        int id = nuovo().get("quoteId").asInt();

        transition(id, "confirm", 0) // dalla bozza non si conferma
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("INVALID_STATE_TRANSITION"));
        transition(id, "send", 0).andExpect(status().isOk());
        transition(id, "send", 1) // gia' inviato
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("INVALID_STATE_TRANSITION"));
    }

    @Test
    void if_match_mancante_o_non_numerico_risponde_400_e_un_id_inesistente_404() throws Exception {
        int id = nuovo().get("quoteId").asInt();

        transition(id, "send", null).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
        transition(id, "send", "abc").andExpect(status().isBadRequest());
        transition(999999, "send", 0).andExpect(status().isNotFound());
    }

    @Test
    void un_preventivo_scaduto_non_si_conferma() throws Exception {
        int id = nuovo().get("quoteId").asInt();
        transition(id, "send", 0).andExpect(status().isOk());
        Fixtures.owner().update("UPDATE core.quote SET valid_until = CURRENT_DATE - 1 WHERE quote_id = ?", id);

        transition(id, "confirm", 1)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_EXPIRED"));
    }
}
```

- [ ] **Step 2: Esegui e verifica che fallisca**

```bash
cd backend
./mvnw -q -Dtest=QuoteTransitionsApiTest test
```

Atteso: i test falliscono con `404` o `405` (gli endpoint non esistono).

- [ ] **Step 3: Scrivi il codice**

In `QuoteService.java` aggiungi (accanto a `get`):

```java
    private record QuoteState(String status, int rowVersion, boolean expired) {}

    /** DRAFT -> SENT (send) e SENT -> CONFIRMED (confirm), con controllo della versione (If-Match). */
    public Quote transition(int quoteId, String ifMatch, String from, String to) {
        int expected = parseIfMatch(ifMatch);
        return db.write(jdbc -> {
            QuoteState s = jdbc.sql("""
                            SELECT status, row_version, (valid_until IS NOT NULL AND valid_until < CURRENT_DATE) AS expired
                              FROM core.quote WHERE quote_id = :id FOR UPDATE""")
                    .param("id", quoteId)
                    .query((rs, n) -> new QuoteState(rs.getString(1), rs.getInt(2), rs.getBoolean(3)))
                    .optional()
                    .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Preventivo non trovato"));
            if (s.rowVersion() != expected) {
                throw ApiException.conflict("OPTIMISTIC_LOCK_CONFLICT", "Il preventivo e' stato modificato nel frattempo");
            }
            if (!from.equals(s.status())) {
                throw ApiException.conflict("INVALID_STATE_TRANSITION",
                        "Passaggio non permesso dallo stato " + s.status());
            }
            if ("CONFIRMED".equals(to) && s.expired()) {
                throw ApiException.conflict("QUOTE_EXPIRED", "Preventivo scaduto");
            }
            jdbc.sql("UPDATE core.quote SET status = :to, row_version = row_version + 1 WHERE quote_id = :id")
                    .param("to", to).param("id", quoteId).update();
            return quotes.find(jdbc, quoteId).orElseThrow();
        });
    }

    private static int parseIfMatch(String value) {
        if (value == null || value.isBlank()) {
            throw ApiException.badRequest("VALIDATION_ERROR", "Intestazione If-Match obbligatoria (rowVersion)");
        }
        try {
            return Integer.parseInt(value.trim().replace("\"", ""));
        } catch (NumberFormatException e) {
            throw ApiException.badRequest("VALIDATION_ERROR", "If-Match deve essere un numero (rowVersion)");
        }
    }
```

In `QuoteController.java` aggiungi:

```java
    @PostMapping("/quotes/{quoteId}/send")
    public Quote send(@PathVariable int quoteId,
                      @RequestHeader(name = "If-Match", required = false) String ifMatch) {
        return quotes.transition(quoteId, ifMatch, "DRAFT", "SENT");
    }

    @PostMapping("/quotes/{quoteId}/confirm")
    public Quote confirm(@PathVariable int quoteId,
                         @RequestHeader(name = "If-Match", required = false) String ifMatch) {
        return quotes.transition(quoteId, ifMatch, "SENT", "CONFIRMED");
    }
```

- [ ] **Step 4: Esegui i test e la suite, poi commit**

```bash
./mvnw -q -Dtest=QuoteTransitionsApiTest test
./mvnw -q test
cd ..
git add backend
git commit -m "B3a: invio e conferma del preventivo con controllo della versione"
```

Atteso: `Tests run: 5` per la classe e suite verde.

---

## Task 7: Conversione in contratto e lettura del contratto

**Deliverable:** `POST /quotes/{id}/contract` crea il contratto in una transazione (stand, righe, sponsorizzazioni, acconto e saldo); `GET /contracts/{id}` lo legge.

**Files:**
- Create: `commercial/ContractRepository.java`, `commercial/ContractService.java`, `commercial/ContractController.java`
- Test: `backend/src/test/java/it/arcade/backend/commercial/ConvertApiTest.java`

**Interfaces:**
- Consumes: `StandReservation.lock/assertOwnedBy`, `IdempotencyService.run`, `NumberGenerator.next`, `QuoteRepository.find`, `ContractProperties` (Task 5), `ApiException.unprocessable/conflict`.
- Produces: `ContractRepository.find(JdbcClient, int contractId)` → `Optional<Contract>`; `ContractService.convert(String principal, String key, int quoteId, ContractFromQuote req)` → `Result`; `ContractService.get(int contractId, DbRole role)` → `Contract`.

- [ ] **Step 1: Aggiungi gli aiuti alla base dei test**

In `support/CommercialApiTest.java` aggiungi (con gli `import` che servono):

```java
    protected ResultActions confirmedQuoteAction(int quoteId) throws Exception {
        mvc.perform(post("/quotes/" + quoteId + "/send").header(HttpHeaders.AUTHORIZATION, staff()).header("If-Match", 0))
                .andExpect(status().isOk());
        return mvc.perform(post("/quotes/" + quoteId + "/confirm").header(HttpHeaders.AUTHORIZATION, staff()).header("If-Match", 1));
    }

    /** Crea, invia e conferma un preventivo; restituisce il preventivo creato. */
    protected JsonNode confirmedQuote(int year, int exhibitorId, double discount, List<Map<String, Object>> lines)
            throws Exception {
        JsonNode q = createdQuote(year, exhibitorId, discount, lines);
        confirmedQuoteAction(q.get("quoteId").asInt()).andExpect(status().isOk());
        return q;
    }

    protected ResultActions convert(int quoteId, String key, String signedOn) throws Exception {
        return mvc.perform(post("/quotes/" + quoteId + "/contract")
                .header(HttpHeaders.AUTHORIZATION, staff()).header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("signedOn", signedOn, "isRenewal", false))));
    }
```

- [ ] **Step 2: Scrivi il test che fallisce**

`backend/src/test/java/it/arcade/backend/commercial/ConvertApiTest.java`:

```java
package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.security.Role;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class ConvertApiTest extends CommercialApiTest {

    private JsonNode preventivoConfermato(int stand) throws Exception {
        return confirmedQuote(YEAR, espositore(), 0.1, List.of(spaceLine(YEAR, stand), extraLine(YEAR, 2)));
    }

    @Test
    void il_percorso_completo_crea_il_contratto_con_acconto_e_saldo() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "ANGOLO");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();

        JsonNode c = read(convert(quoteId, key(), "2098-06-01").andExpect(status().isCreated()));

        assertThat(c.get("contractNumber").asText()).matches("C2098-\\d{4}");
        assertThat(c.get("status").asText()).isEqualTo("SIGNED");
        assertThat(c.get("quoteId").asInt()).isEqualTo(quoteId);
        assertThat(c.get("netAmount").decimalValue()).isEqualByComparingTo("1080.00");
        assertThat(c.get("stands")).hasSize(1);
        assertThat(c.get("lines")).hasSize(3);
        JsonNode pay = c.get("payments");
        assertThat(pay).hasSize(2);
        assertThat(pay.get(0).get("kind").asText()).isEqualTo("DEPOSIT");
        assertThat(pay.get(0).get("dueAmount").decimalValue()).isEqualByComparingTo("324.00");   // 30 % di 1080
        assertThat(pay.get(0).get("dueOn").asText()).isEqualTo("2098-06-16");                    // firma + 15 giorni
        assertThat(pay.get(0).get("dueAmountBasis").asText()).isEqualTo("RULE_DERIVED");
        assertThat(pay.get(1).get("kind").asText()).isEqualTo("BALANCE");
        assertThat(pay.get(1).get("dueAmount").decimalValue()).isEqualByComparingTo("756.00");
        assertThat(pay.get(1).get("dueOn").asText()).isEqualTo("2098-11-18");                    // 18/12 - 30 giorni

        assertThat(Fixtures.owner().queryForMap("SELECT commercial_status, reserved_by_quote_id "
                + "FROM core.stand_edition WHERE stand_edition_id = ?", stand))
                .containsEntry("commercial_status", "SOLD").containsEntry("reserved_by_quote_id", null);
        assertThat(Fixtures.owner().queryForObject("SELECT status FROM core.quote WHERE quote_id = ?", String.class, quoteId))
                .isEqualTo("CONVERTED");
    }

    @Test
    void il_contratto_si_legge_e_serve_il_ruolo_giusto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        JsonNode c = read(convert(preventivoConfermato(stand).get("quoteId").asInt(), key(), "2098-06-01")
                .andExpect(status().isCreated()));
        int id = c.get("contractId").asInt();

        mvc.perform(get("/contracts/" + id).header(HttpHeaders.AUTHORIZATION, bearer(null, Role.OPS)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.contractNumber").value(c.get("contractNumber").asText()));
        mvc.perform(get("/contracts/" + id).header(HttpHeaders.AUTHORIZATION, bearer(espositore(), Role.EXHIBITOR)))
                .andExpect(status().isForbidden());
        mvc.perform(get("/contracts/999999").header(HttpHeaders.AUTHORIZATION, staff())).andExpect(status().isNotFound());
    }

    @Test
    void la_sponsorizzazione_crea_la_riga_di_tracciamento() throws Exception {
        Map<String, Object> sponsor = Map.of("priceItemId", Fixtures.priceItem(YEAR, "SPN-GOLD"), "quantity", 1);
        JsonNode q = confirmedQuote(YEAR, exhibitorId("ESP902"), 0, List.of(sponsor));

        JsonNode c = read(convert(q.get("quoteId").asInt(), key(), "2098-06-01").andExpect(status().isCreated()));

        assertThat(Fixtures.owner().queryForObject("""
                SELECT count(*) FROM core.sponsorship s JOIN core.contract_line l ON l.contract_line_id = s.contract_line_id
                 WHERE l.contract_id = ?""", Integer.class, c.get("contractId").asInt())).isEqualTo(1);
    }

    @Test
    void un_preventivo_non_confermato_risponde_409_quote_not_confirmed() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int id = createdQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))).get("quoteId").asInt();

        convert(id, key(), "2098-06-01")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_NOT_CONFIRMED"));
    }

    @Test
    void la_data_di_firma_e_obbligatoria() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int id = preventivoConfermato(stand).get("quoteId").asInt();

        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/quotes/" + id + "/contract")
                        .header(HttpHeaders.AUTHORIZATION, staff()).header("Idempotency-Key", key())
                        .contentType(org.springframework.http.MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.errors[0].field").value("signedOn"));
    }

    @Test
    void la_ripetizione_con_la_stessa_chiave_non_duplica_il_contratto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();
        String k = key();

        JsonNode first = read(convert(quoteId, k, "2098-06-01").andExpect(status().isCreated()));
        JsonNode second = read(convert(quoteId, k, "2098-06-01").andExpect(status().isCreated())
                .andExpect(header().string("Idempotent-Replayed", "true")));

        assertThat(second).isEqualTo(first);
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteId))
                .isEqualTo(1);
        convert(quoteId, key(), "2098-06-01") // chiave nuova dopo la conversione
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_NOT_CONFIRMED"));
    }

    @Test
    void se_manca_la_riserva_perche_un_altro_preventivo_ha_ripreso_lo_stand_risponde_409_e_non_cambia_nulla() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteA = preventivoConfermato(stand).get("quoteId").asInt();
        Fixtures.owner().update("UPDATE core.stand_edition SET reserved_until = now() - interval '1 hour' "
                + "WHERE stand_edition_id = ?", stand);
        createdQuote(YEAR, exhibitorId("ESP902"), 0, List.of(spaceLine(YEAR, stand))); // B riprende lo stand

        convert(quoteA, key(), "2098-06-01")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("STAND_ALREADY_RESERVED"));

        assertThat(Fixtures.owner().queryForObject("SELECT status FROM core.quote WHERE quote_id = ?", String.class, quoteA))
                .isEqualTo("CONFIRMED");
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteA))
                .isZero();
    }

    @Test
    void edizione_senza_date_risponde_422_e_non_lascia_nulla() throws Exception {
        int stand = Fixtures.newStand(2099, "P1", "10.00", "LINEA");
        int quoteId = confirmedQuote(2099, espositore(), 0, List.of(spaceLine(2099, stand))).get("quoteId").asInt();

        convert(quoteId, key(), "2099-06-01")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("EDITION_DATES_MISSING"));

        assertThat(Fixtures.owner().queryForObject("SELECT status FROM core.quote WHERE quote_id = ?", String.class, quoteId))
                .isEqualTo("CONFIRMED");
        assertThat(Fixtures.owner().queryForObject(
                "SELECT commercial_status FROM core.stand_edition WHERE stand_edition_id = ?", String.class, stand))
                .isEqualTo("RESERVED");
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteId))
                .isZero();
    }

    @Test
    void condizioni_di_pagamento_mancanti_nel_listino_rispondono_422() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();
        int edition = Fixtures.edition(YEAR);
        Fixtures.owner().update("UPDATE core.price_list SET deposit_pct = NULL WHERE edition_id = ?", edition);
        try {
            convert(quoteId, key(), "2098-06-01")
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.code").value("PRICE_LIST_CONDITIONS_MISSING"));
        } finally {
            Fixtures.owner().update("UPDATE core.price_list SET deposit_pct = 0.3000 WHERE edition_id = ?", edition);
        }
    }

    @Test
    void l_acconto_non_scade_dopo_il_saldo() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();

        JsonNode c = read(convert(quoteId, key(), "2098-11-10").andExpect(status().isCreated())); // saldo il 18/11

        assertThat(c.get("payments").get(0).get("dueOn").asText()).isEqualTo("2098-11-18"); // non 25/11
    }
}
```

- [ ] **Step 3: Esegui e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest=ConvertApiTest test
```

Atteso: i test falliscono con `404`/`405`.

- [ ] **Step 4: Scrivi `ContractRepository`**

`commercial/ContractRepository.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.dto.Contract;
import it.arcade.backend.commercial.dto.ContractStandRef;
import it.arcade.backend.commercial.dto.DocumentLine;
import it.arcade.backend.commercial.dto.Payment;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class ContractRepository {

    public Optional<Contract> find(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT contract_id, contract_number, edition_id, exhibitor_id, quote_id, status, signed_on,
                               list_amount, discount_pct, net_amount, is_renewal, row_version
                          FROM core.contract WHERE contract_id = :id""")
                .param("id", contractId)
                .query((rs, n) -> new Contract(rs.getInt("contract_id"), rs.getString("contract_number"),
                        rs.getInt("edition_id"), rs.getInt("exhibitor_id"), rs.getObject("quote_id", Integer.class),
                        rs.getString("status"), rs.getObject("signed_on", LocalDate.class),
                        rs.getBigDecimal("list_amount"), rs.getBigDecimal("discount_pct"),
                        rs.getBigDecimal("net_amount"), rs.getBoolean("is_renewal"), rs.getInt("row_version"),
                        stands(jdbc, contractId), lines(jdbc, contractId), payments(jdbc, contractId)))
                .optional();
    }

    private List<ContractStandRef> stands(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT cs.stand_edition_id, s.stand_code, s.sqm
                          FROM core.contract_stand cs
                          JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
                          JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE cs.contract_id = :id AND cs.released_at IS NULL ORDER BY s.stand_code""")
                .param("id", contractId)
                .query((rs, n) -> new ContractStandRef(rs.getInt(1), rs.getString(2), rs.getBigDecimal(3)))
                .list();
    }

    private List<DocumentLine> lines(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT l.line_no, l.line_type, l.price_item_id, cs.stand_edition_id, s.stand_code,
                               l.description, l.quantity, l.unit_price, l.amount
                          FROM core.contract_line l
                          LEFT JOIN core.contract_stand cs ON cs.contract_stand_id = l.contract_stand_id
                          LEFT JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
                          LEFT JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE l.contract_id = :id ORDER BY l.line_no""")
                .param("id", contractId)
                .query((rs, n) -> new DocumentLine(rs.getInt("line_no"), rs.getString("line_type"),
                        rs.getInt("price_item_id"), rs.getObject("stand_edition_id", Integer.class),
                        rs.getString("stand_code"), rs.getString("description"), rs.getBigDecimal("quantity"),
                        rs.getBigDecimal("unit_price"), rs.getBigDecimal("amount")))
                .list();
    }

    private List<Payment> payments(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT payment_id, contract_id, kind, due_on, due_amount, due_amount_basis, paid_on,
                               paid_amount, paid_amount_is_assumed
                          FROM core.payment WHERE contract_id = :id ORDER BY due_on, payment_id""")
                .param("id", contractId)
                .query((rs, n) -> {
                    LocalDate dueOn = rs.getObject("due_on", LocalDate.class);
                    LocalDate paidOn = rs.getObject("paid_on", LocalDate.class);
                    String state = paidOn != null ? (paidOn.isAfter(dueOn) ? "PAID_LATE" : "PAID")
                            : (LocalDate.now().isAfter(dueOn) ? "OVERDUE" : "DUE");
                    return new Payment(rs.getInt("payment_id"), rs.getInt("contract_id"), rs.getString("kind"),
                            dueOn, rs.getBigDecimal("due_amount"), rs.getString("due_amount_basis"), paidOn,
                            rs.getBigDecimal("paid_amount"), rs.getBoolean("paid_amount_is_assumed"), state);
                })
                .list();
    }
}
```

- [ ] **Step 5: Scrivi `ContractService` e `ContractController`**

`commercial/ContractService.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.IdempotencyService.Created;
import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.commercial.StandReservation.LockedStand;
import it.arcade.backend.commercial.dto.Contract;
import it.arcade.backend.commercial.dto.ContractFromQuote;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.error.ValidationErrors;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class ContractService {

    private record QuoteHead(int editionId, int exhibitorId, String status, BigDecimal discountPct,
                             BigDecimal listAmount, BigDecimal netAmount, boolean expired) {}

    private record QuoteLineRow(int lineNo, String lineType, int priceItemId, String itemCode,
                                Integer standEditionId, String description, BigDecimal quantity,
                                BigDecimal unitPrice, BigDecimal amount) {}

    private final ScopedDb db;
    private final IdempotencyService idempotency;
    private final NumberGenerator numbers;
    private final StandReservation stands;
    private final ContractRepository contracts;
    private final ContractProperties properties;

    public ContractService(ScopedDb db, IdempotencyService idempotency, NumberGenerator numbers,
                           StandReservation stands, ContractRepository contracts, ContractProperties properties) {
        this.db = db;
        this.idempotency = idempotency;
        this.numbers = numbers;
        this.stands = stands;
        this.contracts = contracts;
        this.properties = properties;
    }

    public Contract get(int contractId, DbRole role) {
        return db.read(role, null, jdbc -> contracts.find(jdbc, contractId))
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Contratto non trovato"));
    }

    public Result convert(String principal, String key, int quoteId, ContractFromQuote req) {
        ValidationErrors v = new ValidationErrors();
        if (req == null || req.signedOn() == null) {
            v.add("signedOn", "obbligatorio");
        }
        v.throwIfAny();
        return idempotency.run(principal, "convertQuoteToContract", key, List.of("convertQuote", quoteId, req),
                jdbc -> new Created(201, doConvert(jdbc, quoteId, req)));
    }

    private Contract doConvert(JdbcClient jdbc, int quoteId, ContractFromQuote req) {
        QuoteHead q = jdbc.sql("""
                        SELECT edition_id, exhibitor_id, status, discount_pct, list_amount, net_amount,
                               (valid_until IS NOT NULL AND valid_until < CURRENT_DATE) AS expired
                          FROM core.quote WHERE quote_id = :id FOR UPDATE""")
                .param("id", quoteId)
                .query((rs, n) -> new QuoteHead(rs.getInt(1), rs.getInt(2), rs.getString(3), rs.getBigDecimal(4),
                        rs.getBigDecimal(5), rs.getBigDecimal(6), rs.getBoolean(7)))
                .optional()
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Preventivo non trovato"));
        if (!"CONFIRMED".equals(q.status())) {
            throw ApiException.conflict("QUOTE_NOT_CONFIRMED", "Il preventivo non e' confermato");
        }
        if (q.expired()) {
            throw ApiException.conflict("QUOTE_EXPIRED", "Preventivo scaduto");
        }

        List<Integer> standIds = jdbc.sql("""
                        SELECT DISTINCT stand_edition_id FROM core.quote_line
                         WHERE quote_id = :id AND stand_edition_id IS NOT NULL ORDER BY 1""")
                .param("id", quoteId).query(Integer.class).list();
        List<LockedStand> locked = stands.lock(jdbc, standIds);
        stands.assertOwnedBy(locked, quoteId);

        // Piano di pagamento: tutte le condizioni si controllano PRIMA di scrivere qualsiasi cosa.
        Object[] cond = jdbc.sql("SELECT deposit_pct, balance_days_before FROM core.price_list WHERE edition_id = :e")
                .param("e", q.editionId())
                .query((rs, n) -> new Object[] {rs.getBigDecimal(1), rs.getObject(2, Integer.class)})
                .optional().orElse(null);
        if (cond == null || cond[0] == null || cond[1] == null) {
            throw ApiException.unprocessable("PRICE_LIST_CONDITIONS_MISSING",
                    "Il listino non indica la percentuale d'acconto o i giorni del saldo");
        }
        LocalDate firstDay = jdbc.sql("SELECT min(day_date) FROM core.edition_day WHERE edition_id = :e")
                .param("e", q.editionId()).query(LocalDate.class).optional().orElse(null);
        if (firstDay == null) {
            throw ApiException.unprocessable("EDITION_DATES_MISSING",
                    "L'edizione non ha giorni di apertura: la scadenza del saldo non si puo' calcolare");
        }
        LocalDate balanceDue = firstDay.minusDays((Integer) cond[1]);
        LocalDate depositDue = req.signedOn().plusDays(properties.depositDueDays());
        if (depositDue.isAfter(balanceDue)) {
            depositDue = balanceDue; // l'acconto non scade dopo il saldo
        }
        BigDecimal deposit = q.netAmount().multiply((BigDecimal) cond[0]).setScale(2, RoundingMode.HALF_UP);
        BigDecimal balance = q.netAmount().subtract(deposit);

        int year = jdbc.sql("SELECT year FROM core.edition WHERE edition_id = :e").param("e", q.editionId())
                .query(Integer.class).single();
        String number = numbers.next(jdbc, "C", year, "core.contract", "contract_number");
        boolean renewal = Boolean.TRUE.equals(req.isRenewal());
        int contractId = jdbc.sql("""
                        INSERT INTO core.contract (contract_number, edition_id, exhibitor_id, quote_id, status, signed_on,
                                                   list_amount, discount_pct, net_amount, is_renewal)
                        VALUES (:num, :ed, :ex, :q, 'SIGNED', :signed, :l, :d, :n, :ren) RETURNING contract_id""")
                .param("num", number).param("ed", q.editionId()).param("ex", q.exhibitorId()).param("q", quoteId)
                .param("signed", req.signedOn()).param("l", q.listAmount()).param("d", q.discountPct())
                .param("n", q.netAmount()).param("ren", renewal).query(Integer.class).single();

        Map<Integer, Integer> contractStandByStandEdition = new HashMap<>();
        for (int standEditionId : standIds) {
            try {
                int csId = jdbc.sql("""
                                INSERT INTO core.contract_stand (contract_id, stand_edition_id, edition_id)
                                VALUES (:c, :se, :ed) RETURNING contract_stand_id""")
                        .param("c", contractId).param("se", standEditionId).param("ed", q.editionId())
                        .query(Integer.class).single();
                contractStandByStandEdition.put(standEditionId, csId);
            } catch (DuplicateKeyException e) {
                // Ultima difesa: l'indice univoco impedisce due contratti attivi sullo stesso stand.
                throw ApiException.conflict("STAND_ALREADY_SOLD", "Stand gia' assegnato a un contratto");
            }
        }

        List<QuoteLineRow> lines = jdbc.sql("""
                        SELECT l.line_no, i.item_type, l.price_item_id, i.code, l.stand_edition_id, l.description,
                               l.quantity, l.unit_price, l.amount
                          FROM core.quote_line l JOIN core.price_item i ON i.price_item_id = l.price_item_id
                         WHERE l.quote_id = :id ORDER BY l.line_no""")
                .param("id", quoteId)
                .query((rs, n) -> new QuoteLineRow(rs.getInt(1), rs.getString(2), rs.getInt(3), rs.getString(4),
                        rs.getObject(5, Integer.class), rs.getString(6), rs.getBigDecimal(7), rs.getBigDecimal(8),
                        rs.getBigDecimal(9)))
                .list();
        for (QuoteLineRow l : lines) {
            Integer csId = l.standEditionId() == null ? null : contractStandByStandEdition.get(l.standEditionId());
            jdbc.sql("""
                            INSERT INTO core.contract_line (contract_id, line_no, line_type, price_item_id,
                                   source_item_code, description, quantity, unit_price, amount, contract_stand_id)
                            VALUES (:c, :n, :t, :pi, :code, :desc, :qty, :up, :amt, :cs)""")
                    .param("c", contractId).param("n", l.lineNo()).param("t", l.lineType())
                    .param("pi", l.priceItemId()).param("code", l.itemCode()).param("desc", l.description())
                    .param("qty", l.quantity()).param("up", l.unitPrice()).param("amt", l.amount())
                    .param("cs", csId).update();
        }
        jdbc.sql("""
                        INSERT INTO core.sponsorship (contract_line_id)
                        SELECT contract_line_id FROM core.contract_line
                         WHERE contract_id = :c AND line_type = 'SPONSORSHIP'""")
                .param("c", contractId).update();

        insertPayment(jdbc, contractId, "DEPOSIT", depositDue, deposit);
        insertPayment(jdbc, contractId, "BALANCE", balanceDue, balance);

        if (!standIds.isEmpty()) {
            jdbc.sql("""
                            UPDATE core.stand_edition
                               SET commercial_status = 'SOLD', reserved_until = NULL, reserved_by_quote_id = NULL,
                                   row_version = row_version + 1
                             WHERE stand_edition_id IN (:ids)""")
                    .param("ids", standIds).update();
        }
        jdbc.sql("UPDATE core.quote SET status = 'CONVERTED', row_version = row_version + 1 WHERE quote_id = :id")
                .param("id", quoteId).update();
        return contracts.find(jdbc, contractId).orElseThrow();
    }

    private void insertPayment(JdbcClient jdbc, int contractId, String kind, LocalDate dueOn, BigDecimal amount) {
        jdbc.sql("""
                        INSERT INTO core.payment (contract_id, kind, due_on, due_amount, due_amount_basis)
                        VALUES (:c, :k, :d, :a, 'RULE_DERIVED')""")
                .param("c", contractId).param("k", kind).param("d", dueOn).param("a", amount).update();
    }
}
```

`commercial/ContractController.java`:

```java
package it.arcade.backend.commercial;

import it.arcade.backend.commercial.dto.Contract;
import it.arcade.backend.commercial.dto.ContractFromQuote;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.security.CurrentUser;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ContractController {

    private final ContractService contracts;

    public ContractController(ContractService contracts) {
        this.contracts = contracts;
    }

    @PostMapping("/quotes/{quoteId}/contract")
    public ResponseEntity<String> convert(@AuthenticationPrincipal Jwt jwt, @PathVariable int quoteId,
                                          @RequestHeader(name = "Idempotency-Key", required = false) String key,
                                          @RequestBody ContractFromQuote body) {
        return QuoteController.toResponse(contracts.convert(jwt.getSubject(), key, quoteId, body));
    }

    @GetMapping("/contracts/{contractId}")
    public Contract get(@AuthenticationPrincipal Jwt jwt, @PathVariable int contractId) {
        return contracts.get(contractId, DbRole.forUser(CurrentUser.from(jwt)));
    }
}
```

- [ ] **Step 6: Esegui i test e la suite, poi commit**

```bash
./mvnw -q -Dtest=ConvertApiTest test
./mvnw -q test
cd ..
git add backend
git commit -m "B3a: conversione del preventivo in contratto e lettura del contratto"
```

Atteso: `Tests run: 10` per `ConvertApiTest` e suite verde. Se `l_acconto_non_scade_dopo_il_saldo` fallisce, controlla il confronto `depositDue.isAfter(balanceDue)`.

---

## Task 8: Prove di concorrenza, documentazione e chiusura

**Deliverable:** i test in parallelo dimostrano che non ci sono doppie vendite, stalli, duplicati né numeri uguali; la documentazione descrive i codici nuovi e le assunzioni.

**Files:**
- Test: `backend/src/test/java/it/arcade/backend/commercial/ConcurrencyApiTest.java`
- Modify: `docs/api/README.md`, `backend/README.md`, `docs/08-decisioni-condivise.md`, `docs/superpowers/specs/2026-11-16-b3a-contratto-venduto-design.md`

- [ ] **Step 1: Scrivi i test di concorrenza**

`backend/src/test/java/it/arcade/backend/commercial/ConcurrencyApiTest.java`:

```java
package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.function.IntFunction;
import org.junit.jupiter.api.Test;

/** Richieste in parallelo sul pool di connessioni predefinito (piu' di una): provano i blocchi veri del database. */
class ConcurrencyApiTest extends CommercialApiTest {

    private record Reply(int status, JsonNode body) {}

    private List<Reply> inParallelo(int n, IntFunction<Callable<Reply>> factory) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(n);
        CountDownLatch via = new CountDownLatch(1);
        List<Future<Reply>> futures = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Callable<Reply> task = factory.apply(i);
            futures.add(pool.submit(() -> { via.await(); return task.call(); }));
        }
        via.countDown();
        List<Reply> out = new ArrayList<>();
        for (Future<Reply> f : futures) {
            out.add(f.get());
        }
        pool.shutdown();
        return out;
    }

    private Reply creaPreventivo(String key, Map<String, Object> body) throws Exception {
        var res = postQuote(key, body).andReturn().getResponse();
        return new Reply(res.getStatus(), json.readTree(res.getContentAsString()));
    }

    private long conStato(List<Reply> replies, int status) {
        return replies.stream().filter(r -> r.status() == status).count();
    }

    @Test
    void molti_preventivi_sullo_stesso_stand_ne_hanno_uno_solo_che_vince() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> body = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));

        List<Reply> r = inParallelo(8, i -> () -> creaPreventivo(key(), body));

        assertThat(conStato(r, 201)).isEqualTo(1);
        assertThat(conStato(r, 409)).isEqualTo(7);
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void stand_in_ordine_opposto_non_vanno_in_stallo() throws Exception {
        int s1 = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int s2 = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> ab = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, s1), spaceLine(YEAR, s2)));
        Map<String, Object> ba = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, s2), spaceLine(YEAR, s1)));

        List<Reply> r = inParallelo(8, i -> () -> creaPreventivo(key(), i % 2 == 0 ? ab : ba));

        assertThat(conStato(r, 201)).isEqualTo(1);
        assertThat(conStato(r, 409)).isEqualTo(7); // nessun 500: nessuno stallo
    }

    @Test
    void la_stessa_chiave_in_parallelo_ha_un_solo_effetto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> body = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));
        String k = key();

        List<Reply> r = inParallelo(6, i -> () -> creaPreventivo(k, body));

        assertThat(conStato(r, 201)).isEqualTo(6);
        assertThat(r.stream().map(x -> x.body().get("quoteId").asInt()).distinct()).hasSize(1);
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void i_numeri_dei_preventivi_creati_in_parallelo_sono_distinti() throws Exception {
        List<Integer> stand = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            stand.add(Fixtures.newStand(YEAR, "P1", "10.00", "LINEA"));
        }

        List<Reply> r = inParallelo(6, i -> () -> creaPreventivo(key(),
                quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand.get(i))))));

        assertThat(conStato(r, 201)).isEqualTo(6);
        assertThat(r.stream().map(x -> x.body().get("quoteNumber").asText()).distinct()).hasSize(6);
    }

    @Test
    void conversioni_concorrenti_con_chiavi_diverse_creano_un_solo_contratto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = confirmedQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))).get("quoteId").asInt();

        List<Reply> r = inParallelo(6, i -> () -> {
            var res = convert(quoteId, key(), "2098-06-01").andReturn().getResponse();
            return new Reply(res.getStatus(), json.readTree(res.getContentAsString()));
        });

        assertThat(conStato(r, 201)).isEqualTo(1);
        assertThat(conStato(r, 409)).isEqualTo(5);
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteId))
                .isEqualTo(1);
    }
}
```

- [ ] **Step 2: Esegui i test di concorrenza**

```bash
cd backend
./mvnw -q -Dtest=ConcurrencyApiTest test
```

Atteso: `Tests run: 5, Failures: 0, Errors: 0`. Se `stand_in_ordine_opposto_non_vanno_in_stallo` mostra un `500`, il blocco in ordine di id non viene rispettato (controlla `StandReservation.lock` e l'ordine in `QuoteService.doCreate`). Se `la_stessa_chiave_in_parallelo_ha_un_solo_effetto` dà `409 DUPLICATE_REQUEST`, controlla che `IdempotencyService` inserisca la chiave **prima** di eseguire l'operazione, nella stessa transazione.

- [ ] **Step 3: Aggiorna la documentazione**

- `docs/api/README.md`, tabella "Codici di errore stabili": aggiungi le righe `EDITION_DATES_MISSING` (422, "L'edizione non ha giorni di apertura: la scadenza del saldo non si calcola"), `PRICE_LIST_CONDITIONS_MISSING` (422, "Il listino non indica acconto o giorni del saldo"), `INVALID_STATE_TRANSITION` (409, "Passaggio di stato non permesso"), `STAND_NOT_SELLABLE` (422, "Stand libero o non commercializzabile"). Aggiungi sotto la tabella: "Aggiunti il 2026-11-16 con B3a: modifica compatibile, da comunicare al BAD".
- `docs/08-decisioni-condivise.md`: aggiungi la voce **B3a — preventivi e contratti via API** con data, i quattro codici nuovi, le assunzioni (riserva 14 giorni, acconto 15 giorni dopo la firma, edizione `SALES_OPEN`, listino `PUBLISHED`), e "Da comunicare al BAD e a Michele (Angular): codici nuovi e comportamento di `If-Match` e `Idempotency-Key`".
- `backend/README.md`: aggiungi la sezione "Preventivi e contratti" con gli endpoint, le due proprietà (`arcade.quote.reservation-days`, `arcade.contract.deposit-due-days`), un esempio di percorso con `curl` e la regola "le migrazioni dopo V5 devono essere ripetibili"; nei limiti noti: listino e date 2026 reali non esistono nel database, provato solo con dati di test.
- Specifica: cambia `**Stato:** da approvare` in `**Stato:** implementata`; nella §9 sostituisci `response_body` (jsonb) con `response_body` (testo, per restituire la risposta identica byte per byte).

- [ ] **Step 4: Suite completa e commit**

```bash
./mvnw -q test
cd ..
git add backend docs
git commit -m "B3a: prove di concorrenza e documentazione"
```

Atteso: suite verde (31 di B2 + i test di B3a).

---

## Autocontrollo del piano

**Copertura della specifica**

| Sezione | Task |
|---|---|
| §3 endpoint | 5 (crea, leggi), 6 (invia, conferma), 7 (converti, contratto) |
| §4 prezzi | 3 |
| §5 riserva e concorrenza | 5 (`StandReservation`), 7 (conversione), 8 (test in parallelo) |
| §6 stati | 6 |
| §7 conversione | 7 |
| §8 assunzioni | 5 (proprietà), 7 (acconto/saldo), 8 (documentazione) |
| §9 idempotenza | 1 (V6), 4, 5, 7 |
| §10 struttura | tutti; `ScopedDb.write` nel 2 |
| §11 test | 3, 4, 5, 6, 7, 8 |
| §12 rischi | documentati in `backend/README.md` (Task 8) |

**Differenze rispetto alla specifica (decise rileggendo il codice esistente)**
- La migrazione è **ripetibile** e la regola vale per tutte le migrazioni dopo V5: serve perché Docker e Flyway possono applicarla entrambi (problema segnalato dalla revisione di B2).
- `response_body` è `text`, non `jsonb`, per restituire la risposta identica.
- I codici di formato usano `VALIDATION_ERROR` (come da contratto) al posto di `INVALID_REQUEST` introdotto in B2: il Task 2 li allinea.
- I dati di prova usano le edizioni **2098** e **2099**, non la 2026 vera, così le prove non toccano le edizioni reali e non servono date inventate.

**Placeholder:** nessuno. **Coerenza dei tipi:** `ScopedDb.write`, `IdempotencyService.run/Created/Result`, `NumberGenerator.next`, `StandReservation.lock/reserve/assertOwnedBy`, `PricingCalculator.calculate` e i DTO sono definiti prima di essere usati.

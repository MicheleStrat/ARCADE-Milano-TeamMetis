# B2 — Scheletro del backend Spring Boot: piano di implementazione

> **Per chi esegue (agenti):** SOTTO-SKILL OBBLIGATORIA: usa `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans` per eseguire il piano task per task. I passaggi usano la sintassi con caselle (`- [ ]`) per tenere traccia dell'avanzamento.

**Obiettivo:** un backend in `backend/` che si avvia con `./mvnw spring-boot:run` contro il database locale `arcade-db`, verifica un JWT, applica ruoli e isolamento tra espositori, e risponde a `/health`, `/me`, `/editions`, `/portal/me`.

**Architettura:** Spring Boot come resource server JWT (chiave HMAC locale in sviluppo). Ogni richiesta che legge dal database passa da `ScopedDb`, che apre una transazione in sola lettura, fa `SET LOCAL ROLE` (`arcade_app` per lo staff, `arcade_portal` per l'espositore) e imposta `app.exhibitor_id`. Gli errori escono come `application/problem+json`. Flyway riusa `database/migrations`.

**Tecnologie:** Java 25, Maven (wrapper), Spring Boot 3.5.7, Spring Security (oauth2-resource-server), Spring JDBC (`JdbcClient`), Flyway 11, PostgreSQL 16, JUnit 5, MockMvc, Testcontainers 2.0.5.

**Specifica:** [docs/superpowers/specs/2026-11-13-b2-scheletro-backend-design.md](../specs/2026-11-13-b2-scheletro-backend-design.md)

## Vincoli globali

- Base URL `/api/v1` (`server.servlet.context-path`), come nel contratto `docs/api/openapi.yaml`.
- Ruoli del contratto: `ADMIN`, `COMMERCIAL`, `OPS`, `EXHIBITOR`, `SCANNER`, `BI_READER`. Staff = `ADMIN`, `COMMERCIAL`, `OPS` → ruolo database `arcade_app`; `EXHIBITOR` → `arcade_portal`.
- Nessun JPA: solo Spring JDBC (`JdbcClient`) con SQL scritto a mano e parametri bind.
- JWT firmato HS256; chiave da `JWT_DEV_SECRET` (almeno 32 caratteri), mai nel repository. Claim: `sub`, `roles`, `exhibitor_id` (solo espositore).
- `POST /dev/token` esiste solo con il profilo `dev`.
- Il backend si collega al database con l'account `arcade_backend` (`LOGIN NOINHERIT`, membro di `arcade_app` e `arcade_portal`), mai con il superutente. Flyway usa l'utente del database locale (`POSTGRES_USER`).
- Errori sempre `application/problem+json` con `code` stabile e `traceId`; mai dettagli interni in un `500`.
- Nessun segreto, password o dato personale nel repository né nei log.
- Messaggi di commit in italiano, senza `Co-Authored-By` e senza riferimenti a Claude.
- Se Spring Boot 3.5.7 o Java 25 non compilano, si scende a Java 21 (`java.version`) e si aggiorna la specifica (§11).

## Punti da controllare (rischi del piano)

| Rischio | Come si controlla |
|---|---|
| Testcontainers 1.x non si collega a Docker 29 (API minima 1.40) | Si usa la 2.0.5; il primo test con container lo conferma |
| In Testcontainers 2.x cambiano nome del modulo e del pacchetto (`testcontainers-postgresql`, `org.testcontainers.postgresql.PostgreSQLContainer`) | Il primo `./mvnw test` lo conferma; se il nome è diverso, si corregge solo `pom.xml` e `PostgresSupport` |
| Flyway su un database creato da Docker: lo schema `public` può sembrare vuoto e Flyway rieseguirebbe V1 | `baseline-on-migrate` non è affidabile qui; si usa `BaselineExistingSchemaStrategy` (Task 1) |
| Il seed di test inserisce righe in `core.exhibitor`: potrebbero esserci trigger non letti | Il test `PortalApiTest` fallisce subito se l'inserimento non va; si corregge `V900` |

## Verifiche richieste dalla revisione (Review Focus)

Casi che la specifica implica ma che non sono nel flusso principale, con il test che li fissa:

1. Token firmato con un'altra chiave → `401` (`MeApiTest`, Task 2).
2. Token scaduto → `401` (`MeApiTest`, Task 2).
3. Token con soli ruoli sconosciuti → `403` su `/editions` (`EditionsApiTest`, Task 3).
4. Token con `ADMIN` ed `EXHIBITOR` su `/portal/me` → vede solo il proprio profilo, non tutti (`PortalApiTest`, Task 3). Senza la scelta esplicita del ruolo `PORTAL` ritornerebbe tutte le righe.
5. Ruolo e `app.exhibitor_id` non restano sulla connessione tra una richiesta e l'altra, e `arcade_backend` senza `SET ROLE` non legge `core` (`ScopedDbTest`, Task 3).

## Struttura dei file

```
backend/
  pom.xml, mvnw, mvnw.cmd, .mvn/wrapper/maven-wrapper.properties
  README.md
  scripts/crea-ruolo-backend.sql
  src/main/java/it/arcade/backend/
    BackendApplication.java
    config/BaselineExistingSchemaStrategy.java
    config/SecurityConfig.java
    security/Role.java  CurrentUser.java  JwtProperties.java  JwtService.java  DevTokenController.java
    db/DbRole.java  ScopedDb.java
    error/ApiException.java  Problem.java  ProblemWriter.java  RestExceptionHandler.java  RequestIdFilter.java
    api/HealthController.java  MeController.java  EditionController.java  PortalController.java
  src/main/resources/application.yml
  src/test/resources/db/testdata/V900__test_backend_role_and_data.sql
  src/test/java/it/arcade/backend/
    support/PostgresSupport.java  ApiTest.java
    config/BaselineExistingSchemaStrategyTest.java
    api/HealthApiTest.java  MeApiTest.java  EditionsApiTest.java  PortalApiTest.java
    db/ScopedDbTest.java
    security/DevTokenApiTest.java  DevTokenDisabledApiTest.java
```

Responsabilità: `security/` produce l'utente corrente dal token e non conosce il database; `db/` è l'unico punto che fa `SET LOCAL ROLE`; `api/` interroga `db/` e restituisce i DTO; `error/` converte ogni errore in `problem+json`.

---

## Task 1: Progetto Maven, migrazioni con Flyway e database di prova

**Deliverable:** `./mvnw test` compila il progetto e prova due cose con un PostgreSQL in container: Flyway parte da zero (V1–V5 applicate) e su uno schema già esistente imposta solo il riferimento alla versione 5 senza rieseguire nulla.

**Files:**
- Create: `backend/pom.xml`, `backend/mvnw`, `backend/mvnw.cmd`, `backend/.mvn/wrapper/maven-wrapper.properties`
- Create: `backend/src/main/java/it/arcade/backend/BackendApplication.java`
- Create: `backend/src/main/java/it/arcade/backend/config/BaselineExistingSchemaStrategy.java`
- Create: `backend/src/main/resources/application.yml`
- Create: `backend/src/test/resources/db/testdata/V900__test_backend_role_and_data.sql`
- Create: `backend/src/test/java/it/arcade/backend/support/PostgresSupport.java`
- Create: `backend/src/test/java/it/arcade/backend/config/BaselineExistingSchemaStrategyTest.java`
- Modify: `.env.example`
- Modify: `docs/superpowers/specs/2026-11-13-b2-scheletro-backend-design.md` (§6)

**Interfaces:**
- Produces: `PostgresSupport.DB` (container avviato), `PostgresSupport.register(DynamicPropertyRegistry)`, `PostgresSupport.owner()` (`JdbcTemplate` come superutente del container); `BaselineExistingSchemaStrategy implements FlywayMigrationStrategy`.

- [ ] **Step 1: Crea il ramo e salva la documentazione già scritta**

Dalla radice del repository:

```bash
git fetch origin
git switch -c b2-backend-scheletro origin/BID
git add docs/08-decisioni-condivise.md docs/06-assegnazione-task-bid.md docs/superpowers
git commit -m "Decisione B1, specifica e piano del backend (B2)"
```

Se `docs/06-assegnazione-task-bid.md` non risulta modificato, `git add` lo ignora senza errori.

- [ ] **Step 2: Scarica il wrapper di Maven**

Maven non è installato. Il wrapper si prende da un progetto generato da Spring Initializr (serve solo per i file del wrapper, il `pom.xml` lo scriviamo noi):

```bash
mkdir -p backend
cd backend
curl -s https://start.spring.io/starter.zip -d type=maven-project -d bootVersion=4.1.2 -d dependencies=web -o /tmp/init.zip
tar -xf /tmp/init.zip mvnw mvnw.cmd .mvn
ls -a
```

Atteso: compaiono `mvnw`, `mvnw.cmd` e la cartella `.mvn`. Poi:

```bash
chmod +x mvnw
```

- [ ] **Step 3: Scrivi `backend/pom.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.5.7</version>
    <relativePath/>
  </parent>

  <groupId>it.arcade</groupId>
  <artifactId>backend</artifactId>
  <version>0.1.0-SNAPSHOT</version>
  <name>arcade-backend</name>
  <description>Backend ARCADE Milano (BID)</description>

  <properties>
    <java.version>25</java.version>
    <!-- Docker 29 richiede Testcontainers 2.x -->
    <testcontainers.version>2.0.5</testcontainers.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-security</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-jdbc</artifactId>
    </dependency>
    <dependency>
      <groupId>org.flywaydb</groupId>
      <artifactId>flyway-core</artifactId>
    </dependency>
    <dependency>
      <groupId>org.flywaydb</groupId>
      <artifactId>flyway-database-postgresql</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <scope>runtime</scope>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.testcontainers</groupId>
      <artifactId>testcontainers-postgresql</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
```

- [ ] **Step 4: Scrivi la classe principale e la configurazione**

`backend/src/main/java/it/arcade/backend/BackendApplication.java`:

```java
package it.arcade.backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class BackendApplication {
    public static void main(String[] args) {
        SpringApplication.run(BackendApplication.class, args);
    }
}
```

`backend/src/main/resources/application.yml`:

```yaml
# I valori arrivano dal file .env nella radice del repository (non versionato) o dalle variabili d'ambiente.
spring:
  application:
    name: arcade-backend
  config:
    import: "optional:file:../.env[.properties]"
  datasource:
    url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${POSTGRES_DB:arcade}
    username: ${BACKEND_DB_USER:arcade_backend}
    password: ${BACKEND_DB_PASSWORD:}
  flyway:
    url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${POSTGRES_DB:arcade}
    user: ${POSTGRES_USER:postgres}
    password: ${POSTGRES_PASSWORD:}
    locations: filesystem:../database/migrations
    # Il database locale e' gia' stato creato da Docker con V1..V5: vedi BaselineExistingSchemaStrategy.
    baseline-version: "5"

server:
  servlet:
    context-path: /api/v1

arcade:
  jwt:
    secret: ${JWT_DEV_SECRET:}
    ttl-minutes: 60

logging:
  pattern:
    level: "%5p [%X{traceId:-}]"
```

Aggiungi in fondo a `.env.example` (nella radice):

```
# --- Backend Spring Boot (backend/) ---
# Account di login del backend sul database (si crea con backend/scripts/crea-ruolo-backend.sql).
BACKEND_DB_USER=arcade_backend
BACKEND_DB_PASSWORD=
# Chiave per firmare i token di sviluppo: almeno 32 caratteri casuali. Solo per il tuo computer.
JWT_DEV_SECRET=
```

- [ ] **Step 5: Scrivi il database di prova e l'aiuto per i test**

`backend/src/test/resources/db/testdata/V900__test_backend_role_and_data.sql`:

```sql
-- SOLO PER I TEST: account di login del backend e due espositori di prova.
-- NOINHERIT: senza SET ROLE l'account non ha nessun permesso sui dati.
CREATE ROLE arcade_backend LOGIN NOINHERIT PASSWORD 'test' IN ROLE arcade_app, arcade_portal;

INSERT INTO core.exhibitor_category (name) VALUES ('Categoria di prova');

INSERT INTO core.exhibitor (exhibitor_code, legal_name, legal_name_norm, vat_number, category_id)
SELECT v.code, v.legal_name, upper(v.legal_name), v.vat, c.category_id
FROM (VALUES ('ESP901', 'Alfa Srl', 'IT00000000901'),
             ('ESP902', 'Beta Spa', 'IT00000000902')) AS v(code, legal_name, vat)
CROSS JOIN core.exhibitor_category c
WHERE c.name = 'Categoria di prova';
```

`backend/src/test/java/it/arcade/backend/support/PostgresSupport.java`:

```java
package it.arcade.backend.support;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.postgresql.PostgreSQLContainer;

/** Un solo PostgreSQL per tutti i test dell'esecuzione, creato dalle migrazioni V1..V5 piu' i dati di prova. */
public final class PostgresSupport {

    public static final PostgreSQLContainer DB = new PostgreSQLContainer("postgres:16-alpine");

    static {
        DB.start();
    }

    private PostgresSupport() {}

    public static void register(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", DB::getJdbcUrl);
        r.add("spring.datasource.username", () -> "arcade_backend");
        r.add("spring.datasource.password", () -> "test");
        r.add("spring.datasource.hikari.maximum-pool-size", () -> "1"); // forza il riuso della connessione
        r.add("spring.flyway.url", DB::getJdbcUrl);
        r.add("spring.flyway.user", DB::getUsername);
        r.add("spring.flyway.password", DB::getPassword);
        r.add("spring.flyway.locations", () -> "filesystem:../database/migrations,classpath:db/testdata");
        r.add("arcade.jwt.secret", () -> "chiave-di-prova-chiave-di-prova-0123456789");
    }

    /** Connessione come superutente del container: serve solo ai test per leggere gli id inseriti. */
    public static JdbcTemplate owner() {
        return new JdbcTemplate(new DriverManagerDataSource(DB.getJdbcUrl(), DB.getUsername(), DB.getPassword()));
    }
}
```

- [ ] **Step 6: Scrivi il test che fallisce**

`backend/src/test/java/it/arcade/backend/config/BaselineExistingSchemaStrategyTest.java`:

```java
package it.arcade.backend.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.postgresql.PostgreSQLContainer;

class BaselineExistingSchemaStrategyTest {

    private static Flyway flyway(PostgreSQLContainer pg) {
        return Flyway.configure()
                .dataSource(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword())
                .locations("filesystem:../database/migrations")
                .baselineVersion("5")
                .load();
    }

    @Test
    void suDatabaseVuotoApplicaTutteLeMigrazioni() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            Flyway flyway = flyway(pg);

            new BaselineExistingSchemaStrategy().migrate(flyway);

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("5");
            assertThat(flyway.info().applied()).hasSize(5);
        }
    }

    @Test
    void suSchemaGiaCreatoSenzaStoricoImpostaSoloIlRiferimentoAllaVersione5() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            flyway(pg).migrate(); // simula il database creato da Docker
            JdbcTemplate jdbc = new JdbcTemplate(
                    new DriverManagerDataSource(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword()));
            jdbc.execute("DROP TABLE flyway_schema_history"); // Docker non crea lo storico di Flyway

            Flyway flyway = flyway(pg);
            new BaselineExistingSchemaStrategy().migrate(flyway);

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("5");
            assertThat(flyway.info().applied()).hasSize(1); // solo il riferimento, nessuna migrazione rieseguita
            assertThat(jdbc.queryForObject("SELECT count(*) FROM core.edition", Integer.class)).isEqualTo(3);
        }
    }
}
```

- [ ] **Step 7: Esegui il test e verifica che fallisca**

```bash
cd backend
./mvnw -q -Dtest=BaselineExistingSchemaStrategyTest test
```

Atteso: errore di compilazione `cannot find symbol BaselineExistingSchemaStrategy`. La prima esecuzione scarica Maven e le dipendenze: può richiedere qualche minuto. Se compare un errore su Java 25 o su `testcontainers-postgresql`, vedi la tabella "Punti da controllare".

- [ ] **Step 8: Scrivi la classe**

`backend/src/main/java/it/arcade/backend/config/BaselineExistingSchemaStrategy.java`:

```java
package it.arcade.backend.config;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.flywaydb.core.Flyway;
import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;
import org.springframework.stereotype.Component;

/**
 * Il database locale e' creato da Docker eseguendo V1..V5 direttamente, senza lo storico di Flyway.
 * Se lo schema esiste gia' ma lo storico no, si imposta il riferimento alla versione di base
 * (spring.flyway.baseline-version) invece di rieseguire V1. Su un database vuoto si migra normalmente.
 */
@Component
public class BaselineExistingSchemaStrategy implements FlywayMigrationStrategy {

    @Override
    public void migrate(Flyway flyway) {
        if (flyway.info().current() == null && coreSchemaExists(flyway)) {
            flyway.baseline();
        }
        flyway.migrate();
    }

    private static boolean coreSchemaExists(Flyway flyway) {
        try (Connection c = flyway.getConfiguration().getDataSource().getConnection();
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT to_regclass('core.edition') IS NOT NULL")) {
            rs.next();
            return rs.getBoolean(1);
        } catch (SQLException e) {
            throw new IllegalStateException("Impossibile controllare lo schema del database", e);
        }
    }
}
```

- [ ] **Step 9: Esegui il test e verifica che passi**

```bash
./mvnw -q -Dtest=BaselineExistingSchemaStrategyTest test
```

Atteso: `Tests run: 2, Failures: 0, Errors: 0`. Il test avvia due container PostgreSQL: richiede Docker avviato.

- [ ] **Step 10: Aggiorna la specifica (§6)**

In `docs/superpowers/specs/2026-11-13-b2-scheletro-backend-design.md`, nella sezione 6 sostituisci il secondo punto elenco (quello che parla di `baselineOnMigrate=true`) con:

```
- Il database locale è già stato creato da quelle stesse migrazioni tramite Docker, senza lo storico di Flyway. `baselineOnMigrate` non è affidabile qui (lo schema `public` può sembrare vuoto e Flyway rieseguirebbe V1), quindi `BaselineExistingSchemaStrategy` controlla se esiste `core.edition`: se sì e lo storico manca, imposta il riferimento alla **versione 5** (`baseline-version: 5`) senza rieseguire nulla; se il database è vuoto migra normalmente.
```

- [ ] **Step 11: Commit**

```bash
cd ..
git add backend .env.example docs/superpowers/specs
git commit -m "Backend B2: progetto Maven, Flyway con riferimento alla versione 5 e database di prova"
```

---

## Task 2: Errori `problem+json`, verifica del JWT, `/health` e `/me`

**Deliverable:** il backend parte; senza token risponde `401` in `problem+json`; con un token valido `/me` mostra utente e ruoli; `/health` risponde senza token.

**Files:**
- Create: `backend/src/main/java/it/arcade/backend/error/ApiException.java`, `Problem.java`, `ProblemWriter.java`, `RestExceptionHandler.java`, `RequestIdFilter.java`
- Create: `backend/src/main/java/it/arcade/backend/security/Role.java`, `CurrentUser.java`, `JwtProperties.java`, `JwtService.java`
- Create: `backend/src/main/java/it/arcade/backend/config/SecurityConfig.java`
- Create: `backend/src/main/java/it/arcade/backend/api/HealthController.java`, `MeController.java`
- Test: `backend/src/test/java/it/arcade/backend/support/ApiTest.java`, `api/HealthApiTest.java`, `api/MeApiTest.java`

**Interfaces:**
- Consumes: `PostgresSupport.register(...)` (Task 1).
- Produces:
  - `Role` (enum, `isStaff()`), `CurrentUser(String username, String displayName, Set<Role> roles, Integer exhibitorId)` con `static CurrentUser from(Jwt)`.
  - `JwtService.issue(String username, Set<Role> roles, Integer exhibitorId)` e `JwtService.issueClaims(String username, Collection<String> roles, Integer exhibitorId, Duration ttl)`, entrambi restituiscono il token come `String`.
  - `ApiException(HttpStatus status, String code, String title, String detail)` e `ApiException.notFound(String code, String title)`.
  - `ProblemWriter.write(HttpServletResponse, HttpStatus, String code, String title, String detail)`.
  - `ApiTest` (classe base dei test API): `mvc`, `jwt`, `bearer(Integer exhibitorId, Role... roles)`, `exhibitorId(String code)`.

- [ ] **Step 1: Scrivi la classe base dei test e i test che falliscono**

`backend/src/test/java/it/arcade/backend/support/ApiTest.java`:

```java
package it.arcade.backend.support;

import it.arcade.backend.security.JwtService;
import it.arcade.backend.security.Role;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
public abstract class ApiTest {

    @Autowired protected MockMvc mvc;
    @Autowired protected JwtService jwt;

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
    }

    protected String bearer(Integer exhibitorId, Role... roles) {
        return "Bearer " + jwt.issue("utente.prova", Set.of(roles), exhibitorId);
    }

    protected int exhibitorId(String code) {
        return PostgresSupport.owner().queryForObject(
                "SELECT exhibitor_id FROM core.exhibitor WHERE exhibitor_code = ?", Integer.class, code);
    }
}
```

`backend/src/test/java/it/arcade/backend/api/HealthApiTest.java`:

```java
package it.arcade.backend.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.support.ApiTest;
import org.junit.jupiter.api.Test;

class HealthApiTest extends ApiTest {

    @Test
    void rispondeSenzaTokenEIndicaCheIlDatabaseRispondeDa() throws Exception {
        mvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
```

`backend/src/test/java/it/arcade/backend/api/MeApiTest.java`:

```java
package it.arcade.backend.api;

import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.emptyOrNullString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.security.JwtProperties;
import it.arcade.backend.security.JwtService;
import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import java.time.Duration;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class MeApiTest extends ApiTest {

    @Test
    void senzaTokenRisponde401ConProblemJson() throws Exception {
        mvc.perform(get("/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"))
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.traceId").value(not(emptyOrNullString())));
    }

    @Test
    void tokenStaffMostraUtenteERuoli() throws Exception {
        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("utente.prova"))
                .andExpect(jsonPath("$.roles", hasItem("ADMIN")))
                .andExpect(jsonPath("$.exhibitorId").value(nullValue()));
    }

    @Test
    void tokenEspositoreMostraLoStessoExhibitorIdDelToken() throws Exception {
        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, bearer(42, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorId").value(42));
    }

    @Test
    void tokenFirmatoConUnaChiaveDiversaRisponde401() throws Exception {
        JwtService altro = new JwtService(new JwtProperties("un-altro-segreto-un-altro-segreto-0123", 60));
        String falso = altro.issue("intruso", Set.of(Role.ADMIN), null);

        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + falso))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void tokenScadutoRisponde401() throws Exception {
        String scaduto = jwt.issueClaims("utente.prova", java.util.List.of("ADMIN"), null, Duration.ofMinutes(-5));

        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + scaduto))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void percorsoSconosciutoSenzaTokenRisponde401() throws Exception {
        mvc.perform(get("/non-esiste"))
                .andExpect(status().isUnauthorized());
    }
}
```

- [ ] **Step 2: Esegui i test e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest='HealthApiTest,MeApiTest' test
```

Atteso: errore di compilazione (`JwtService`, `Role`, `JwtProperties` non esistono).

- [ ] **Step 3: Scrivi il pacchetto `error`**

`backend/src/main/java/it/arcade/backend/error/ApiException.java`:

```java
package it.arcade.backend.error;

import org.springframework.http.HttpStatus;

/** Errore previsto dell'API: diventa una risposta problem+json con questo codice stabile. */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;

    public ApiException(HttpStatus status, String code, String title, String detail) {
        super(detail != null ? detail : title);
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
    }

    public static ApiException notFound(String code, String title) {
        return new ApiException(HttpStatus.NOT_FOUND, code, title, null);
    }

    public static ApiException forbidden() {
        return new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Ruolo non autorizzato", null);
    }

    public HttpStatus status() { return status; }
    public String code() { return code; }
    public String title() { return title; }
    public String detail() { return detail; }
}
```

`backend/src/main/java/it/arcade/backend/error/Problem.java`:

```java
package it.arcade.backend.error;

import com.fasterxml.jackson.annotation.JsonInclude;

/** Corpo degli errori (schema `Problem` di docs/api/openapi.yaml). */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record Problem(String type, String title, int status, String code, String detail, String traceId) {}
```

`backend/src/main/java/it/arcade/backend/error/RequestIdFilter.java`:

```java
package it.arcade.backend.error;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Assegna a ogni richiesta un identificativo (mai preso dal client) per ritrovarla nei log. */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {

    public static final String MDC_KEY = "traceId";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String id = UUID.randomUUID().toString();
        MDC.put(MDC_KEY, id);
        response.setHeader("X-Request-Id", id);
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }
}
```

`backend/src/main/java/it/arcade/backend/error/ProblemWriter.java`:

```java
package it.arcade.backend.error;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class ProblemWriter {

    private final ObjectMapper mapper;

    public ProblemWriter(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    public Problem problem(HttpStatus status, String code, String title, String detail) {
        return new Problem("about:blank", title, status.value(), code, detail, MDC.get(RequestIdFilter.MDC_KEY));
    }

    /** Per i filtri di sicurezza, che rispondono fuori dai controller. */
    public void write(HttpServletResponse response, HttpStatus status, String code, String title, String detail)
            throws IOException {
        response.setStatus(status.value());
        response.setContentType("application/problem+json");
        response.setCharacterEncoding("UTF-8");
        mapper.writeValue(response.getOutputStream(), problem(status, code, title, detail));
    }
}
```

`backend/src/main/java/it/arcade/backend/error/RestExceptionHandler.java`:

```java
package it.arcade.backend.error;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class RestExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(RestExceptionHandler.class);
    private static final MediaType PROBLEM = MediaType.valueOf("application/problem+json");

    private final ProblemWriter problems;

    public RestExceptionHandler(ProblemWriter problems) {
        this.problems = problems;
    }

    @ExceptionHandler(ApiException.class)
    ResponseEntity<Problem> api(ApiException e) {
        return reply(e.status(), e.code(), e.title(), e.detail());
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<Problem> notFound(NoResourceFoundException e) {
        return reply(HttpStatus.NOT_FOUND, "NOT_FOUND", "Risorsa non trovata", null);
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    ResponseEntity<Problem> method(HttpRequestMethodNotSupportedException e) {
        return reply(HttpStatus.METHOD_NOT_ALLOWED, "METHOD_NOT_ALLOWED", "Metodo non consentito", null);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<Problem> unreadable(HttpMessageNotReadableException e) {
        return reply(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Corpo della richiesta non valido", null);
    }

    /** Questi li gestisce la catena di sicurezza (401/403): qui non vanno trasformati in 500. */
    @ExceptionHandler({AccessDeniedException.class, AuthenticationException.class})
    void security(Exception e) throws Exception {
        throw e;
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Problem> unexpected(Exception e) {
        log.error("Errore non previsto", e);
        return reply(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "Errore interno", null);
    }

    private ResponseEntity<Problem> reply(HttpStatus status, String code, String title, String detail) {
        return ResponseEntity.status(status).contentType(PROBLEM).body(problems.problem(status, code, title, detail));
    }
}
```

- [ ] **Step 4: Scrivi il pacchetto `security`**

`backend/src/main/java/it/arcade/backend/security/Role.java`:

```java
package it.arcade.backend.security;

/** Ruoli del contratto API (x-roles in docs/api/openapi.yaml). */
public enum Role {
    ADMIN, COMMERCIAL, OPS, EXHIBITOR, SCANNER, BI_READER;

    public boolean isStaff() {
        return this == ADMIN || this == COMMERCIAL || this == OPS;
    }
}
```

`backend/src/main/java/it/arcade/backend/security/CurrentUser.java`:

```java
package it.arcade.backend.security;

import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import org.springframework.security.oauth2.jwt.Jwt;

/** Utente che ha fatto la richiesta, ricavato dal token. I ruoli sconosciuti vengono ignorati. */
public record CurrentUser(String username, String displayName, Set<Role> roles, Integer exhibitorId) {

    public static CurrentUser from(Jwt jwt) {
        Set<Role> roles = EnumSet.noneOf(Role.class);
        List<String> raw = jwt.getClaimAsStringList("roles");
        if (raw != null) {
            for (String name : raw) {
                try {
                    roles.add(Role.valueOf(name));
                } catch (IllegalArgumentException ignored) {
                    // ruolo non previsto dal contratto: non concede nulla
                }
            }
        }
        Object id = jwt.getClaim("exhibitor_id");
        Integer exhibitorId = id instanceof Number n ? n.intValue() : null;
        return new CurrentUser(jwt.getSubject(), jwt.getClaimAsString("name"), roles, exhibitorId);
    }
}
```

`backend/src/main/java/it/arcade/backend/security/JwtProperties.java`:

```java
package it.arcade.backend.security;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

@ConfigurationProperties(prefix = "arcade.jwt")
public record JwtProperties(String secret, @DefaultValue("60") long ttlMinutes) {}
```

`backend/src/main/java/it/arcade/backend/security/JwtService.java`:

```java
package it.arcade.backend.security;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.stereotype.Service;

/**
 * Firma e verifica i token con una chiave HMAC locale (solo sviluppo). Per passare a Entra ID
 * si sostituisce il decoder con uno basato sull'indirizzo dell'emittente: i controller non cambiano.
 */
@Service
public class JwtService {

    private final SecretKey key;
    private final JwtEncoder encoder;
    private final Duration defaultTtl;

    public JwtService(JwtProperties properties) {
        String secret = properties.secret() == null ? "" : properties.secret();
        byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) {
            throw new IllegalStateException(
                    "La chiave dei token e' mancante o troppo corta: imposta JWT_DEV_SECRET con almeno 32 caratteri.");
        }
        this.key = new SecretKeySpec(bytes, "HmacSHA256");
        this.encoder = new NimbusJwtEncoder(new ImmutableSecret<>(key));
        this.defaultTtl = Duration.ofMinutes(properties.ttlMinutes());
    }

    public JwtDecoder decoder() {
        return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
    }

    public String issue(String username, Set<Role> roles, Integer exhibitorId) {
        List<String> names = roles.stream().map(Role::name).sorted().toList();
        return issueClaims(username, names, exhibitorId, defaultTtl);
    }

    /** Accetta anche nomi di ruolo qualsiasi: serve ai test per provare i ruoli sconosciuti. */
    public String issueClaims(String username, Collection<String> roles, Integer exhibitorId, Duration ttl) {
        Instant now = Instant.now();
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .subject(username)
                .issuedAt(now)
                .expiresAt(now.plus(ttl))
                .claim("roles", List.copyOf(roles));
        if (exhibitorId != null) {
            claims.claim("exhibitor_id", exhibitorId);
        }
        JwsHeader header = JwsHeader.with(MacAlgorithm.HS256).build();
        return encoder.encode(JwtEncoderParameters.from(header, claims.build())).getTokenValue();
    }
}
```

- [ ] **Step 5: Scrivi la configurazione di sicurezza**

`backend/src/main/java/it/arcade/backend/config/SecurityConfig.java`:

```java
package it.arcade.backend.config;

import it.arcade.backend.error.ProblemWriter;
import it.arcade.backend.security.JwtService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.AccessDeniedHandler;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    JwtDecoder jwtDecoder(JwtService jwtService) {
        return jwtService.decoder();
    }

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http, ProblemWriter problems) throws Exception {
        AuthenticationEntryPoint unauthenticated = (request, response, ex) -> {
            response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Bearer");
            problems.write(response, HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "Token mancante o non valido", null);
        };
        AccessDeniedHandler forbidden = (request, response, ex) ->
                problems.write(response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Ruolo non autorizzato", null);

        JwtGrantedAuthoritiesConverter authorities = new JwtGrantedAuthoritiesConverter();
        authorities.setAuthoritiesClaimName("roles");
        authorities.setAuthorityPrefix("ROLE_");
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(authorities);

        http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(a -> a
                        .requestMatchers("/health", "/dev/token").permitAll()
                        .requestMatchers("/me").authenticated()
                        .requestMatchers("/editions").hasAnyRole("ADMIN", "COMMERCIAL", "OPS", "EXHIBITOR")
                        .requestMatchers("/portal/me").hasRole("EXHIBITOR")
                        .anyRequest().denyAll())
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(unauthenticated)
                        .accessDeniedHandler(forbidden))
                .oauth2ResourceServer(o -> o
                        .jwt(j -> j.jwtAuthenticationConverter(converter))
                        .authenticationEntryPoint(unauthenticated)
                        .accessDeniedHandler(forbidden));
        return http.build();
    }
}
```

`/dev/token` è sempre "permitAll": se il profilo `dev` non è attivo il controller non esiste e la risposta è `404`.

- [ ] **Step 6: Scrivi `/health` e `/me`**

`backend/src/main/java/it/arcade/backend/api/HealthController.java`:

```java
package it.arcade.backend.api;

import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    private static final Logger log = LoggerFactory.getLogger(HealthController.class);
    private final JdbcClient jdbc;

    public HealthController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        try {
            jdbc.sql("SELECT 1").query(Integer.class).single();
            return ResponseEntity.ok(Map.of("status", "UP"));
        } catch (Exception e) {
            log.warn("Il database non risponde: {}", e.getMessage());
            return ResponseEntity.status(503).body(Map.of("status", "DOWN"));
        }
    }
}
```

`backend/src/main/java/it/arcade/backend/api/MeController.java`:

```java
package it.arcade.backend.api;

import com.fasterxml.jackson.annotation.JsonInclude;
import it.arcade.backend.security.CurrentUser;
import it.arcade.backend.security.Role;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MeController {

    /** Schema `CurrentUser` del contratto: `exhibitorId` e' sempre presente (null per lo staff). */
    public record CurrentUserResponse(
            String username,
            @JsonInclude(JsonInclude.Include.NON_NULL) String displayName,
            List<Role> roles,
            Integer exhibitorId) {}

    @GetMapping("/me")
    public CurrentUserResponse me(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user = CurrentUser.from(jwt);
        return new CurrentUserResponse(
                user.username(), user.displayName(), user.roles().stream().sorted().toList(), user.exhibitorId());
    }
}
```

- [ ] **Step 7: Esegui i test e verifica che passino**

```bash
./mvnw -q -Dtest='HealthApiTest,MeApiTest' test
```

Atteso: `Tests run: 7, Failures: 0, Errors: 0` (1 health + 6 me). Se il contesto non parte, leggi l'errore: i casi più probabili sono la chiave JWT (impostata da `PostgresSupport`) e il seed `V900` (colonne di `core.exhibitor`).

- [ ] **Step 8: Commit**

```bash
cd ..
git add backend
git commit -m "Backend B2: errori problem+json, verifica del token, /health e /me"
```

---

## Task 3: Accesso al database per ruolo, `/editions` e `/portal/me`

**Deliverable:** lo staff e l'espositore leggono dal database con il ruolo giusto; un espositore non vede i dati di un altro.

**Files:**
- Create: `backend/src/main/java/it/arcade/backend/db/DbRole.java`, `ScopedDb.java`
- Create: `backend/src/main/java/it/arcade/backend/api/EditionController.java`, `PortalController.java`
- Test: `backend/src/test/java/it/arcade/backend/db/ScopedDbTest.java`, `api/EditionsApiTest.java`, `api/PortalApiTest.java`

**Interfaces:**
- Consumes: `CurrentUser`, `Role`, `ApiException` (Task 2); `ApiTest`, `PostgresSupport` (Task 1–2).
- Produces:
  - `DbRole` (enum `STAFF("arcade_app")`, `PORTAL("arcade_portal")`) con `sqlName()` e `static DbRole forUser(CurrentUser)` (lancia `ApiException.forbidden()` se non staff e non espositore).
  - `ScopedDb.read(DbRole role, Integer exhibitorId, Function<JdbcClient, T> work)` → `T`. Esegue `work` in una transazione in sola lettura con il ruolo del database e, se `role == PORTAL` e `exhibitorId != null`, `app.exhibitor_id` impostato.

- [ ] **Step 1: Scrivi i test che falliscono**

`backend/src/test/java/it/arcade/backend/db/ScopedDbTest.java`:

```java
package it.arcade.backend.db;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.support.PostgresSupport;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest
class ScopedDbTest {

    @Autowired ScopedDb db;
    @Autowired JdbcClient jdbc;

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
    }

    private int exhibitorId(String code) {
        return PostgresSupport.owner().queryForObject(
                "SELECT exhibitor_id FROM core.exhibitor WHERE exhibitor_code = ?", Integer.class, code);
    }

    private static int countExhibitors(JdbcClient jdbc) {
        return jdbc.sql("SELECT count(*) FROM core.exhibitor").query(Integer.class).single();
    }

    @Test
    void lo_staff_vede_tutti_gli_espositori() {
        assertThat(db.read(DbRole.STAFF, null, ScopedDbTest::countExhibitors)).isGreaterThanOrEqualTo(2);
    }

    @Test
    void il_portale_vede_solo_il_proprio_espositore() {
        int alfa = exhibitorId("ESP901");
        assertThat(db.read(DbRole.PORTAL, alfa, ScopedDbTest::countExhibitors)).isEqualTo(1);
    }

    @Test
    void il_portale_senza_exhibitor_id_non_vede_nulla() {
        assertThat(db.read(DbRole.PORTAL, null, ScopedDbTest::countExhibitors)).isZero();
    }

    @Test
    void ruolo_e_exhibitor_id_non_restano_sulla_connessione() {
        int alfa = exhibitorId("ESP901");
        db.read(DbRole.PORTAL, alfa, ScopedDbTest::countExhibitors); // il pool ha una sola connessione

        String utente = jdbc.sql("SELECT current_user").query(String.class).single();
        assertThat(utente).isEqualTo("arcade_backend");
        assertThat(db.read(DbRole.STAFF, null, ScopedDbTest::countExhibitors)).isGreaterThanOrEqualTo(2);
    }

    @Test
    void l_account_del_backend_senza_set_role_non_legge_core() {
        assertThatThrownBy(() -> countExhibitors(jdbc)).hasMessageContaining("permission denied");
    }
}
```

`backend/src/test/java/it/arcade/backend/api/EditionsApiTest.java`:

```java
package it.arcade.backend.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class EditionsApiTest extends ApiTest {

    @Test
    void lo_staff_legge_le_edizioni_con_i_giorni() throws Exception {
        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.COMMERCIAL)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].year").value(2024))
                .andExpect(jsonPath("$[0].status").value("CLOSED"))
                .andExpect(jsonPath("$[0].days.length()").value(3))
                .andExpect(jsonPath("$[0].days[0].dayDate").value("2024-12-20"))
                .andExpect(jsonPath("$[0].days[0].opensAt").value("09:00"))
                .andExpect(jsonPath("$[0].days[0].closesAt").value("17:30"))
                .andExpect(jsonPath("$[2].days.length()").value(0));
    }

    @Test
    void l_espositore_puo_leggere_le_edizioni() throws Exception {
        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, bearer(exhibitorId("ESP901"), Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));
    }

    @Test
    void il_ruolo_scanner_non_e_autorizzato() throws Exception {
        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.SCANNER)))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    @Test
    void un_token_con_soli_ruoli_sconosciuti_non_e_autorizzato() throws Exception {
        String token = jwt.issueClaims("utente.prova", List.of("SUPERUSER", "root"), null, Duration.ofMinutes(5));

        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isForbidden());
    }

    @Test
    void senza_token_risponde_401() throws Exception {
        mvc.perform(get("/editions")).andExpect(status().isUnauthorized());
    }
}
```

`backend/src/test/java/it/arcade/backend/api/PortalApiTest.java`:

```java
package it.arcade.backend.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class PortalApiTest extends ApiTest {

    @Test
    void l_espositore_vede_solo_il_proprio_profilo() throws Exception {
        int alfa = exhibitorId("ESP901");

        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(alfa, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorId").value(alfa))
                .andExpect(jsonPath("$.exhibitorCode").value("ESP901"))
                .andExpect(jsonPath("$.legalName").value("Alfa Srl"))
                .andExpect(jsonPath("$.categoryName").value("Categoria di prova"));
    }

    @Test
    void un_altro_espositore_non_vede_i_dati_del_primo() throws Exception {
        int beta = exhibitorId("ESP902");

        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(beta, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorCode").value("ESP902"));
    }

    @Test
    void senza_exhibitor_id_nel_token_non_si_vede_nulla() throws Exception {
        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.EXHIBITOR)))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.code").value("PORTAL_PROFILE_NOT_FOUND"));
    }

    @Test
    void un_exhibitor_id_inesistente_risponde_404() throws Exception {
        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(999999, Role.EXHIBITOR)))
                .andExpect(status().isNotFound());
    }

    @Test
    void lo_staff_non_puo_usare_il_portale() throws Exception {
        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isForbidden());
    }

    @Test
    void un_token_con_ruolo_staff_ed_espositore_vede_solo_il_proprio_profilo() throws Exception {
        int alfa = exhibitorId("ESP901");

        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(alfa, Role.ADMIN, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorCode").value("ESP901"));
    }
}
```

- [ ] **Step 2: Esegui i test e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest='ScopedDbTest,EditionsApiTest,PortalApiTest' test
```

Atteso: errore di compilazione (`ScopedDb`, `DbRole` non esistono).

- [ ] **Step 3: Scrivi il pacchetto `db`**

`backend/src/main/java/it/arcade/backend/db/DbRole.java`:

```java
package it.arcade.backend.db;

import it.arcade.backend.error.ApiException;
import it.arcade.backend.security.CurrentUser;
import it.arcade.backend.security.Role;

/** Ruoli del database usati per le richieste. Il nome e' una costante: mai testo preso dal client. */
public enum DbRole {
    STAFF("arcade_app"),
    PORTAL("arcade_portal");

    private final String sqlName;

    DbRole(String sqlName) {
        this.sqlName = sqlName;
    }

    public String sqlName() {
        return sqlName;
    }

    /** Staff se ha un ruolo staff, altrimenti portale se e' un espositore, altrimenti 403. */
    public static DbRole forUser(CurrentUser user) {
        if (user.roles().stream().anyMatch(Role::isStaff)) {
            return STAFF;
        }
        if (user.roles().contains(Role.EXHIBITOR)) {
            return PORTAL;
        }
        throw ApiException.forbidden();
    }
}
```

`backend/src/main/java/it/arcade/backend/db/ScopedDb.java`:

```java
package it.arcade.backend.db;

import java.util.function.Function;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Unico punto che cambia il ruolo del database. Ogni lettura gira in una transazione in sola lettura:
 * SET LOCAL ROLE e set_config(..., true) valgono solo fino alla fine della transazione, quindi
 * non restano sulla connessione del pool.
 */
@Component
public class ScopedDb {

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public ScopedDb(JdbcClient jdbc, PlatformTransactionManager transactionManager) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactionManager);
        this.tx.setReadOnly(true);
    }

    public <T> T read(DbRole role, Integer exhibitorId, Function<JdbcClient, T> work) {
        return tx.execute(status -> {
            jdbc.sql("SET LOCAL ROLE " + role.sqlName()).update();
            if (role == DbRole.PORTAL && exhibitorId != null) {
                jdbc.sql("SELECT set_config('app.exhibitor_id', :id, true)")
                        .param("id", String.valueOf(exhibitorId))
                        .query(String.class)
                        .single();
            }
            return work.apply(jdbc);
        });
    }
}
```

- [ ] **Step 4: Scrivi i controller**

`backend/src/main/java/it/arcade/backend/api/EditionController.java`:

```java
package it.arcade.backend.api;

import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.security.CurrentUser;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class EditionController {

    private static final DateTimeFormatter HHMM = DateTimeFormatter.ofPattern("HH:mm");

    public record EditionDay(LocalDate dayDate, int dayNumber, String opensAt, String closesAt) {}

    public record Edition(int editionId, int year, String name, String status, String timezone,
                          List<EditionDay> days) {}

    private final ScopedDb db;

    public EditionController(ScopedDb db) {
        this.db = db;
    }

    @GetMapping("/editions")
    public List<Edition> list(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user = CurrentUser.from(jwt);
        return db.read(DbRole.forUser(user), user.exhibitorId(), jdbc -> {
            Map<Integer, Edition> byId = new LinkedHashMap<>();
            jdbc.sql("SELECT edition_id, year, name, status, timezone FROM core.edition ORDER BY year")
                    .query((rs, n) -> new Edition(rs.getInt("edition_id"), rs.getInt("year"), rs.getString("name"),
                            rs.getString("status"), rs.getString("timezone"), new ArrayList<>()))
                    .list()
                    .forEach(e -> byId.put(e.editionId(), e));
            jdbc.sql("SELECT edition_id, day_date, day_number, opens_at, closes_at "
                            + "FROM core.edition_day ORDER BY edition_id, day_date")
                    .query(rs -> {
                        byId.get(rs.getInt("edition_id")).days().add(new EditionDay(
                                rs.getObject("day_date", LocalDate.class),
                                rs.getInt("day_number"),
                                rs.getObject("opens_at", LocalTime.class).format(HHMM),
                                rs.getObject("closes_at", LocalTime.class).format(HHMM)));
                    });
            return new ArrayList<>(byId.values());
        });
    }
}
```

`backend/src/main/java/it/arcade/backend/api/PortalController.java`:

```java
package it.arcade.backend.api;

import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.security.CurrentUser;
import java.util.Optional;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PortalController {

    public record PortalProfile(int exhibitorId, String exhibitorCode, String legalName, String categoryName) {}

    private final ScopedDb db;

    public PortalController(ScopedDb db) {
        this.db = db;
    }

    /**
     * Usa SEMPRE il ruolo PORTAL, anche se il token ha pure un ruolo staff: la query non ha un filtro
     * sull'id, e' la sicurezza per riga del database a limitare il risultato al proprio espositore.
     */
    @GetMapping("/portal/me")
    public PortalProfile me(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user = CurrentUser.from(jwt);
        Optional<PortalProfile> profile = db.read(DbRole.PORTAL, user.exhibitorId(), jdbc -> jdbc.sql("""
                        SELECT e.exhibitor_id, e.exhibitor_code, e.legal_name, c.name AS category_name
                          FROM core.exhibitor e
                          JOIN core.exhibitor_category c ON c.category_id = e.category_id
                        """)
                .query((rs, n) -> new PortalProfile(rs.getInt("exhibitor_id"), rs.getString("exhibitor_code"),
                        rs.getString("legal_name"), rs.getString("category_name")))
                .optional());
        return profile.orElseThrow(() ->
                ApiException.notFound("PORTAL_PROFILE_NOT_FOUND", "Profilo espositore non trovato"));
    }
}
```

- [ ] **Step 5: Esegui i test e verifica che passino**

```bash
./mvnw -q -Dtest='ScopedDbTest,EditionsApiTest,PortalApiTest' test
```

Atteso: `Tests run: 16, Failures: 0, Errors: 0` (5 + 5 + 6). Se `PortalApiTest` fallisce con un errore SQL all'avvio, il problema è nel seed `V900` (trigger o colonne di `core.exhibitor`): correggi il seed, non il codice.

- [ ] **Step 6: Esegui tutta la suite**

```bash
./mvnw -q test
```

Atteso: tutti i test passano (Task 1: 2, Task 2: 7, Task 3: 16, totale 25).

- [ ] **Step 7: Commit**

```bash
cd ..
git add backend
git commit -m "Backend B2: accesso al database per ruolo, /editions e /portal/me"
```

---

## Task 4: Token di sviluppo, avvio locale e documentazione

**Deliverable:** con `arcade-db` avviato si può lanciare il backend, ottenere un token e leggere dati reali (135 espositori nel database; un espositore vede solo il proprio profilo).

**Files:**
- Create: `backend/src/main/java/it/arcade/backend/security/DevTokenController.java`
- Create: `backend/scripts/crea-ruolo-backend.sql`
- Create: `backend/README.md`
- Test: `backend/src/test/java/it/arcade/backend/security/DevTokenApiTest.java`, `DevTokenDisabledApiTest.java`
- Modify: `docs/superpowers/specs/2026-11-13-b2-scheletro-backend-design.md` (stato)

**Interfaces:**
- Consumes: `JwtService.issue(...)`, `Role`, `ApiException` (Task 2).
- Produces: `POST /dev/token` con corpo `{"username": string, "roles": [string], "exhibitorId": integer|null}` → `{"accessToken": string, "tokenType": "Bearer", "expiresInSeconds": number}`; solo con profilo `dev`.

- [ ] **Step 1: Scrivi i test che falliscono**

`backend/src/test/java/it/arcade/backend/security/DevTokenApiTest.java`:

```java
package it.arcade.backend.security;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.support.ApiTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;

@ActiveProfiles("dev")
class DevTokenApiTest extends ApiTest {

    @Autowired ObjectMapper json;

    private String richiesta(String username, String... roles) throws Exception {
        return json.writeValueAsString(java.util.Map.of("username", username, "roles", java.util.List.of(roles)));
    }

    @Test
    void emette_un_token_che_funziona_su_me() throws Exception {
        String risposta = mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content(richiesta("mattia", "ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tokenType").value("Bearer"))
                .andReturn().getResponse().getContentAsString();
        String token = json.readTree(risposta).get("accessToken").asText();

        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("mattia"));
    }

    @Test
    void rifiuta_un_ruolo_inesistente() throws Exception {
        mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content(richiesta("mattia", "SUPERUSER")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
    }

    @Test
    void rifiuta_un_corpo_malformato() throws Exception {
        mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON).content("{non json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
    }
}
```

`backend/src/test/java/it/arcade/backend/security/DevTokenDisabledApiTest.java`:

```java
package it.arcade.backend.security;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.support.ApiTest;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

/** Senza il profilo dev l'endpoint che emette token non deve esistere. */
class DevTokenDisabledApiTest extends ApiTest {

    @Test
    void senza_profilo_dev_l_endpoint_non_esiste() throws Exception {
        mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"x\",\"roles\":[\"ADMIN\"]}"))
                .andExpect(status().isNotFound());
    }
}
```

- [ ] **Step 2: Esegui i test e verifica che falliscano**

```bash
cd backend
./mvnw -q -Dtest='DevTokenApiTest,DevTokenDisabledApiTest' test
```

Atteso: `DevTokenApiTest` fallisce con `404` (l'endpoint non esiste ancora); `DevTokenDisabledApiTest` passa già.

- [ ] **Step 3: Scrivi il controller**

`backend/src/main/java/it/arcade/backend/security/DevTokenController.java`:

```java
package it.arcade.backend.security;

import it.arcade.backend.error.ApiException;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** SOLO SVILUPPO: emette token per provare ruoli e isolamento. Esiste solo con il profilo `dev`. */
@Profile("dev")
@RestController
public class DevTokenController {

    public record TokenRequest(String username, List<String> roles, Integer exhibitorId) {}

    public record TokenResponse(String accessToken, String tokenType, long expiresInSeconds) {}

    private final JwtService jwt;
    private final JwtProperties properties;

    public DevTokenController(JwtService jwt, JwtProperties properties) {
        this.jwt = jwt;
        this.properties = properties;
    }

    @PostMapping("/dev/token")
    public TokenResponse token(@RequestBody TokenRequest request) {
        if (request.username() == null || request.username().isBlank()) {
            throw invalid("username obbligatorio");
        }
        if (request.roles() == null || request.roles().isEmpty()) {
            throw invalid("indica almeno un ruolo");
        }
        Set<Role> roles = EnumSet.noneOf(Role.class);
        for (String name : request.roles()) {
            try {
                roles.add(Role.valueOf(name));
            } catch (IllegalArgumentException e) {
                throw invalid("ruolo sconosciuto: " + name);
            }
        }
        String token = jwt.issue(request.username(), roles, request.exhibitorId());
        return new TokenResponse(token, "Bearer", properties.ttlMinutes() * 60);
    }

    private static ApiException invalid(String detail) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Richiesta non valida", detail);
    }
}
```

- [ ] **Step 4: Esegui i test e verifica che passino**

```bash
./mvnw -q -Dtest='DevTokenApiTest,DevTokenDisabledApiTest' test
```

Atteso: `Tests run: 4, Failures: 0, Errors: 0`.

- [ ] **Step 5: Scrivi lo script per l'account del backend**

`backend/scripts/crea-ruolo-backend.sql`:

```sql
-- Crea (o aggiorna la password di) l'account di login del backend sul database locale.
-- NOINHERIT: senza SET ROLE l'account non ha permessi sui dati; il backend passa ad arcade_app o
-- arcade_portal solo dentro la transazione di ogni richiesta.
-- La password NON e' in questo file: si passa con -v pwd=... (vedi backend/README.md).
SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'arcade_backend') AS mancante \gset
\if :mancante
  CREATE ROLE arcade_backend LOGIN NOINHERIT PASSWORD :'pwd' IN ROLE arcade_app, arcade_portal;
\else
  ALTER ROLE arcade_backend LOGIN NOINHERIT PASSWORD :'pwd';
\endif
```

- [ ] **Step 6: Scrivi `backend/README.md`**

```markdown
# Backend ARCADE Milano (B2: scheletro)

Spring Boot 3.5, Java 25, Maven (wrapper). Implementa `/health`, `/me`, `/editions` e `/portal/me` del contratto `docs/api/openapi.yaml`. Preventivi, contratti e pagamenti sono in B3.

Specifica: `docs/superpowers/specs/2026-11-13-b2-scheletro-backend-design.md`.

## Avvio in locale

1. Database locale avviato (`docker compose up -d` dalla radice del repository).
2. Nel file `.env` della radice compila `BACKEND_DB_PASSWORD` (scegli una password locale) e `JWT_DEV_SECRET` (almeno 32 caratteri casuali). Il file non è versionato.
3. Crea l'account del backend sul database (una volta sola; rieseguilo per cambiare password). Dalla radice, in Git Bash:

   ```bash
   set -a; . <(tr -d '\r' < .env); set +a
   docker exec -i arcade-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
     -v pwd="$BACKEND_DB_PASSWORD" < backend/scripts/crea-ruolo-backend.sql
   ```

4. Avvia il backend con il profilo `dev`:

   ```bash
   cd backend
   ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
   ```

Al primo avvio Flyway imposta il riferimento alla versione 5 (il database è già stato creato da Docker) e non modifica i dati.

## Provarlo

```bash
# token da staff
T=$(curl -s -X POST localhost:8080/api/v1/dev/token -H 'Content-Type: application/json' \
      -d '{"username":"mattia","roles":["ADMIN"]}' | sed 's/.*"accessToken":"\([^"]*\)".*/\1/')
curl -s -H "Authorization: Bearer $T" localhost:8080/api/v1/editions
curl -s -H "Authorization: Bearer $T" localhost:8080/api/v1/me
```

Per un espositore: leggi un id con
`docker exec arcade-db psql -U postgres -d arcade -At -c "SELECT exhibitor_id FROM core.exhibitor LIMIT 1"`
e chiedi un token con `"roles":["EXHIBITOR"],"exhibitorId":<id>`; poi `GET /api/v1/portal/me`.

## Test

```bash
cd backend
./mvnw test
```

Servono Docker avviato (i test creano un PostgreSQL in container) e nessun file `.env`. I test non toccano il database locale.

## Limiti noti

- Il token di sviluppo usa una chiave locale: Entra ID non è configurato né provato.
- Solo quattro endpoint; il resto del contratto non è implementato.
- Provato solo sul database locale, non sul server Azure.
```

- [ ] **Step 7: Avvia il backend sul database locale e provalo davvero**

Prima compila il `.env` (`BACKEND_DB_PASSWORD` e `JWT_DEV_SECRET`), poi esegui i passi 3 e 4 del README. Poi, con il backend in esecuzione, in un altro terminale:

```bash
T=$(curl -s -X POST localhost:8080/api/v1/dev/token -H 'Content-Type: application/json' -d '{"username":"mattia","roles":["ADMIN"]}' | sed 's/.*"accessToken":"\([^"]*\)".*/\1/')
curl -s localhost:8080/api/v1/health
curl -s -H "Authorization: Bearer $T" localhost:8080/api/v1/editions | head -c 400
ID=$(docker exec arcade-db psql -U postgres -d arcade -At -c "SELECT exhibitor_id FROM core.exhibitor ORDER BY exhibitor_id LIMIT 1")
E=$(curl -s -X POST localhost:8080/api/v1/dev/token -H 'Content-Type: application/json' -d "{\"username\":\"esp\",\"roles\":[\"EXHIBITOR\"],\"exhibitorId\":$ID}" | sed 's/.*"accessToken":"\([^"]*\)".*/\1/')
curl -s -H "Authorization: Bearer $E" localhost:8080/api/v1/portal/me
curl -s -o /dev/null -w "staff su /portal/me: %{http_code}\n" -H "Authorization: Bearer $T" localhost:8080/api/v1/portal/me
curl -s -o /dev/null -w "senza token su /me: %{http_code}\n" localhost:8080/api/v1/me
```

Atteso: `{"status":"UP"}`; tre edizioni (2024, 2025, 2026); il profilo di **un solo** espositore; `403` per lo staff su `/portal/me`; `401` senza token. Controlla anche che i dati non siano cambiati:

```bash
docker exec arcade-db psql -U postgres -d arcade -At -c "SELECT count(*) FROM core.exhibitor"
```

Atteso: `135`. Scrivi nel resoconto finale cosa è stato provato davvero e cosa no.

- [ ] **Step 8: Aggiorna lo stato della specifica**

In `docs/superpowers/specs/2026-11-13-b2-scheletro-backend-design.md` cambia la riga `**Stato:** da approvare` in `**Stato:** implementata (vedi backend/README.md per cosa è stato provato)`.

- [ ] **Step 9: Commit**

```bash
cd ..
git add backend docs/superpowers/specs
git commit -m "Backend B2: token di sviluppo, script dell'account del backend e README"
```

---

## Autocontrollo del piano

**Copertura della specifica**

| Sezione della specifica | Dove |
|---|---|
| §1 criterio di riuscita | Task 3 (test), Task 4 Step 7 (prova reale) |
| §3 struttura | "Struttura dei file" e Task 1–4 |
| §4 autenticazione e ruoli, token di sviluppo | Task 2 (`JwtService`, `SecurityConfig`), Task 4 (`DevTokenController`) |
| §5 ruolo del database per richiesta, account `arcade_backend` | Task 3 (`ScopedDb`), Task 4 (script) |
| §6 migrazioni | Task 1 (con correzione di §6 nello Step 10) |
| §7 endpoint | Task 2 (`/health`, `/me`), Task 3 (`/editions`, `/portal/me`) |
| §8 errori e log | Task 2 (`error/`, `RequestIdFilter`, pattern dei log in `application.yml`) |
| §9 test | Task 1–4; il test 3 della specifica (espositore su `/editions`) è corretto in `EditionsApiTest` |
| §11 limiti | `backend/README.md` |

**Differenza rispetto alla specifica:** la specifica indicava `IN ROLE arcade_app, arcade_portal` per l'account del backend; il piano aggiunge `NOINHERIT` (senza `SET ROLE` l'account non legge nulla). È una scelta più restrittiva, provata da un test.

**Placeholder:** nessuno. **Coerenza dei tipi:** `ScopedDb.read(DbRole, Integer, Function<JdbcClient,T>)`, `DbRole.forUser(CurrentUser)`, `JwtService.issue/issueClaims`, `ApiException.notFound/forbidden` sono definiti prima di essere usati.

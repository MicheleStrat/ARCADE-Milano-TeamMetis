# BID-06 Portale espositori — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** portale web per gli espositori (Riepilogo, Visite, Contratto) con accesso di prova e un logout che revoca le sessioni sul server.

**Architecture:** il backend registra ogni token in `core.app_session` e un filtro rifiuta le sessioni mancanti, revocate, scadute o inattive; `POST /auth/logout` le revoca tutte. Il frontend Angular tiene il token solo in memoria, usa il backend vero per accesso, logout e profilo, e tre sorgenti con dati demo, sostituibili una alla volta, per contratti, visite e risultati.

**Tech Stack:** Spring Boot 3.5.7, Java 25, PostgreSQL 16, Flyway, JUnit 5, Testcontainers; Angular 21.2 (standalone, signal), RxJS, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-28-bid06-portale-espositori-design.md`

## Global Constraints

- Ramo `task-06`. Commit locali a fine task; **nessun push o PR senza richiesta di Mattia**.
- **Nessuna attribuzione a Claude** nei commit (niente `Co-Authored-By`, niente "Generated with").
- `docs/06-assegnazione-task-bid.md` ha una modifica non committata di un altro lavoro: **non aggiungerla** fino al Task 7. Usa sempre `git add` con percorsi espliciti, mai `git add -A` o `git add .`.
- Angular **21.2** e non 22: la 22 richiede Node `^24.15.0` e sul computer c'è 24.13.0 (controllato il 28/11).
- Token in Angular **solo in memoria**: mai `localStorage`, `sessionStorage`, cookie, URL o log.
- Sessione: durata massima **60 minuti**, inattività **15 minuti**, configurabili.
- Testi dell'interfaccia in italiano. Dato mancante = `—` con una spiegazione; lo zero resta `0`. Importi in euro **IVA esclusa**.
- `discountPct` è una **frazione** (0.05 = 5%); `visitsDeltaPct` e `contractedNetDeltaPct` sono **già percentuali** (12.5 = +12,5%).
- Dati demo chiaramente inventati, con etichetta **"dati demo"**. Niente dati veri di espositori nel repository. I casi "una sola edizione" ed "elenco vuoto" non stanno nei dati demo (non possono convivere con il confronto tra edizioni): li provano i test delle pagine.
- Migrazioni dopo V5 **ripetibili** (`IF NOT EXISTS`).
- I test del backend richiedono Docker avviato.

## Prima di iniziare (blocca solo il Task 1)

Chiedere al BAD quali numeri di migrazione hanno usato (la loro schermata Live cita una `V14`). Il piano usa `V7__app_session.sql`. Se `V7` è occupato, usare il numero indicato nel nome del file, in `SessionSchemaTest` e nella documentazione del Task 2.

## Review Focus

Casi che la specifica implica ma non elenca tra i test. Ognuno ha il suo test nel task indicato.

1. Computer sospeso oltre 15 minuti e poi il mouse si muove: logout, il movimento **non** riattiva la sessione (Task 4).
2. Doppio clic su "Esci" o su "Riprova": **una sola** richiesta di logout (Task 3).
3. La risposta di un logout vecchio arriva dopo un nuovo accesso: **non** chiude la sessione nuova (Task 3).
4. ID espositore vuoto, `0`, negativo, decimale o con lettere: messaggio, **nessuna richiesta** (Task 4).
5. Sconto `0.05` mostrato "5%" e variazione `12.5` mostrata "+12,5%", non scambiati (Task 5).

## Struttura dei file

| File | Compito |
|---|---|
| `database/migrations/V7__app_session.sql` | tabella delle sessioni e permessi |
| `backend/.../security/SessionService.java` | apre, verifica e revoca le sessioni |
| `backend/.../security/SessionFilter.java` | rifiuta le richieste con sessione non valida |
| `backend/.../security/LogoutController.java` | `POST /auth/logout` |
| `frontend/src/app/auth/session.store.ts` | stato della sessione in memoria |
| `frontend/src/app/auth/auth.service.ts` | accesso e logout |
| `frontend/src/app/auth/auth.interceptor.ts` | token sulle richieste, 401, annullamento |
| `frontend/src/app/auth/tab-sync.ts` | avviso alle altre schede |
| `frontend/src/app/auth/inactivity.ts` | timeout e segnale periodico |
| `frontend/src/app/auth/guards.ts`, `restore.ts` | pagine protette, ripristino dalla cache |
| `frontend/src/app/auth/login-page.ts`, `logout-pending.ts` | schermate di accesso e logout non confermato |
| `frontend/src/app/data/models.ts`, `sources.ts`, `demo-data.ts`, `load-rows.ts` | tipi, sorgenti, dati demo, stati di caricamento |
| `frontend/src/app/format/format.ts` | testi di numeri, date e pagamenti |
| `frontend/src/app/shared/ui.ts` | etichetta demo e riquadro di stato |
| `frontend/src/app/pages/shell.ts`, `summary-page.ts`, `visits-page.ts`, `contract-page.ts` | menu e tre pagine |

---

### Task 1: Sessioni sul server

**Files:**
- Create: `database/migrations/V7__app_session.sql`
- Create: `backend/src/main/java/it/arcade/backend/security/SessionService.java`
- Create: `backend/src/main/java/it/arcade/backend/security/SessionFilter.java`
- Modify: `backend/src/main/java/it/arcade/backend/security/JwtService.java`
- Modify: `backend/src/main/java/it/arcade/backend/security/JwtProperties.java`
- Modify: `backend/src/main/java/it/arcade/backend/config/SecurityConfig.java`
- Modify: `backend/src/main/resources/application.yml`
- Test: `backend/src/test/java/it/arcade/backend/db/SessionSchemaTest.java`, `backend/src/test/java/it/arcade/backend/security/SessionApiTest.java`

**Interfaces:**
- Produces: `SessionService.open(UUID id, String subject, Instant expiresAt)`, `boolean touch(Jwt jwt)`, `void revokeAll(String subject)`. `JwtService.issue(...)` e `issueClaims(...)` mantengono la firma e registrano la sessione.

- [ ] **Step 1: Verificare che i test attuali passino**

Run (in `backend/`): `./mvnw test`
Expected: BUILD SUCCESS. Annotare il numero di test eseguiti.

- [ ] **Step 2: Scrivere il test dello schema**

`backend/src/test/java/it/arcade/backend/db/SessionSchemaTest.java`:

```java
package it.arcade.backend.db;

import static org.assertj.core.api.Assertions.assertThat;

import it.arcade.backend.support.ApiTest;
import it.arcade.backend.support.PostgresSupport;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

class SessionSchemaTest extends ApiTest {

    private final JdbcTemplate owner = PostgresSupport.owner();

    private boolean puo(String ruolo, String permesso) {
        return owner.queryForObject("SELECT has_table_privilege(?, 'core.app_session', ?)",
                Boolean.class, ruolo, permesso);
    }

    @Test
    void la_tabella_non_contiene_il_token() {
        List<String> colonne = owner.queryForList("""
                SELECT column_name FROM information_schema.columns
                 WHERE table_schema = 'core' AND table_name = 'app_session'""", String.class);
        assertThat(colonne).containsExactlyInAnyOrder(
                "session_id", "subject", "created_at", "last_seen_at", "expires_at", "revoked_at");
    }

    @Test
    void il_portale_e_l_etl_non_hanno_permessi() {
        for (String ruolo : List.of("arcade_portal", "arcade_etl")) {
            for (String permesso : List.of("SELECT", "INSERT", "UPDATE", "DELETE")) {
                assertThat(puo(ruolo, permesso)).as(ruolo + " " + permesso).isFalse();
            }
        }
    }

    @Test
    void il_backend_non_puo_cancellare_le_sessioni() {
        assertThat(puo("arcade_app", "SELECT")).isTrue();
        assertThat(puo("arcade_app", "INSERT")).isTrue();
        assertThat(puo("arcade_app", "UPDATE")).isTrue();
        assertThat(puo("arcade_app", "DELETE")).isFalse();
    }

    @Test
    void la_migrazione_si_puo_rieseguire() throws Exception {
        String sql = Files.readString(Path.of("../database/migrations/V7__app_session.sql"));
        owner.execute(sql);
        owner.execute(sql);
    }
}
```

- [ ] **Step 3: Scrivere i test delle sessioni**

`backend/src/test/java/it/arcade/backend/security/SessionApiTest.java`:

```java
package it.arcade.backend.security;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import it.arcade.backend.support.ApiTest;
import it.arcade.backend.support.PostgresSupport;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.ResultActions;

class SessionApiTest extends ApiTest {

    @MockitoSpyBean SessionService sessions;

    private String token(String utente) {
        return jwt.issueClaims(utente, List.of("ADMIN"), null, Duration.ofMinutes(60));
    }

    private ResultActions me(String token) throws Exception {
        return mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token));
    }

    private static String utenteNuovo() {
        return "sessione-" + UUID.randomUUID();
    }

    private static void modifica(String assegnazione, String utente) {
        PostgresSupport.owner().update(
                "UPDATE core.app_session SET " + assegnazione + " WHERE subject = ?", utente);
    }

    /** Firma valida, ma senza passare dal servizio: nessuna riga nella tabella. */
    private static String firmatoSenzaSessione(String jti) {
        var key = new SecretKeySpec(
                "chiave-di-prova-chiave-di-prova-0123456789".getBytes(StandardCharsets.UTF_8), "HmacSHA256");
        var claims = JwtClaimsSet.builder().subject("fantasma").issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(600)).claim("roles", List.of("ADMIN"));
        if (jti != null) {
            claims.id(jti);
        }
        return new NimbusJwtEncoder(new ImmutableSecret<>(key)).encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims.build())).getTokenValue();
    }

    @Test
    void un_token_emesso_dal_servizio_funziona() throws Exception {
        me(token(utenteNuovo())).andExpect(status().isOk());
    }

    @Test
    void un_token_firmato_senza_sessione_e_rifiutato() throws Exception {
        me(firmatoSenzaSessione(UUID.randomUUID().toString()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void un_token_senza_jti_o_con_jti_non_valido_e_rifiutato() throws Exception {
        me(firmatoSenzaSessione(null)).andExpect(status().isUnauthorized());
        me(firmatoSenzaSessione("non-un-uuid")).andExpect(status().isUnauthorized());
    }

    @Test
    void una_sessione_revocata_scaduta_o_inattiva_e_rifiutata() throws Exception {
        for (String assegnazione : List.of(
                "revoked_at = now()",
                "expires_at = now() - interval '1 second'",
                "last_seen_at = now() - interval '16 minutes'")) {
            String utente = utenteNuovo();
            String token = token(utente);
            modifica(assegnazione, utente);
            me(token).andExpect(status().isUnauthorized());
        }
    }

    @Test
    void una_richiesta_valida_aggiorna_l_ultima_attivita() throws Exception {
        String utente = utenteNuovo();
        String token = token(utente);
        modifica("last_seen_at = now() - interval '10 minutes'", utente);

        me(token).andExpect(status().isOk());

        Boolean recente = PostgresSupport.owner().queryForObject(
                "SELECT last_seen_at > now() - interval '1 minute' FROM core.app_session WHERE subject = ?",
                Boolean.class, utente);
        org.assertj.core.api.Assertions.assertThat(recente).isTrue();
    }

    @Test
    void se_la_verifica_fallisce_risponde_503_senza_dati() throws Exception {
        String token = token(utenteNuovo());
        doThrow(new DataAccessResourceFailureException("database spento"))
                .when(sessions).touch(any(Jwt.class));

        me(token)
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("SESSION_CHECK_UNAVAILABLE"))
                .andExpect(jsonPath("$.username").doesNotExist());
    }
}
```

- [ ] **Step 4: Verificare che i test falliscano**

Run: `./mvnw test -Dtest='SessionSchemaTest,SessionApiTest'`
Expected: errore di compilazione, `SessionService` non esiste.

- [ ] **Step 5: Scrivere la migrazione**

`database/migrations/V7__app_session.sql`:

```sql
-- Sessioni dei token emessi dal backend: permettono la revoca (logout). Il token NON viene salvato.
-- Ripetibile: Docker la esegue su un volume nuovo e Flyway puo' rieseguirla.
CREATE TABLE IF NOT EXISTS core.app_session (
    session_id    uuid        PRIMARY KEY,
    subject       text        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now(),
    expires_at    timestamptz NOT NULL,
    revoked_at    timestamptz
);

CREATE INDEX IF NOT EXISTS ix_app_session_subject_active
    ON core.app_session (subject) WHERE revoked_at IS NULL;

-- I permessi predefiniti dello schema core darebbero accesso anche a ETL: vanno tolti.
REVOKE ALL ON core.app_session FROM PUBLIC, arcade_portal, arcade_etl, arcade_app;
GRANT SELECT, INSERT, UPDATE ON core.app_session TO arcade_app;
```

- [ ] **Step 6: Scrivere `SessionService`**

```java
package it.arcade.backend.security;

import it.arcade.backend.db.ScopedDb;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

/** Sessioni sul server: un token vale solo finche' la sua sessione e' attiva. */
@Service
public class SessionService {

    private final ScopedDb db;
    private final int idleMinutes;

    public SessionService(ScopedDb db, JwtProperties properties) {
        this.db = db;
        this.idleMinutes = Math.toIntExact(properties.idleMinutes());
    }

    public void open(UUID id, String subject, Instant expiresAt) {
        db.write(jdbc -> jdbc.sql("""
                        INSERT INTO core.app_session (session_id, subject, expires_at)
                        VALUES (:id, :subject, :expires)
                        """)
                .param("id", id)
                .param("subject", subject)
                .param("expires", Timestamp.from(expiresAt))
                .update());
    }

    /**
     * Vero se la sessione del token e' attiva, e in quel caso ne aggiorna l'ultima attivita'. Un solo UPDATE:
     * una richiesta in corso non puo' riattivare una sessione appena revocata.
     */
    public boolean touch(Jwt jwt) {
        UUID id = sessionId(jwt.getId());
        if (id == null || jwt.getSubject() == null) {
            return false;
        }
        return db.write(jdbc -> jdbc.sql("""
                        UPDATE core.app_session SET last_seen_at = now()
                         WHERE session_id = :id AND subject = :subject
                           AND revoked_at IS NULL AND expires_at > now()
                           AND last_seen_at > now() - make_interval(mins => :idle)
                        """)
                .param("id", id)
                .param("subject", jwt.getSubject())
                .param("idle", idleMinutes)
                .update()) == 1;
    }

    public void revokeAll(String subject) {
        db.write(jdbc -> jdbc.sql(
                        "UPDATE core.app_session SET revoked_at = now() WHERE subject = :subject AND revoked_at IS NULL")
                .param("subject", subject)
                .update());
    }

    private static UUID sessionId(String value) {
        if (value == null) {
            return null;
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
```

- [ ] **Step 7: Scrivere `SessionFilter`**

Non annotarlo con `@Component`: Spring Boot lo registrerebbe due volte.

```java
package it.arcade.backend.security;

import it.arcade.backend.error.ProblemWriter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.transaction.TransactionException;
import org.springframework.web.filter.OncePerRequestFilter;

/** Dopo la verifica della firma controlla che la sessione del token sia ancora attiva. */
public class SessionFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(SessionFilter.class);

    private final SessionService sessions;
    private final ProblemWriter problems;

    public SessionFilter(SessionService sessions, ProblemWriter problems) {
        this.sessions = sessions;
        this.problems = problems;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof JwtAuthenticationToken token) {
            boolean active;
            try {
                active = sessions.touch(token.getToken());
            } catch (DataAccessException | TransactionException e) {
                // Nel dubbio non si accetta.
                log.error("Impossibile verificare la sessione", e);
                SecurityContextHolder.clearContext();
                problems.write(response, HttpStatus.SERVICE_UNAVAILABLE, "SESSION_CHECK_UNAVAILABLE",
                        "Verifica della sessione non disponibile", null);
                return;
            }
            if (!active) {
                SecurityContextHolder.clearContext();
                response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Bearer");
                problems.write(response, HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED",
                        "Token mancante o non valido", null);
                return;
            }
        }
        chain.doFilter(request, response);
    }
}
```

- [ ] **Step 8: Collegare proprietà, emissione e filtro**

`JwtProperties.java`:

```java
@ConfigurationProperties(prefix = "arcade.jwt")
public record JwtProperties(String secret, @DefaultValue("60") long ttlMinutes,
        @DefaultValue("15") long idleMinutes) {}
```

`JwtService.java`: aggiungere `import java.util.UUID;`, il campo `private final SessionService sessions;`, cambiare la firma del costruttore in `public JwtService(JwtProperties properties, SessionService sessions)` con `this.sessions = sessions;`, e in `issueClaims` sostituire dalla riga `JwtClaimsSet.Builder claims` fino al `return` con:

```java
        UUID sessionId = UUID.randomUUID();
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .id(sessionId.toString())
                .subject(username)
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .claim("roles", List.copyOf(roles));
        if (exhibitorId != null) {
            claims.claim("exhibitor_id", exhibitorId);
        }
        JwsHeader header = JwsHeader.with(MacAlgorithm.HS256).build();
        String token = encoder.encode(JwtEncoderParameters.from(header, claims.build())).getTokenValue();
        // Se la registrazione fallisce l'eccezione sale e il token non viene restituito.
        sessions.open(sessionId, username, expiresAt);
        return token;
```

`SecurityConfig.java`: aggiungere gli import `it.arcade.backend.security.SessionFilter`, `it.arcade.backend.security.SessionService`, `org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter`; cambiare la firma in `SecurityFilterChain filterChain(HttpSecurity http, ProblemWriter problems, SessionService sessions)`; dopo il blocco `.oauth2ResourceServer(...)`, prima del `;`, aggiungere:

```java
                .addFilterAfter(new SessionFilter(sessions, problems), BearerTokenAuthenticationFilter.class)
```

`application.yml`, sotto `arcade.jwt`:

```yaml
    ttl-minutes: 60
    idle-minutes: 15
```

- [ ] **Step 9: Eseguire tutti i test**

Run: `./mvnw test`
Expected: BUILD SUCCESS, con i test del Step 1 più quelli nuovi.

- [ ] **Step 10: Commit**

```bash
git add database/migrations/V7__app_session.sql backend/src
git commit -m "BID-06: sessioni sul server, i token revocati, scaduti o inattivi sono rifiutati"
```

---

### Task 2: Logout, accesso di prova e contratto API

**Files:**
- Create: `backend/src/main/java/it/arcade/backend/security/LogoutController.java`
- Modify: `backend/src/main/java/it/arcade/backend/security/DevTokenController.java`
- Modify: `backend/src/main/java/it/arcade/backend/config/SecurityConfig.java`
- Modify: `docs/api/openapi.yaml`, `docs/api/README.md`, `docs/08-decisioni-condivise.md`, `backend/README.md`
- Test: `backend/src/test/java/it/arcade/backend/security/LogoutApiTest.java`

**Interfaces:**
- Consumes: `SessionService.revokeAll(String subject)`.
- Produces: `POST /api/v1/auth/logout` → 204; `POST /api/v1/dev/token` con ruolo `EXHIBITOR` → `sub` = `espositore-<id>`.

- [ ] **Step 1: Scrivere i test**

```java
package it.arcade.backend.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.support.ApiTest;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.ResultActions;

@ActiveProfiles("dev")
class LogoutApiTest extends ApiTest {

    @Autowired ObjectMapper json;

    private String accesso(String nome, int espositore) throws Exception {
        String risposta = mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "username", nome, "roles", List.of("EXHIBITOR"), "exhibitorId", espositore))))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return json.readTree(risposta).get("accessToken").asText();
    }

    private ResultActions chiama(String percorso, String token) throws Exception {
        return mvc.perform(get(percorso).header(HttpHeaders.AUTHORIZATION, "Bearer " + token));
    }

    private ResultActions logout(String token) throws Exception {
        return mvc.perform(post("/auth/logout").header(HttpHeaders.AUTHORIZATION, "Bearer " + token));
    }

    @Test
    void dopo_il_logout_il_vecchio_token_e_rifiutato() throws Exception {
        String token = accesso("primo", exhibitorId("ESP901"));
        chiama("/portal/me", token).andExpect(status().isOk());

        logout(token).andExpect(status().isNoContent());

        chiama("/me", token).andExpect(status().isUnauthorized());
        chiama("/portal/me", token).andExpect(status().isUnauthorized());
    }

    @Test
    void il_logout_chiude_anche_le_altre_sessioni_dello_stesso_espositore() throws Exception {
        int alfa = exhibitorId("ESP901");
        String uno = accesso("un-nome", alfa);
        String due = accesso("un-altro-nome", alfa);

        logout(uno).andExpect(status().isNoContent());

        chiama("/portal/me", due).andExpect(status().isUnauthorized());
    }

    @Test
    void il_logout_non_tocca_gli_altri_utenti() throws Exception {
        String alfa = accesso("a", exhibitorId("ESP901"));
        String beta = accesso("b", exhibitorId("ESP902"));

        logout(alfa).andExpect(status().isNoContent());

        chiama("/portal/me", beta).andExpect(status().isOk());
    }

    @Test
    void lo_stesso_espositore_ha_sempre_lo_stesso_utente() throws Exception {
        int alfa = exhibitorId("ESP901");
        for (String nome : List.of("pippo", "pluto")) {
            chiama("/me", accesso(nome, alfa))
                    .andExpect(status().isOk())
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers
                            .jsonPath("$.username").value("espositore-" + alfa));
        }
    }

    @Test
    void il_logout_senza_token_o_ripetuto_risponde_401() throws Exception {
        mvc.perform(post("/auth/logout")).andExpect(status().isUnauthorized());
        String token = jwt.issueClaims("logout-" + UUID.randomUUID(), List.of("ADMIN"), null, Duration.ofMinutes(5));
        logout(token).andExpect(status().isNoContent());
        logout(token).andExpect(status().isUnauthorized());
    }

    @Test
    void il_logout_ignora_un_utente_passato_dal_client() throws Exception {
        String vittima = "vittima-" + UUID.randomUUID();
        String tokenVittima = jwt.issueClaims(vittima, List.of("ADMIN"), null, Duration.ofMinutes(5));
        String altro = jwt.issueClaims("altro-" + UUID.randomUUID(), List.of("ADMIN"), null, Duration.ofMinutes(5));

        mvc.perform(post("/auth/logout?subject=" + vittima)
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + altro)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"subject\":\"" + vittima + "\"}"))
                .andExpect(status().isNoContent());

        assertThat(chiama("/me", tokenVittima).andReturn().getResponse().getStatus()).isEqualTo(200);
    }
}
```

- [ ] **Step 2: Verificare il fallimento**

Run: `./mvnw test -Dtest=LogoutApiTest`
Expected: FAIL (il logout risponde 403 e `username` è il nome inviato).

- [ ] **Step 3: Scrivere il controller**

```java
package it.arcade.backend.security;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class LogoutController {

    private final SessionService sessions;

    public LogoutController(SessionService sessions) {
        this.sessions = sessions;
    }

    /** Chiude tutte le sessioni dell'utente del token. Non legge parametri ne' corpo. */
    @PostMapping("/auth/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@AuthenticationPrincipal Jwt jwt) {
        sessions.revokeAll(jwt.getSubject());
    }
}
```

In `SecurityConfig`, subito dopo la riga di `/me`:

```java
                        .requestMatchers(HttpMethod.POST, "/auth/logout").authenticated()
```

In `DevTokenController`, sostituire la riga `String token = jwt.issue(...)` con:

```java
        // Per un espositore l'utente dipende dall'id: cosi' il logout chiude tutte le sue sessioni.
        String subject = roles.contains(Role.EXHIBITOR) && request.exhibitorId() != null
                ? "espositore-" + request.exhibitorId()
                : request.username();
        String token = jwt.issue(subject, roles, request.exhibitorId());
```

- [ ] **Step 4: Eseguire tutti i test**

Run: `./mvnw test`
Expected: BUILD SUCCESS.

- [ ] **Step 5: Aggiornare la documentazione**

In `docs/api/openapi.yaml`, prima di `  /me:`:

```yaml
  /auth/logout:
    post:
      tags: [Sistema]
      operationId: logout
      summary: Chiude tutte le sessioni dell'utente autenticato
      description: |
        Revoca sul server tutte le sessioni attive dell'utente (`sub`) del token. Non ha parametri ne' corpo.
        Dopo la risposta i token gia' emessi per quell'utente ricevono 401.
      x-roles: [ADMIN, COMMERCIAL, OPS, EXHIBITOR, SCANNER, BI_READER]
      responses:
        '204':
          description: Sessioni revocate
        '401':
          $ref: '#/components/responses/Unauthorized'
```

In `docs/api/README.md` aggiornare i conteggi: 59 operazioni su 54 percorsi.

In `docs/08-decisioni-condivise.md` aggiungere in fondo:

```markdown
## Sessioni e logout (BID-06)

**Data:** 28 novembre 2026 · **Responsabile:** Mattia Billong · **Stato:** implementata nel backend; **da comunicare** al BAD e a chi usa le API.

- Ogni token emesso dal backend ha una sessione in `core.app_session` (migrazione `V7`). Il token non viene salvato.
- Una richiesta è accettata solo se la sessione è attiva: non revocata, non scaduta (60 minuti) e usata da meno di 15 minuti. Se la verifica non è possibile il backend risponde 503.
- `POST /auth/logout` chiude tutte le sessioni dell'utente.
- I token emessi prima di questa modifica non funzionano più.
- Con un fornitore di identità esterno (per esempio Entra ID) il logout va riprogettato.
```

In `backend/README.md` aggiungere sotto "Provarlo": `POST /api/v1/auth/logout` chiude le sessioni; dopo, lo stesso token riceve 401. Il database ha bisogno della migrazione `V7`, che Flyway applica all'avvio.

- [ ] **Step 6: Commit**

```bash
git add backend/src backend/README.md docs/api/openapi.yaml docs/api/README.md docs/08-decisioni-condivise.md
git commit -m "BID-06: logout che revoca tutte le sessioni dell'utente"
```

---

### Task 3: Progetto Angular, sessione e logout

**Files:**
- Create: `frontend/` (progetto Angular), `frontend/proxy.conf.json`
- Create: `frontend/src/app/auth/session.store.ts`, `auth.service.ts`, `auth.interceptor.ts`, `tab-sync.ts`
- Test: `frontend/src/app/auth/auth.spec.ts`

**Interfaces:**
- Produces:
  - `SessionStore`: `status: Signal<'anonymous'|'authenticated'|'logout-pending'>`, `profile: WritableSignal<PortalProfile|null>`, `notice: WritableSignal<Notice>`, `exhibitorId: number|null`, `token: string|null`, `ended$: Observable<void>`, `start(token, exhibitorId)`, `lock()`, `clear(notice)`.
  - `AuthService`: `login(exhibitorId: number): Promise<boolean>`, `logout(successNotice?: Notice): Promise<void>`, `retryLogout(): Promise<void>`.
  - `authInterceptor: HttpInterceptorFn`; costante `API = '/api/v1'`.
  - `CHANNEL_FACTORY: InjectionToken<() => ChannelLike>`.

- [ ] **Step 1: Creare il progetto**

Dalla radice del repository:

```bash
npx --yes @angular/cli@21.2 new arcade-portale --directory frontend --routing --style css --ssr false --skip-git --package-manager npm --ai-config none --defaults
```

Eliminare `frontend/src/app/app.spec.ts`. Creare `frontend/proxy.conf.json`:

```json
{
  "/api": { "target": "http://localhost:8080", "secure": false }
}
```

In `frontend/angular.json`, in `projects.arcade-portale.architect.serve`, aggiungere `"options": { "proxyConfig": "proxy.conf.json" }`.

Run: `git status --short frontend | head` e `git check-ignore frontend/node_modules`
Expected: `node_modules` ignorato; `.angular/` non compare tra i file nuovi (se compare, aggiungere `.angular/` al `.gitignore` della radice).

- [ ] **Step 2: Scrivere i test**

`frontend/src/app/auth/auth.spec.ts`:

```ts
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { authInterceptor } from './auth.interceptor';
import { AuthService } from './auth.service';
import { SessionStore } from './session.store';
import { CHANNEL_FACTORY, ChannelLike } from './tab-sync';

const PROFILE = { exhibitorId: 7, exhibitorCode: 'DEMO7', legalName: 'Demo Srl', categoryName: 'Demo' };

describe('accesso e logout', () => {
  let auth: AuthService;
  let session: SessionStore;
  let http: HttpClient;
  let server: HttpTestingController;
  let sent: unknown[];
  let channel: ChannelLike;

  beforeEach(() => {
    localStorage.clear();
    sessionStorage.clear();
    sent = [];
    channel = { onmessage: null, postMessage: (m) => sent.push(m), close: () => {} };
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: CHANNEL_FACTORY, useValue: () => channel },
      ],
    });
    auth = TestBed.inject(AuthService);
    session = TestBed.inject(SessionStore);
    http = TestBed.inject(HttpClient);
    server = TestBed.inject(HttpTestingController);
  });

  afterEach(() => server.verify());

  const tick = () => new Promise((resolve) => setTimeout(resolve));

  async function enter(token = 'token-segreto') {
    const done = auth.login(7);
    server.expectOne('/api/v1/dev/token').flush({ accessToken: token });
    await tick();
    const profile = server.expectOne('/api/v1/portal/me');
    expect(profile.request.headers.get('Authorization')).toBe(`Bearer ${token}`);
    profile.flush(PROFILE);
    expect(await done).toBe(true);
  }

  it('il token non finisce negli archivi del browser', async () => {
    await enter();
    const stored = JSON.stringify([{ ...localStorage }, { ...sessionStorage }]) + document.cookie;
    expect(stored).not.toContain('token-segreto');
  });

  it('con 204 cancella token e dati e avvisa le altre schede', async () => {
    await enter();
    const done = auth.logout();
    expect(session.status()).toBe('logout-pending');
    expect(session.profile()).toBeNull();
    server.expectOne('/api/v1/auth/logout').flush(null, { status: 204, statusText: 'No Content' });
    await done;
    expect(session.status()).toBe('anonymous');
    expect(session.token).toBeNull();
    expect(session.notice()).toBe('logged-out');
    expect(sent).toEqual([{ type: 'logout', exhibitorId: 7 }]);
  });

  it('se il server non risponde resta "non confermato" e Riprova funziona', async () => {
    await enter();
    const first = auth.logout();
    server.expectOne('/api/v1/auth/logout').error(new ProgressEvent('error'));
    await first;
    expect(session.status()).toBe('logout-pending');
    expect(session.notice()).not.toBe('logged-out');
    expect(sent).toEqual([]);

    const second = auth.retryLogout();
    const retry = server.expectOne('/api/v1/auth/logout');
    expect(retry.request.headers.get('Authorization')).toBe('Bearer token-segreto');
    retry.flush(null, { status: 204, statusText: 'No Content' });
    await second;
    expect(session.status()).toBe('anonymous');
  });

  it('con 401 dice "sessione terminata" e non dichiara chiuse le altre schede', async () => {
    await enter();
    const done = auth.logout();
    server.expectOne('/api/v1/auth/logout').flush(null, { status: 401, statusText: 'Unauthorized' });
    await done;
    expect(session.notice()).toBe('ended');
    expect(session.token).toBeNull();
    expect(sent).toEqual([]);
  });

  it('doppio clic: una sola richiesta di logout', async () => {
    await enter();
    const done = auth.logout();
    void auth.logout();
    void auth.retryLogout();
    server.expectOne('/api/v1/auth/logout').flush(null, { status: 204, statusText: 'No Content' });
    await done;
  });

  it('una risposta in ritardo dopo il logout non arriva alla pagina', async () => {
    await enter();
    const received: unknown[] = [];
    http.get('/api/v1/editions').subscribe((v) => received.push(v));
    const slow = server.expectOne('/api/v1/editions');
    const done = auth.logout();
    expect(slow.cancelled).toBe(true);
    expect(received).toEqual([]);
    server.expectOne('/api/v1/auth/logout').flush(null, { status: 204, statusText: 'No Content' });
    await done;
  });

  it('la risposta di un logout vecchio non chiude la sessione nuova', async () => {
    await enter('vecchio');
    const done = auth.logout();
    const old = server.expectOne('/api/v1/auth/logout');
    session.clear('ended'); // per esempio un avviso da un'altra scheda
    await enter('nuovo');
    old.flush(null, { status: 204, statusText: 'No Content' });
    await done;
    expect(session.status()).toBe('authenticated');
    expect(session.token).toBe('nuovo');
  });

  it('un 401 su una richiesta qualunque cancella token e dati', async () => {
    await enter();
    http.get('/api/v1/me').subscribe({ error: () => {} });
    server.expectOne('/api/v1/me').flush(null, { status: 401, statusText: 'Unauthorized' });
    expect(session.status()).toBe('anonymous');
    expect(session.token).toBeNull();
    expect(session.profile()).toBeNull();
  });

  it('il token non viene inviato fuori dalle API del portale', async () => {
    await enter();
    http.get('https://esempio.test/api/v1/me').subscribe();
    const external = server.expectOne('https://esempio.test/api/v1/me');
    expect(external.request.headers.has('Authorization')).toBe(false);
    external.flush({});
  });

  it('profilo non trovato: esegue il logout e lo spiega', async () => {
    const done = auth.login(999);
    server.expectOne('/api/v1/dev/token').flush({ accessToken: 't' });
    await tick();
    server.expectOne('/api/v1/portal/me').flush(null, { status: 404, statusText: 'Not Found' });
    await tick();
    server.expectOne('/api/v1/auth/logout').flush(null, { status: 204, statusText: 'No Content' });
    expect(await done).toBe(false);
    expect(session.notice()).toBe('not-found');
  });

  it("l'avviso di un'altra scheda chiude solo lo stesso espositore", async () => {
    await enter();
    channel.onmessage!({ data: { type: 'logout', exhibitorId: 8 } });
    expect(session.status()).toBe('authenticated');
    channel.onmessage!({ data: { type: 'logout', exhibitorId: 7 } });
    expect(session.status()).toBe('anonymous');
    expect(session.notice()).toBe('ended');
  });
});
```

- [ ] **Step 3: Verificare il fallimento**

Run (in `frontend/`): `npx ng test --watch=false`
Expected: FAIL, i file importati non esistono.

- [ ] **Step 4: Scrivere lo stato della sessione**

`session.store.ts`:

```ts
import { Injectable, signal } from '@angular/core';
import { Subject } from 'rxjs';

export type SessionStatus = 'anonymous' | 'authenticated' | 'logout-pending';
export type Notice = 'logged-out' | 'ended' | 'not-found' | 'login-failed' | null;

export interface PortalProfile {
  exhibitorId: number;
  exhibitorCode: string;
  legalName: string;
  categoryName: string;
}

/** Stato della sessione, solo in memoria: ricaricando la pagina si rifà l'accesso. */
@Injectable({ providedIn: 'root' })
export class SessionStore {
  #token: string | null = null;
  readonly #status = signal<SessionStatus>('anonymous');
  readonly #ended = new Subject<void>();

  readonly status = this.#status.asReadonly();
  readonly profile = signal<PortalProfile | null>(null);
  readonly notice = signal<Notice>(null);
  readonly ended$ = this.#ended.asObservable();
  exhibitorId: number | null = null;

  get token(): string | null {
    return this.#token;
  }

  start(token: string, exhibitorId: number): void {
    this.#token = token;
    this.exhibitorId = exhibitorId;
    this.notice.set(null);
    this.#status.set('authenticated');
  }

  /** Logout in corso: i dati spariscono, il token resta solo per chiamare il logout. */
  lock(): void {
    this.#status.set('logout-pending');
    this.profile.set(null);
    this.#ended.next();
  }

  clear(notice: Notice): void {
    if (this.#status() === 'anonymous') return;
    this.#token = null;
    this.exhibitorId = null;
    this.profile.set(null);
    this.notice.set(notice);
    this.#status.set('anonymous');
    this.#ended.next();
  }
}
```

- [ ] **Step 5: Scrivere schede, interceptor e servizio**

`tab-sync.ts`:

```ts
import { Injectable, InjectionToken, inject } from '@angular/core';
import { SessionStore } from './session.store';

export interface ChannelLike {
  onmessage: ((event: { data: unknown }) => void) | null;
  postMessage(message: unknown): void;
  close(): void;
}

export const CHANNEL_FACTORY = new InjectionToken<() => ChannelLike>('canale tra schede', {
  providedIn: 'root',
  factory: () => () => new BroadcastChannel('arcade-portale-auth') as unknown as ChannelLike,
});

/** Avvisa le altre schede di un logout confermato. Il token non viene mai trasmesso. */
@Injectable({ providedIn: 'root' })
export class TabSync {
  private readonly session = inject(SessionStore);
  private readonly channel = inject(CHANNEL_FACTORY)();

  constructor() {
    this.channel.onmessage = ({ data }) => {
      const message = data as { type?: string; exhibitorId?: number };
      if (message?.type === 'logout' && message.exhibitorId === this.session.exhibitorId) {
        this.session.clear('ended');
      }
    };
  }

  announceLogout(exhibitorId: number): void {
    this.channel.postMessage({ type: 'logout', exhibitorId });
  }
}
```

`auth.interceptor.ts`:

```ts
import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { EMPTY, catchError, takeUntil, throwError } from 'rxjs';
import { SessionStore } from './session.store';

export const API = '/api/v1';

export const authInterceptor: HttpInterceptorFn = (request, next) => {
  if (!request.url.startsWith(`${API}/`) || request.url === `${API}/dev/token`) return next(request);

  const session = inject(SessionStore);
  const isLogout = request.url === `${API}/auth/logout`;
  const status = session.status();
  const allowed = status === 'authenticated' || (isLogout && status === 'logout-pending');
  if (!allowed) return EMPTY;

  const authorized = request.clone({ setHeaders: { Authorization: `Bearer ${session.token}` } });
  if (isLogout) return next(authorized);

  return next(authorized).pipe(
    // Alla fine della sessione la richiesta si annulla: una risposta in ritardo non arriva alla pagina.
    takeUntil(session.ended$),
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse && error.status === 401) session.clear('ended');
      return throwError(() => error);
    }),
  );
};
```

`auth.service.ts`:

```ts
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';
import { API } from './auth.interceptor';
import { Notice, PortalProfile, SessionStore } from './session.store';
import { TabSync } from './tab-sync';

const LOGOUT_TIMEOUT_MS = 10_000;

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly session = inject(SessionStore);
  private readonly tabs = inject(TabSync);
  private sendingToken: string | null = null;
  private successNotice: Notice = 'logged-out';

  /** Accesso di prova: esiste solo se il backend gira con il profilo dev. */
  async login(exhibitorId: number): Promise<boolean> {
    try {
      const response = await firstValueFrom(
        this.http.post<{ accessToken: string }>(`${API}/dev/token`, {
          username: 'portale',
          roles: ['EXHIBITOR'],
          exhibitorId,
        }),
      );
      this.session.start(response.accessToken, exhibitorId);
    } catch {
      this.session.notice.set('login-failed');
      return false;
    }
    try {
      this.session.profile.set(await firstValueFrom(this.http.get<PortalProfile>(`${API}/portal/me`)));
      return true;
    } catch (error) {
      const notFound = error instanceof HttpErrorResponse && error.status === 404;
      await this.logout(notFound ? 'not-found' : 'login-failed');
      return false;
    }
  }

  async logout(successNotice: Notice = 'logged-out'): Promise<void> {
    if (this.session.status() !== 'authenticated') return;
    this.successNotice = successNotice;
    this.session.lock();
    await this.send();
  }

  async retryLogout(): Promise<void> {
    if (this.session.status() === 'logout-pending') await this.send();
  }

  private async send(): Promise<void> {
    const token = this.session.token;
    if (this.sendingToken === token) return;
    this.sendingToken = token;
    try {
      await firstValueFrom(this.http.post(`${API}/auth/logout`, null).pipe(timeout(LOGOUT_TIMEOUT_MS)));
      if (this.session.token !== token) return; // risposta di una sessione vecchia
      const exhibitorId = this.session.exhibitorId!;
      this.session.clear(this.successNotice);
      this.tabs.announceLogout(exhibitorId);
    } catch (error) {
      if (this.session.token !== token) return;
      if (error instanceof HttpErrorResponse && error.status === 401) this.session.clear('ended');
      // altrimenti resta "logout non confermato"
    } finally {
      if (this.sendingToken === token) this.sendingToken = null;
    }
  }
}
```

- [ ] **Step 6: Eseguire i test**

Run: `npx ng test --watch=false`
Expected: PASS, 11 test.

- [ ] **Step 7: Commit**

```bash
git add frontend .gitignore
git commit -m "BID-06: progetto Angular con sessione in memoria e logout confermato dal server"
```

---

### Task 4: Pagine protette, inattività e schermate di accesso

**Files:**
- Create: `frontend/src/app/auth/guards.ts`, `restore.ts`, `inactivity.ts`, `login-page.ts`, `logout-pending.ts`
- Create: `frontend/src/app/pages/shell.ts`, `summary-page.ts`, `visits-page.ts`, `contract-page.ts` (queste tre con il solo titolo, completate al Task 6)
- Modify: `frontend/src/app/app.ts`, `app.routes.ts`, `app.config.ts`, `frontend/src/main.ts`
- Delete: `frontend/src/app/app.html`, `app.css`
- Test: `frontend/src/app/auth/protection.spec.ts`

**Interfaces:**
- Consumes: `SessionStore`, `AuthService`, `API`, `authInterceptor`, `CHANNEL_FACTORY`.
- Produces: `sessionGuard`, `guestGuard`; `InactivityWatcher.start()/stop()`; `reloadOnRestore(target, reload)`; `parseExhibitorId(text: string): number | null`; rotte `/accesso`, `/riepilogo`, `/visite`, `/contratto`; classi `SummaryPage`, `VisitsPage`, `ContractPage`.

- [ ] **Step 1: Scrivere i test**

`protection.spec.ts`:

```ts
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { routes } from '../app.routes';
import { authInterceptor } from './auth.interceptor';
import { IDLE_LIMIT_MS, InactivityWatcher } from './inactivity';
import { parseExhibitorId } from './login-page';
import { reloadOnRestore } from './restore';
import { SessionStore } from './session.store';
import { CHANNEL_FACTORY } from './tab-sync';

describe('protezione delle pagine', () => {
  let session: SessionStore;
  let server: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes),
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: CHANNEL_FACTORY, useValue: () => ({ onmessage: null, postMessage() {}, close() {} }) },
      ],
    });
    session = TestBed.inject(SessionStore);
    server = TestBed.inject(HttpTestingController);
  });

  it('senza sessione le pagine portano all’accesso', async () => {
    const router = TestBed.inject(Router);
    for (const path of ['/riepilogo', '/visite', '/contratto', '/non-esiste']) {
      await router.navigateByUrl(path);
      expect(router.url).toBe('/accesso');
    }
  });

  it('con la sessione si entra, dopo il logout non più', async () => {
    const router = TestBed.inject(Router);
    session.start('t', 7);
    await router.navigateByUrl('/visite');
    expect(router.url).toBe('/visite');
    session.clear('logged-out');
    await router.navigateByUrl('/contratto');
    expect(router.url).toBe('/accesso');
  });

  it('una pagina ripristinata dalla cache del browser viene ricaricata', () => {
    const target = new EventTarget();
    let reloads = 0;
    reloadOnRestore(target, () => reloads++);
    target.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: false }));
    target.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: true }));
    expect(reloads).toBe(1);
  });

  it('ID espositore: accetta solo interi positivi', () => {
    expect(parseExhibitorId(' 12 ')).toBe(12);
    for (const bad of ['', '0', '-3', '1.5', '12abc', '1e3', '99999999999']) {
      expect(parseExhibitorId(bad)).toBeNull();
    }
  });

  describe('inattività', () => {
    let watcher: InactivityWatcher;

    beforeEach(() => {
      vi.useFakeTimers();
      session.start('t', 7);
      watcher = TestBed.inject(InactivityWatcher);
      watcher.start();
    });

    afterEach(() => {
      watcher.stop();
      vi.useRealTimers();
    });

    it('dopo 15 minuti senza attività esegue il logout', () => {
      vi.advanceTimersByTime(IDLE_LIMIT_MS + 5_000);
      server.expectOne('/api/v1/auth/logout');
      server.expectNone('/api/v1/me');
    });

    it('segnale periodico solo dopo attività, al massimo una volta al minuto', () => {
      vi.advanceTimersByTime(3 * 60_000);
      server.expectNone('/api/v1/me');
      document.dispatchEvent(new Event('keydown'));
      vi.advanceTimersByTime(5_000);
      server.expectOne('/api/v1/me').flush({});
      document.dispatchEvent(new Event('keydown'));
      vi.advanceTimersByTime(30_000);
      server.expectNone('/api/v1/me');
      vi.advanceTimersByTime(35_000);
      server.expectOne('/api/v1/me').flush({});
    });

    it('dopo la sospensione del computer il mouse non riattiva la sessione', () => {
      vi.setSystemTime(Date.now() + IDLE_LIMIT_MS + 1_000); // il tempo passa senza timer
      document.dispatchEvent(new Event('mousemove'));
      expect(session.status()).toBe('logout-pending');
      server.expectOne('/api/v1/auth/logout');
    });
  });
});
```

- [ ] **Step 2: Verificare il fallimento**

Run: `npx ng test --watch=false`
Expected: FAIL, i moduli nuovi non esistono.

- [ ] **Step 3: Scrivere guardie, ripristino e inattività**

`guards.ts`:

```ts
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SessionStore } from './session.store';

export const sessionGuard: CanActivateFn = () =>
  inject(SessionStore).status() === 'authenticated' || inject(Router).parseUrl('/accesso');

export const guestGuard: CanActivateFn = () =>
  inject(SessionStore).status() !== 'authenticated' || inject(Router).parseUrl('/riepilogo');
```

`restore.ts`:

```ts
/** La cache "indietro/avanti" conserva la memoria della pagina: ricaricando si perdono token e dati. */
export function reloadOnRestore(target: EventTarget, reload: () => void): void {
  target.addEventListener('pageshow', (event) => {
    if ((event as PageTransitionEvent).persisted) reload();
  });
}
```

`inactivity.ts`:

```ts
import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { API } from './auth.interceptor';
import { AuthService } from './auth.service';

export const IDLE_LIMIT_MS = 15 * 60_000;
const PING_EVERY_MS = 60_000;
const CHECK_EVERY_MS = 5_000;
const EVENTS = ['mousemove', 'mousedown', 'keydown', 'touchstart', 'wheel'];

/**
 * Logout dopo 15 minuti senza attività. Se l'utente è attivo manda GET /me, al massimo una volta al minuto,
 * perché il server non consideri inattivo chi sta leggendo.
 */
@Injectable({ providedIn: 'root' })
export class InactivityWatcher {
  private readonly auth = inject(AuthService);
  private readonly http = inject(HttpClient);
  private timer: ReturnType<typeof setInterval> | undefined;
  private lastActivity = 0;
  private lastPing = 0;
  private activeSincePing = false;

  private readonly onActivity = () => {
    // Prima il controllo: dopo una sospensione un movimento non deve riattivare la sessione.
    if (this.expired()) {
      void this.auth.logout();
      return;
    }
    this.lastActivity = Date.now();
    this.activeSincePing = true;
  };

  start(): void {
    this.stop();
    this.lastActivity = this.lastPing = Date.now();
    this.activeSincePing = false;
    for (const name of EVENTS) document.addEventListener(name, this.onActivity, { passive: true });
    this.timer = setInterval(() => this.check(), CHECK_EVERY_MS);
  }

  stop(): void {
    clearInterval(this.timer);
    for (const name of EVENTS) document.removeEventListener(name, this.onActivity);
  }

  private expired(): boolean {
    return Date.now() - this.lastActivity >= IDLE_LIMIT_MS;
  }

  private check(): void {
    if (this.expired()) {
      void this.auth.logout();
    } else if (this.activeSincePing && Date.now() - this.lastPing >= PING_EVERY_MS) {
      this.activeSincePing = false;
      this.lastPing = Date.now();
      this.http.get(`${API}/me`).subscribe({ error: () => {} });
    }
  }
}
```

- [ ] **Step 4: Scrivere schermate, menu e rotte**

`login-page.ts`:

```ts
import { Component, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';
import { Notice, SessionStore } from './session.store';

export function parseExhibitorId(text: string): number | null {
  const value = text.trim();
  return /^[1-9]\d{0,8}$/.test(value) ? Number(value) : null;
}

const MESSAGES: Record<NonNullable<Notice>, string> = {
  'logged-out': 'Sei uscito. Le tue sessioni sono state chiuse.',
  ended: 'Sessione terminata. Accedi di nuovo.',
  'not-found': 'Espositore non trovato.',
  'login-failed': 'Accesso non riuscito. Controlla che il backend sia avviato con il profilo dev.',
};

@Component({
  selector: 'app-login-page',
  template: `
    <main class="center">
      <form class="panel login" (submit)="submit($event, field.value)">
        <h1>Portale espositori</h1>
        <p class="warning"><strong>Accesso di prova.</strong> Non chiede una password: serve solo per lo sviluppo.</p>
        @if (session.notice(); as notice) {
          <p role="status">{{ messages[notice] }}</p>
        }
        <label for="exhibitor">ID dell’espositore di test</label>
        <input #field id="exhibitor" inputmode="numeric" autocomplete="off" />
        @if (invalid()) {
          <p role="alert">Inserisci un numero intero maggiore di zero.</p>
        }
        <button class="primary" type="submit" [disabled]="busy()">Entra</button>
      </form>
    </main>
  `,
})
export class LoginPage {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  readonly session = inject(SessionStore);
  readonly messages = MESSAGES;
  readonly busy = signal(false);
  readonly invalid = signal(false);

  async submit(event: Event, text: string): Promise<void> {
    event.preventDefault();
    const id = parseExhibitorId(text);
    this.invalid.set(id === null);
    if (id === null || this.busy()) return;
    this.busy.set(true);
    const entered = await this.auth.login(id);
    this.busy.set(false);
    if (entered) await this.router.navigateByUrl('/riepilogo');
  }
}
```

`logout-pending.ts`:

```ts
import { Component, inject, signal } from '@angular/core';
import { AuthService } from './auth.service';

@Component({
  selector: 'app-logout-pending',
  template: `
    <main class="center">
      <section class="panel login" role="alert">
        <h1>Logout non confermato</h1>
        <p>I tuoi dati sono nascosti, ma il server non ha ancora confermato la chiusura della sessione.</p>
        <p>Se chiudi la pagina adesso, la sessione può restare aperta fino alla scadenza.</p>
        <button class="primary" type="button" [disabled]="busy()" (click)="retry()">Riprova</button>
      </section>
    </main>
  `,
})
export class LogoutPending {
  private readonly auth = inject(AuthService);
  readonly busy = signal(false);

  async retry(): Promise<void> {
    this.busy.set(true);
    await this.auth.retryLogout();
    this.busy.set(false);
  }
}
```

`pages/shell.ts`:

```ts
import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from '../auth/auth.service';
import { SessionStore } from '../auth/session.store';

@Component({
  selector: 'app-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    @if (session.status() === 'authenticated') {
      <header class="topbar">
        <strong>{{ session.profile()?.legalName }}</strong>
        <nav class="pills" aria-label="Sezioni">
          <a routerLink="/riepilogo" routerLinkActive="active" ariaCurrentWhenActive="page">Riepilogo</a>
          <a routerLink="/visite" routerLinkActive="active" ariaCurrentWhenActive="page">Visite</a>
          <a routerLink="/contratto" routerLinkActive="active" ariaCurrentWhenActive="page">Contratto</a>
        </nav>
        <button type="button" (click)="auth.logout()">Esci</button>
      </header>
      <main class="content"><router-outlet /></main>
    }
  `,
})
export class Shell {
  readonly auth = inject(AuthService);
  readonly session = inject(SessionStore);
}
```

`pages/summary-page.ts` (provvisorio fino al Task 6):

```ts
import { Component } from '@angular/core';

@Component({ selector: 'app-summary-page', template: `<h1>Riepilogo</h1>` })
export class SummaryPage {}
```

`pages/visits-page.ts`:

```ts
import { Component } from '@angular/core';

@Component({ selector: 'app-visits-page', template: `<h1>Visite</h1>` })
export class VisitsPage {}
```

`pages/contract-page.ts`:

```ts
import { Component } from '@angular/core';

@Component({ selector: 'app-contract-page', template: `<h1>Contratto</h1>` })
export class ContractPage {}
```

`app.routes.ts`:

```ts
import { Routes } from '@angular/router';
import { guestGuard, sessionGuard } from './auth/guards';
import { LoginPage } from './auth/login-page';
import { ContractPage } from './pages/contract-page';
import { Shell } from './pages/shell';
import { SummaryPage } from './pages/summary-page';
import { VisitsPage } from './pages/visits-page';

export const routes: Routes = [
  { path: 'accesso', component: LoginPage, canActivate: [guestGuard] },
  {
    path: '',
    component: Shell,
    canActivate: [sessionGuard],
    canActivateChild: [sessionGuard],
    children: [
      { path: 'riepilogo', component: SummaryPage },
      { path: 'visite', component: VisitsPage },
      { path: 'contratto', component: ContractPage },
      { path: '', pathMatch: 'full', redirectTo: 'riepilogo' },
    ],
  },
  { path: '**', redirectTo: '' },
];
```

`app.config.ts`:

```ts
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { authInterceptor } from './auth/auth.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
  ],
};
```

`app.ts`:

```ts
import { Component, effect, inject } from '@angular/core';
import { Router, RouterOutlet } from '@angular/router';
import { InactivityWatcher } from './auth/inactivity';
import { LogoutPending } from './auth/logout-pending';
import { SessionStore } from './auth/session.store';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, LogoutPending],
  template: `
    @if (session.status() === 'logout-pending') {
      <app-logout-pending />
    }
    <router-outlet />
  `,
})
export class App {
  readonly session = inject(SessionStore);

  constructor() {
    const router = inject(Router);
    const watcher = inject(InactivityWatcher);
    let wasAuthenticated = false;
    effect(() => {
      const status = this.session.status();
      if (status === 'authenticated') {
        watcher.start();
        wasAuthenticated = true;
      } else {
        watcher.stop();
        if (status === 'anonymous' && wasAuthenticated) {
          wasAuthenticated = false;
          void router.navigateByUrl('/accesso');
        }
      }
    });
  }
}
```

In `main.ts`, prima di `bootstrapApplication`:

```ts
import { reloadOnRestore } from './app/auth/restore';

reloadOnRestore(window, () => location.reload());
```

Eliminare `app.html` e `app.css`.

- [ ] **Step 5: Eseguire test e build**

Run: `npx ng test --watch=false` poi `npx ng build`
Expected: tutti i test passano; build senza errori.

- [ ] **Step 6: Commit**

```bash
git add frontend
git commit -m "BID-06: accesso di prova, pagine protette, timeout di inattivita e logout non confermato"
```

---

### Task 5: Dati, dati demo e formattazione

**Files:**
- Create: `frontend/src/app/data/models.ts`, `sources.ts`, `demo-data.ts`, `load-rows.ts`, `aggregate.ts`
- Create: `frontend/src/app/format/format.ts`
- Test: `frontend/src/app/format/format.spec.ts`, `frontend/src/app/data/data.spec.ts`

**Interfaces:**
- Consumes: `SessionStore.ended$`, `SessionStore.status()`.
- Produces:
  - tipi `PortalContract`, `PortalVisit`, `PortalKpi`, `ContractStatus`;
  - `DataSource<T> { readonly demo: boolean; load(): Observable<T[]> }`; token `CONTRACTS`, `VISITS`, `KPI`;
  - `loadRows<T>(source): { state: Signal<LoadState<T>>; reload(): void }` con `LoadState<T> = {kind:'loading'} | {kind:'error'} | {kind:'ready'; rows: T[]}`;
  - `yearsDesc(rows)`, `totalVisits(rows)`, `byDayHour(rows)`, `byStand(rows)`;
  - `DASH`, `money`, `decimal`, `signedPercent`, `ratioPercent`, `dateIt`, `isoDay`, `paymentStatus(paidOn, dueOn, status, today)`, `CONTRACT_STATUS`.

- [ ] **Step 1: Scrivere i test**

`format/format.spec.ts`:

```ts
import { DASH, dateIt, decimal, isoDay, money, paymentStatus, ratioPercent, signedPercent } from './format';

const plain = (text: string) => text.replace(/\s/g, ' ');

describe('formattazione', () => {
  it('un valore mancante è un trattino, lo zero resta zero', () => {
    for (const format of [money, decimal, signedPercent, ratioPercent]) {
      expect(format(null)).toBe(DASH);
      expect(format(undefined)).toBe(DASH);
      expect(format(0)).not.toBe(DASH);
    }
    expect(decimal(0)).toBe('0');
    expect(dateIt(null)).toBe(DASH);
  });

  it('euro e date in italiano', () => {
    expect(plain(money(10945.9))).toBe('10.945,90 €');
    expect(dateIt('2026-12-03')).toBe('03/12/2026');
    expect(isoDay(new Date(2026, 10, 5, 23, 30))).toBe('2026-11-05');
  });

  it('lo sconto è una frazione, la variazione è già una percentuale', () => {
    expect(ratioPercent(0.05)).toBe('5%');
    expect(signedPercent(12.5)).toBe('+12,5%');
    expect(signedPercent(-3)).toBe('-3%');
    expect(signedPercent(0)).toBe('0%');
  });

  it('stato dei pagamenti', () => {
    const today = '2026-11-28';
    expect(paymentStatus('2026-10-01', '2026-10-10', 'SIGNED', today)).toBe('Pagato il 01/10/2026');
    expect(paymentStatus('2026-10-01', null, 'CANCELLED', today)).toBe('Pagato il 01/10/2026');
    expect(paymentStatus(null, '2026-10-10', 'CANCELLED', today)).toBe('— (contratto annullato)');
    expect(paymentStatus(null, null, 'SIGNED', today)).toBe('— (scadenza non disponibile)');
    expect(paymentStatus(null, '2026-11-27', 'SIGNED', today)).toBe('Scaduto il 27/11/2026');
    expect(paymentStatus(null, '2026-11-28', 'SIGNED', today)).toBe('Da pagare entro il 28/11/2026');
  });
});
```

`data/data.spec.ts`:

```ts
import { Injector, runInInjectionContext } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Subject, throwError } from 'rxjs';
import { SessionStore } from '../auth/session.store';
import { byDayHour, byStand, totalVisits, yearsDesc } from './aggregate';
import { loadRows } from './load-rows';
import { PortalVisit } from './models';
import { CONTRACTS, DataSource, KPI, VISITS } from './sources';

const visit = (standCode: string, visitDate: string, visitHour: number, visits: number): PortalVisit =>
  ({ editionYear: Number(visitDate.slice(0, 4)), standCode, visitDate, visitHour, visits });

describe('dati', () => {
  it('le sorgenti iniziali dichiarano di essere demo', () => {
    for (const token of [CONTRACTS, VISITS, KPI]) {
      expect(TestBed.inject<DataSource<unknown>>(token).demo).toBe(true);
    }
  });

  it('aggrega le visite per anno, ora e stand', () => {
    const rows = [visit('B', '2025-12-20', 10, 2), visit('A', '2025-12-19', 11, 5),
      visit('B', '2025-12-19', 11, 1), visit('A', '2024-12-19', 9, 4)];
    expect(yearsDesc(rows)).toEqual([2025, 2024]);
    expect(totalVisits(rows)).toBe(12);
    expect(byDayHour(rows.filter((r) => r.editionYear === 2025))).toEqual([
      { date: '2025-12-19', hour: 11, visits: 6 },
      { date: '2025-12-20', hour: 10, visits: 2 },
    ]);
    expect(byStand(rows)).toEqual([{ standCode: 'A', visits: 9 }, { standCode: 'B', visits: 3 }]);
  });

  describe('caricamento', () => {
    let session: SessionStore;
    const run = <T>(source: DataSource<T>) =>
      runInInjectionContext(TestBed.inject(Injector), () => loadRows(source));

    beforeEach(() => {
      session = TestBed.inject(SessionStore);
      session.start('t', 7);
    });

    it('una risposta arrivata dopo il logout viene scartata', () => {
      const answer = new Subject<number[]>();
      const result = run({ demo: true, load: () => answer });
      session.lock();
      answer.next([1, 2, 3]);
      expect(result.state().kind).not.toBe('ready');
    });

    it('un errore porta allo stato errore e Riprova ricarica', () => {
      let calls = 0;
      const answer = new Subject<number[]>();
      const result = run({ demo: false, load: () => (calls++ === 0 ? throwError(() => new Error('rete')) : answer) });
      expect(result.state().kind).toBe('error');
      result.reload();
      answer.next([]);
      expect(result.state()).toEqual({ kind: 'ready', rows: [] });
      expect(session.status()).toBe('authenticated');
    });
  });
});
```

- [ ] **Step 2: Verificare il fallimento**

Run: `npx ng test --watch=false`
Expected: FAIL, moduli mancanti.

- [ ] **Step 3: Scrivere il codice**

`format/format.ts`:

```ts
import { ContractStatus } from '../data/models';

export const DASH = '—';
type Value = number | null | undefined;

const euro = new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR' });
const plain = new Intl.NumberFormat('it-IT', { maximumFractionDigits: 2 });
const signed = new Intl.NumberFormat('it-IT', { maximumFractionDigits: 2, signDisplay: 'exceptZero' });

const orDash = (value: Value, format: (n: number) => string) => (value == null ? DASH : format(value));

export const money = (value: Value) => orDash(value, (n) => euro.format(n));
export const decimal = (value: Value) => orDash(value, (n) => plain.format(n));
/** Per i campi già in percentuale (12.5 = +12,5%). */
export const signedPercent = (value: Value) => orDash(value, (n) => `${signed.format(n)}%`);
/** Per le frazioni, come discountPct (0.05 = 5%). */
export const ratioPercent = (value: Value) => orDash(value, (n) => `${plain.format(n * 100)}%`);

export function dateIt(value: string | null | undefined): string {
  return value ? value.split('-').reverse().join('/') : DASH;
}

/** Giorno locale in formato YYYY-MM-DD. */
export function isoDay(now: Date): string {
  const two = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${two(now.getMonth() + 1)}-${two(now.getDate())}`;
}

export function paymentStatus(
  paidOn: string | null, dueOn: string | null, status: ContractStatus, today: string,
): string {
  if (paidOn) return `Pagato il ${dateIt(paidOn)}`;
  if (status === 'CANCELLED') return `${DASH} (contratto annullato)`;
  if (!dueOn) return `${DASH} (scadenza non disponibile)`;
  return dueOn < today ? `Scaduto il ${dateIt(dueOn)}` : `Da pagare entro il ${dateIt(dueOn)}`;
}

export const CONTRACT_STATUS: Record<ContractStatus, string> = {
  DRAFT: 'Bozza',
  SIGNED: 'Firmato',
  CANCELLED: 'Annullato',
};
```

`data/models.ts` (allineato a `docs/api/openapi.yaml`; sono omessi i campi fuori da questa versione):

```ts
export type ContractStatus = 'DRAFT' | 'SIGNED' | 'CANCELLED';

export interface PortalContract {
  contractId: number;
  contractNumber: string;
  editionYear: number;
  status: ContractStatus;
  signedOn: string | null;
  listAmount: number | null;
  discountPct: number | null;
  netAmount: number | null;
  stands: string | null;
  depositDueOn: string | null;
  depositPaidOn: string | null;
  balanceDueOn: string | null;
  balancePaidOn: string | null;
}

export interface PortalVisit {
  editionYear: number;
  standCode: string;
  visitDate: string;
  visitHour: number;
  visits: number;
}

export interface PortalKpi {
  editionYear: number;
  contractedNet: number | null;
  sqm: number | null;
  visits: number | null;
  visitsPerSqm: number | null;
  prevYear: number | null;
  contractedNetDeltaPct: number | null;
  visitsDeltaPct: number | null;
}
```

`data/demo-data.ts`:

```ts
import { PortalContract, PortalKpi, PortalVisit } from './models';

// DATI INVENTATI per lo sviluppo: non descrivono nessun espositore reale.
export const DEMO_CONTRACTS: PortalContract[] = [
  { contractId: 3, contractNumber: 'DEMO-2026-001', editionYear: 2026, status: 'SIGNED', signedOn: '2026-10-20',
    listAmount: 12000, discountPct: 0.05, netAmount: 11400, stands: 'DEMO-01',
    depositDueOn: '2026-11-04', depositPaidOn: null, balanceDueOn: '2026-12-30', balancePaidOn: null },
  { contractId: 2, contractNumber: 'DEMO-2025-001', editionYear: 2025, status: 'SIGNED', signedOn: '2025-09-02',
    listAmount: 9000, discountPct: 0, netAmount: 9000, stands: 'DEMO-02',
    depositDueOn: '2025-09-17', depositPaidOn: '2025-09-15', balanceDueOn: '2025-11-18', balancePaidOn: '2025-11-10' },
  { contractId: 1, contractNumber: 'DEMO-2024-001', editionYear: 2024, status: 'CANCELLED', signedOn: null,
    listAmount: 8000, discountPct: 0, netAmount: 8000, stands: null,
    depositDueOn: null, depositPaidOn: null, balanceDueOn: null, balancePaidOn: null },
];

const visit = (editionYear: number, standCode: string, day: number, visitHour: number, visits: number): PortalVisit =>
  ({ editionYear, standCode, visitDate: `${editionYear}-12-${day}`, visitHour, visits });

export const DEMO_VISITS: PortalVisit[] = [
  visit(2025, 'DEMO-02', 12, 10, 34), visit(2025, 'DEMO-02', 12, 11, 58), visit(2025, 'DEMO-02', 12, 15, 41),
  visit(2025, 'DEMO-02', 13, 10, 62), visit(2025, 'DEMO-02', 13, 12, 77), visit(2025, 'DEMO-02', 14, 16, 29),
  visit(2024, 'DEMO-03', 13, 11, 47), visit(2024, 'DEMO-03', 14, 15, 53),
];

export const DEMO_KPI: PortalKpi[] = [
  { editionYear: 2024, contractedNet: 8000, sqm: 32, visits: 100, visitsPerSqm: 3.13,
    prevYear: null, contractedNetDeltaPct: null, visitsDeltaPct: null },
  { editionYear: 2025, contractedNet: 9000, sqm: null, visits: 301, visitsPerSqm: null,
    prevYear: 2024, contractedNetDeltaPct: 12.5, visitsDeltaPct: 201 },
];
```

`data/sources.ts`:

```ts
import { InjectionToken } from '@angular/core';
import { Observable, delay, of } from 'rxjs';
import { DEMO_CONTRACTS, DEMO_KPI, DEMO_VISITS } from './demo-data';
import { PortalContract, PortalKpi, PortalVisit } from './models';

/** Quando un endpoint è pronto si sostituisce solo la sua sorgente, con demo = false. */
export interface DataSource<T> {
  readonly demo: boolean;
  load(): Observable<T[]>;
}

function demoSource<T>(rows: T[]): DataSource<T> {
  return { demo: true, load: () => of(structuredClone(rows)).pipe(delay(200)) };
}

export const CONTRACTS = new InjectionToken<DataSource<PortalContract>>('contratti', {
  providedIn: 'root', factory: () => demoSource(DEMO_CONTRACTS),
});
export const VISITS = new InjectionToken<DataSource<PortalVisit>>('visite', {
  providedIn: 'root', factory: () => demoSource(DEMO_VISITS),
});
export const KPI = new InjectionToken<DataSource<PortalKpi>>('risultati', {
  providedIn: 'root', factory: () => demoSource(DEMO_KPI),
});
```

`data/load-rows.ts`:

```ts
import { DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subscription, takeUntil } from 'rxjs';
import { SessionStore } from '../auth/session.store';
import { DataSource } from './sources';

export type LoadState<T> = { kind: 'loading' } | { kind: 'error' } | { kind: 'ready'; rows: T[] };

/** Da chiamare nel contesto di injection di un componente. */
export function loadRows<T>(source: DataSource<T>) {
  const session = inject(SessionStore);
  const destroyRef = inject(DestroyRef);
  const state = signal<LoadState<T>>({ kind: 'loading' });
  let running: Subscription | undefined;

  const reload = () => {
    running?.unsubscribe();
    state.set({ kind: 'loading' });
    if (session.status() !== 'authenticated') return;
    running = source
      .load()
      // Vale anche per le sorgenti demo, che non passano dall'interceptor.
      .pipe(takeUntil(session.ended$), takeUntilDestroyed(destroyRef))
      .subscribe({
        next: (rows) => state.set({ kind: 'ready', rows }),
        error: () => state.set({ kind: 'error' }),
      });
  };

  reload();
  return { state: state.asReadonly(), reload };
}
```

`data/aggregate.ts`:

```ts
import { PortalVisit } from './models';

export const yearsDesc = (rows: { editionYear: number }[]) =>
  [...new Set(rows.map((r) => r.editionYear))].sort((a, b) => b - a);

export const totalVisits = (rows: PortalVisit[]) => rows.reduce((sum, r) => sum + r.visits, 0);

export function byDayHour(rows: PortalVisit[]) {
  const totals = new Map<string, { date: string; hour: number; visits: number }>();
  for (const r of rows) {
    const key = `${r.visitDate} ${r.visitHour}`;
    const entry = totals.get(key) ?? { date: r.visitDate, hour: r.visitHour, visits: 0 };
    entry.visits += r.visits;
    totals.set(key, entry);
  }
  return [...totals.values()].sort((a, b) => a.date.localeCompare(b.date) || a.hour - b.hour);
}

export function byStand(rows: PortalVisit[]) {
  const totals = new Map<string, number>();
  for (const r of rows) totals.set(r.standCode, (totals.get(r.standCode) ?? 0) + r.visits);
  return [...totals]
    .map(([standCode, visits]) => ({ standCode, visits }))
    .sort((a, b) => b.visits - a.visits || a.standCode.localeCompare(b.standCode));
}
```

- [ ] **Step 4: Eseguire i test**

Run: `npx ng test --watch=false`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/app/data frontend/src/app/format
git commit -m "BID-06: sorgenti dati demo, stati di caricamento e formattazione"
```

---

### Task 6: Le tre pagine e lo stile

**Files:**
- Create: `frontend/src/app/shared/ui.ts`
- Modify: `frontend/src/app/pages/summary-page.ts`, `visits-page.ts`, `contract-page.ts`, `frontend/src/styles.css`
- Test: `frontend/src/app/pages/pages.spec.ts`

**Interfaces:**
- Consumes: `CONTRACTS`, `VISITS`, `KPI`, `loadRows`, `aggregate.ts`, `format.ts`, `SessionStore.profile`.
- Produces: `DemoBadge` (`<app-demo-badge />`), `StateBox` (`<app-state-box [kind]="..." (retry)="..." />`, `kind: 'loading' | 'error' | 'empty'`).

- [ ] **Step 1: Scrivere i test**

`pages.spec.ts`:

```ts
import { Type } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { SessionStore } from '../auth/session.store';
import { PortalContract, PortalKpi, PortalVisit } from '../data/models';
import { CONTRACTS, DataSource, KPI, VISITS } from '../data/sources';
import { DEMO_CONTRACTS, DEMO_KPI, DEMO_VISITS } from '../data/demo-data';
import { ContractPage } from './contract-page';
import { SummaryPage } from './summary-page';
import { VisitsPage } from './visits-page';

const source = <T>(rows: T[], demo = true): DataSource<T> => ({ demo, load: () => of(rows) });

async function render(
  page: Type<unknown>,
  data: { kpi?: DataSource<PortalKpi>; visits?: DataSource<PortalVisit>; contracts?: DataSource<PortalContract> } = {},
) {
  TestBed.resetTestingModule();
  TestBed.configureTestingModule({
    providers: [
      { provide: KPI, useValue: data.kpi ?? source(DEMO_KPI) },
      { provide: VISITS, useValue: data.visits ?? source(DEMO_VISITS) },
      { provide: CONTRACTS, useValue: data.contracts ?? source(DEMO_CONTRACTS) },
    ],
  });
  const session = TestBed.inject(SessionStore);
  session.start('t', 7);
  session.profile.set({ exhibitorId: 7, exhibitorCode: 'ESP7', legalName: 'Nome Vero', categoryName: 'Categoria' });
  const fixture = TestBed.createComponent(page);
  await fixture.whenStable();
  const element = fixture.nativeElement as HTMLElement;
  return { fixture, element, text: () => element.textContent!.replace(/\s+/g, ' ') };
}

describe('pagine', () => {
  it('Riepilogo: ultima edizione, valori mancanti e variazioni', async () => {
    const { element, text } = await render(SummaryPage);
    expect(text()).toContain('Nome Vero');
    expect(text()).toContain('Edizione 2025');
    expect(text()).toContain('301');
    expect(text()).toContain('+12,5%');
    expect(text()).toContain('Dato non disponibile');
    expect(element.querySelectorAll('tbody tr').length).toBe(2);
  });

  it('Riepilogo con una sola edizione: nessuna variazione inventata', async () => {
    const { element, text } = await render(SummaryPage, { kpi: source([DEMO_KPI[0]]) });
    expect(element.querySelectorAll('tbody tr').length).toBe(1);
    expect(text()).toContain('nessuna edizione precedente');
    expect(text()).not.toContain('+');
  });

  it('l’etichetta demo segue la sorgente', async () => {
    for (const page of [SummaryPage, VisitsPage, ContractPage]) {
      expect((await render(page)).text()).toContain('dati demo');
    }
    const real = await render(SummaryPage, { kpi: source(DEMO_KPI, false) });
    expect(real.text()).not.toContain('dati demo');
  });

  it('Visite: edizione più recente, totale e nota', async () => {
    const { fixture, element, text } = await render(VisitsPage);
    expect(text()).toMatch(/Totale visite\s*301/);
    expect(text()).toContain('Una visita non è un contatto');
    const select = element.querySelector('select')!;
    select.value = '2024';
    select.dispatchEvent(new Event('change'));
    await fixture.whenStable();
    expect(text()).toMatch(/Totale visite\s*100/);
  });

  it('Contratto: sconto, stati dei pagamenti e contratto annullato', async () => {
    const { text } = await render(ContractPage);
    expect(text()).toContain('5%');
    expect(text()).toContain('Scaduto il');
    expect(text()).toContain('Pagato il 15/09/2025');
    expect(text()).toContain('contratto annullato');
    expect(text()).toContain('IVA esclusa');
  });

  it('nessun dato ed errore hanno uno stato proprio', async () => {
    for (const page of [SummaryPage, VisitsPage, ContractPage]) {
      const empty = await render(page, { kpi: source([]), visits: source([]), contracts: source([]) });
      expect(empty.text()).toContain('Nessun dato disponibile');
      const broken = { demo: true, load: () => throwError(() => new Error('rete')) };
      const failed = await render(page, { kpi: broken, visits: broken, contracts: broken });
      expect(failed.text()).toContain('Riprova');
    }
  });
});
```

- [ ] **Step 2: Verificare il fallimento**

Run: `npx ng test --watch=false`
Expected: FAIL, le pagine hanno solo il titolo.

- [ ] **Step 3: Scrivere i componenti comuni**

`shared/ui.ts`:

```ts
import { Component, input, output } from '@angular/core';

@Component({
  selector: 'app-demo-badge',
  template: `<span class="badge">dati demo</span>`,
})
export class DemoBadge {}

@Component({
  selector: 'app-state-box',
  template: `
    <section class="panel state" aria-live="polite">
      @switch (kind()) {
        @case ('loading') { <p>Caricamento…</p> }
        @case ('error') {
          <p role="alert">Non è stato possibile caricare i dati.</p>
          <button type="button" (click)="retry.emit()">Riprova</button>
        }
        @case ('empty') { <p>Nessun dato disponibile.</p> }
      }
    </section>
  `,
})
export class StateBox {
  readonly kind = input.required<'loading' | 'error' | 'empty'>();
  readonly retry = output<void>();
}
```

- [ ] **Step 4: Scrivere le pagine**

`pages/summary-page.ts`:

```ts
import { Component, computed, inject } from '@angular/core';
import { SessionStore } from '../auth/session.store';
import { loadRows } from '../data/load-rows';
import { KPI } from '../data/sources';
import { DASH, decimal, money, signedPercent } from '../format/format';
import { DemoBadge, StateBox } from '../shared/ui';

@Component({
  selector: 'app-summary-page',
  imports: [DemoBadge, StateBox],
  template: `
    <h1>Riepilogo @if (source.demo) { <app-demo-badge /> }</h1>
    @if (session.profile(); as profile) {
      <p>{{ profile.legalName }} · {{ profile.exhibitorCode }} · {{ profile.categoryName }}</p>
    }
    @if (source.demo) {
      <p class="warning">Il profilo è reale; i numeri qui sotto sono inventati e non sono quelli di questo espositore.</p>
    }
    @if (data.state().kind !== 'ready') {
      <app-state-box [kind]="data.state().kind === 'error' ? 'error' : 'loading'" (retry)="data.reload()" />
    } @else if (latest(); as last) {
      <h2>Edizione {{ last.editionYear }}</h2>
      <div class="tiles">
        @for (tile of tiles(); track tile.label) {
          <section class="panel tile">
            <h3>{{ tile.label }}</h3>
            <p class="big">{{ tile.value }}</p>
            @if (tile.value === dash) { <p class="hint">Dato non disponibile</p> }
          </section>
        }
      </div>
      <section class="panel">
        <h2>Confronto tra edizioni</h2>
        <p class="hint">Importi IVA esclusa. “—” indica un dato non disponibile.</p>
        <table>
          <thead>
            <tr>
              <th scope="col">Anno</th><th scope="col">Visite</th><th scope="col">Visite al m²</th>
              <th scope="col">Superficie (m²)</th><th scope="col">Netto</th>
              <th scope="col">Variazione visite</th><th scope="col">Variazione netto</th>
              <th scope="col">Rispetto a</th>
            </tr>
          </thead>
          <tbody>
            @for (row of rows(); track row.editionYear) {
              <tr>
                <th scope="row">{{ row.editionYear }}</th>
                <td>{{ decimal(row.visits) }}</td>
                <td>{{ decimal(row.visitsPerSqm) }}</td>
                <td>{{ decimal(row.sqm) }}</td>
                <td>{{ money(row.contractedNet) }}</td>
                <td>{{ percent(row.visitsDeltaPct) }}</td>
                <td>{{ percent(row.contractedNetDeltaPct) }}</td>
                <td>{{ row.prevYear ?? 'nessuna edizione precedente' }}</td>
              </tr>
            }
          </tbody>
        </table>
      </section>
    } @else {
      <app-state-box kind="empty" />
    }
  `,
})
export class SummaryPage {
  readonly session = inject(SessionStore);
  readonly source = inject(KPI);
  readonly data = loadRows(this.source);
  readonly dash = DASH;
  readonly decimal = decimal;
  readonly money = money;
  readonly percent = signedPercent;

  readonly rows = computed(() => {
    const state = this.data.state();
    return state.kind === 'ready' ? [...state.rows].sort((a, b) => b.editionYear - a.editionYear) : [];
  });
  readonly latest = computed(() => this.rows()[0]);
  readonly tiles = computed(() => {
    const last = this.latest();
    return last
      ? [
          { label: 'Visite', value: decimal(last.visits) },
          { label: 'Visite al m²', value: decimal(last.visitsPerSqm) },
          { label: 'Superficie (m²)', value: decimal(last.sqm) },
          { label: 'Netto contratto (IVA esclusa)', value: money(last.contractedNet) },
        ]
      : [];
  });
}
```

`pages/visits-page.ts`:

```ts
import { Component, computed, inject, signal } from '@angular/core';
import { byDayHour, byStand, totalVisits, yearsDesc } from '../data/aggregate';
import { loadRows } from '../data/load-rows';
import { VISITS } from '../data/sources';
import { dateIt, decimal } from '../format/format';
import { DemoBadge, StateBox } from '../shared/ui';

@Component({
  selector: 'app-visits-page',
  imports: [DemoBadge, StateBox],
  template: `
    <h1>Visite @if (source.demo) { <app-demo-badge /> }</h1>
    <p class="hint">Una visita non è un contatto.</p>
    @if (data.state().kind !== 'ready') {
      <app-state-box [kind]="data.state().kind === 'error' ? 'error' : 'loading'" (retry)="data.reload()" />
    } @else if (!years().length) {
      <app-state-box kind="empty" />
    } @else {
      <label>Edizione
        <select (change)="choose($event)">
          @for (y of years(); track y) { <option [value]="y" [selected]="y === year()">{{ y }}</option> }
        </select>
      </label>
      <section class="panel tile">
        <h2>Totale visite</h2>
        <p class="big">{{ decimal(total()) }}</p>
      </section>
      <section class="panel">
        <h2>Andamento per giorno e ora</h2>
        <ul class="bars">
          @for (slot of slots(); track slot.date + slot.hour) {
            <li>
              <span>{{ dateIt(slot.date) }} · {{ slot.hour }}:00</span>
              <span class="bar" aria-hidden="true"><i [style.width.%]="(slot.visits / peak()) * 100"></i></span>
              <strong>{{ decimal(slot.visits) }}</strong>
            </li>
          }
        </ul>
      </section>
      <section class="panel">
        <h2>Per stand</h2>
        <table>
          <thead><tr><th scope="col">Stand</th><th scope="col">Visite</th></tr></thead>
          <tbody>
            @for (row of stands(); track row.standCode) {
              <tr><th scope="row">{{ row.standCode }}</th><td>{{ decimal(row.visits) }}</td></tr>
            }
          </tbody>
        </table>
      </section>
    }
  `,
})
export class VisitsPage {
  readonly source = inject(VISITS);
  readonly data = loadRows(this.source);
  readonly dateIt = dateIt;
  readonly decimal = decimal;
  private readonly chosen = signal<number | null>(null);

  private readonly all = computed(() => {
    const state = this.data.state();
    return state.kind === 'ready' ? state.rows : [];
  });
  readonly years = computed(() => yearsDesc(this.all()));
  readonly year = computed(() => this.chosen() ?? this.years()[0]);
  private readonly selected = computed(() => this.all().filter((r) => r.editionYear === this.year()));
  readonly total = computed(() => totalVisits(this.selected()));
  readonly slots = computed(() => byDayHour(this.selected()));
  readonly peak = computed(() => Math.max(1, ...this.slots().map((s) => s.visits)));
  readonly stands = computed(() => byStand(this.selected()));

  choose(event: Event): void {
    this.chosen.set(Number((event.target as HTMLSelectElement).value));
  }
}
```

`pages/contract-page.ts`:

```ts
import { Component, computed, inject } from '@angular/core';
import { loadRows } from '../data/load-rows';
import { PortalContract } from '../data/models';
import { CONTRACTS } from '../data/sources';
import { CONTRACT_STATUS, DASH, dateIt, isoDay, money, paymentStatus, ratioPercent } from '../format/format';
import { DemoBadge, StateBox } from '../shared/ui';

@Component({
  selector: 'app-contract-page',
  imports: [DemoBadge, StateBox],
  template: `
    <h1>Contratto @if (source.demo) { <app-demo-badge /> }</h1>
    <p class="hint">Importi in euro, IVA esclusa. “—” indica un dato non disponibile.</p>
    @if (data.state().kind !== 'ready') {
      <app-state-box [kind]="data.state().kind === 'error' ? 'error' : 'loading'" (retry)="data.reload()" />
    } @else {
      @for (c of contracts(); track c.contractId) {
        <section class="panel">
          <h2>{{ c.contractNumber }} · Edizione {{ c.editionYear }} · {{ status[c.status] }}</h2>
          <dl>
            <dt>Firmato il</dt><dd>{{ c.signedOn ? dateIt(c.signedOn) : dash + ' (non firmato o data non disponibile)' }}</dd>
            <dt>Stand</dt><dd>{{ c.stands || dash + ' (nessuno stand indicato)' }}</dd>
            <dt>Prezzo di listino</dt><dd>{{ money(c.listAmount) }}</dd>
            <dt>Sconto</dt><dd>{{ discount(c.discountPct) }}</dd>
            <dt>Netto</dt><dd>{{ money(c.netAmount) }}</dd>
          </dl>
          <h3>Pagamenti</h3>
          <dl>
            <dt>Acconto</dt><dd>{{ deposit(c) }}</dd>
            <dt>Saldo</dt><dd>{{ balance(c) }}</dd>
          </dl>
        </section>
      } @empty {
        <app-state-box kind="empty" />
      }
    }
  `,
})
export class ContractPage {
  readonly source = inject(CONTRACTS);
  readonly data = loadRows(this.source);
  readonly status = CONTRACT_STATUS;
  readonly dash = DASH;
  readonly dateIt = dateIt;
  readonly money = money;
  readonly discount = ratioPercent;
  private readonly today = isoDay(new Date());

  readonly contracts = computed(() => {
    const state = this.data.state();
    return state.kind === 'ready' ? [...state.rows].sort((a, b) => b.editionYear - a.editionYear) : [];
  });

  deposit(c: PortalContract): string {
    return paymentStatus(c.depositPaidOn, c.depositDueOn, c.status, this.today);
  }

  balance(c: PortalContract): string {
    return paymentStatus(c.balancePaidOn, c.balanceDueOn, c.status, this.today);
  }
}
```

- [ ] **Step 5: Scrivere lo stile**

`frontend/src/styles.css` (stile del mockup: vetro, numeri grandi, giallo e nero; testi scuri per la leggibilità):

```css
:root { --ink: #14161c; --muted: #3f4552; --accent: #ffd60a; --glass: rgba(255, 255, 255, 0.82); }
* { box-sizing: border-box; }
body {
  margin: 0; min-height: 100vh; color: var(--ink); font: 100%/1.5 system-ui, sans-serif;
  background: radial-gradient(circle at 10% 0%, #fff3b8, transparent 45%),
    radial-gradient(circle at 90% 20%, #c9d3f5, transparent 45%), #eceef4;
  background-attachment: fixed;
}
h1 { font-size: 2rem; line-height: 1.1; letter-spacing: -0.02em; }
.panel {
  background: var(--glass); border: 1px solid rgba(255, 255, 255, 0.9); border-radius: 24px;
  padding: 1.25rem 1.5rem; margin-bottom: 1rem; overflow-x: auto;
  backdrop-filter: blur(18px) saturate(160%); box-shadow: 0 12px 32px rgba(20, 22, 28, 0.08);
}
.center { min-height: 100vh; display: grid; place-items: center; padding: 1rem; }
.login { width: min(28rem, 100%); display: grid; gap: 0.75rem; }
.topbar { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding: 1rem 2rem; flex-wrap: wrap; }
.content { max-width: 70rem; margin: 0 auto; padding: 0 2rem 2rem; }
.pills { display: flex; gap: 0.25rem; background: var(--glass); border-radius: 999px; padding: 0.25rem; }
.pills a { padding: 0.4rem 1.1rem; border-radius: 999px; color: var(--ink); text-decoration: none; }
.pills a.active { background: var(--ink); color: #fff; font-weight: 600; }
button, input, select { font: inherit; padding: 0.55rem 1.1rem; border-radius: 999px; border: 1px solid #5b6270; background: #fff; color: var(--ink); }
button { cursor: pointer; }
button:active { transform: scale(0.97); }
button:disabled { cursor: wait; opacity: 0.6; }
button.primary { background: var(--accent); border-color: var(--ink); font-weight: 700; }
:focus-visible { outline: 3px solid var(--ink); outline-offset: 2px; }
.badge { display: inline-block; font-size: 0.75rem; font-weight: 700; vertical-align: middle; background: var(--accent); color: var(--ink); border-radius: 999px; padding: 0.15rem 0.7rem; letter-spacing: 0.01em; }
.warning { border-left: 4px solid var(--accent); padding-left: 0.75rem; }
.hint { color: var(--muted); }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr)); gap: 1rem; }
.tile h2, .tile h3 { font-size: 0.95rem; margin: 0; }
.big { font-size: 2.5rem; line-height: 1.1; letter-spacing: -0.02em; margin: 0.35rem 0 0; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 0.5rem 0.75rem 0.5rem 0; border-bottom: 1px solid #d5d9e3; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 0.35rem 1.5rem; }
dt { color: var(--muted); }
dd { margin: 0; font-weight: 600; }
.bars { list-style: none; padding: 0; display: grid; gap: 0.5rem; }
.bars li { display: grid; grid-template-columns: 12rem 1fr 4rem; align-items: center; gap: 0.75rem; }
.bar { height: 0.75rem; background: #dfe2ea; border-radius: 999px; }
.bar i { display: block; height: 100%; background: var(--ink); border-radius: 999px; }

@media (prefers-reduced-transparency: reduce) { .panel, .pills { background: #fff; backdrop-filter: none; } }
@media (prefers-contrast: more) { .panel, .pills { background: #fff; border: 2px solid var(--ink); } }
@media (prefers-reduced-motion: reduce) { button:active { transform: none; } }
```

- [ ] **Step 6: Eseguire test e build**

Run: `npx ng test --watch=false` poi `npx ng build`
Expected: tutti i test passano; build senza errori.

- [ ] **Step 7: Commit**

```bash
git add frontend/src
git commit -m "BID-06: pagine Riepilogo, Visite e Contratto con dati demo"
```

---

### Task 7: Prova nel browser e documentazione

**Files:**
- Create: `frontend/README.md` (sostituisce quello generato)
- Modify: `README.md`, `docs/06-assegnazione-task-bid.md`

- [ ] **Step 1: Avviare tutto**

Database: `docker compose up -d`. Se manca l'account del backend, seguire `backend/README.md`. Backend in `backend/`: `./mvnw spring-boot:run -Dspring-boot.run.profiles=dev`. Frontend in `frontend/`: `npx ng serve`.
Expected: Flyway applica `V7`; il portale risponde su `http://localhost:4200`.

- [ ] **Step 2: Leggere due ID espositore**

Run: `docker exec arcade-db psql -U postgres -d arcade -At -c "SELECT exhibitor_id FROM core.exhibitor ORDER BY 1 LIMIT 2"`
Non scrivere nomi di espositori nel repository, nei commit o negli screenshot condivisi.

- [ ] **Step 3: Prova guidata (annotare l'esito di ogni punto)**

1. Accesso con il primo ID: compaiono Riepilogo, Visite, Contratto con "dati demo".
2. Application → Storage del browser: nessun token in Local Storage, Session Storage o cookie.
3. Copiare l'header `Authorization` della richiesta `/portal/me` (strumenti di sviluppo → Network).
4. Due schede con lo stesso ID e una terza con il secondo ID. "Esci" nella prima: la seconda torna all'accesso, la terza resta dentro.
5. Tasto Indietro dopo l'uscita: nessun dato.
6. Riusare il token copiato con `curl.exe -i -H "Authorization: <valore copiato>" http://localhost:8080/api/v1/portal/me`. Expected: **401**.
7. Accesso, fermare il backend, premere "Esci": "Logout non confermato", nessun dato. Riavviare il backend, "Riprova": torna all'accesso.
8. ID inesistente: "Espositore non trovato". ID `abc`: messaggio, nessuna richiesta in Network.
9. Finestra a 1280 px: nessuna sovrapposizione; navigazione completa da tastiera.

Se un punto fallisce, correggerlo (con un test che lo riproduca) prima di proseguire.

- [ ] **Step 4: Documentare**

`frontend/README.md`: requisiti (Node 24, backend con profilo `dev`), comandi `npm install`, `npx ng serve`, `npx ng test --watch=false`; accesso di prova **solo per lo sviluppo**; come sostituire una sorgente demo (un provider per `CONTRACTS`, `VISITS` o `KPI` con `demo: false`) e come autorizzare l'endpoint in `SecurityConfig`.

`README.md` della radice: nella riga "Frontend Angular" indicare portale espositori in prima versione con dati demo; dashboard staff e scansione stand da fare.

`docs/06-assegnazione-task-bid.md`: **prima** chiedere a Mattia cosa fare della modifica a SHARED-01 già presente e non committata. Poi, nella sezione BID-06, aggiornare le note di `#35`…`#39` secondo la tabella della sezione 1 della specifica, senza dichiarare chiuse le issue.

- [ ] **Step 5: Verifica finale**

Run: `./mvnw test` in `backend/`; `npx ng test --watch=false` e `npx ng build` in `frontend/`; `git status --short`
Expected: tutto passa; nessun file imprevisto.

- [ ] **Step 6: Commit**

```bash
git add README.md frontend/README.md
git commit -m "BID-06: documentazione del portale espositori"
```

`docs/06-assegnazione-task-bid.md` si aggiunge al commit solo se Mattia ha approvato anche la modifica precedente.

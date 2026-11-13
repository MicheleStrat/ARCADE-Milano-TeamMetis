# B2 — Scheletro del backend Spring Boot: specifica

**Data:** 13 novembre 2026 · **Responsabile:** Mattia Billong · **Stato:** implementata; test automatici verdi (29); prova sul database locale `arcade-db` non ancora fatta (vedi backend/README.md)

## 1. Obiettivo

Un backend in `backend/` che si avvia in locale con `mvn spring-boot:run`, si collega al database `arcade-db` (Docker), autentica le richieste con un JWT, applica i ruoli e l'isolamento tra espositori, e legge dati reali.

Serve a sbloccare B3 (API commerciali), B20 (API KPI) e B21 (test di sicurezza). Non implementa nessuna logica commerciale.

**Criterio di riuscita:** con il database locale avviato, il backend parte; un token di sviluppo da staff legge `/editions`; un token da espositore legge solo i propri dati in `/portal/me`; un token da espositore non vede i dati di un altro espositore.

## 2. Decisioni già prese

| Tema | Decisione | Motivo |
|---|---|---|
| Avvio | Solo in locale (`mvn spring-boot:run`) contro `arcade-db`; il container del backend si aggiunge dopo | Sviluppo e prove più rapidi; il container è B17 |
| Login | Token di sviluppo (chiave locale); passaggio a Entra ID cambiando solo la configurazione | Entra ID non è configurato; permette di provare ruoli e isolamento ora |
| Accesso ai dati | Spring JDBC (SQL scritto a mano), non JPA | Ogni richiesta imposta ruolo e `app.exhibitor_id` nella stessa transazione; le viste `analytics` e `portal` si leggono con SQL |
| Accesso di Power Apps | Scritture solo via API; letture BI dirette con `arcade_bi` su `analytics` (decisione B1, [08-decisioni-condivise.md](../../08-decisioni-condivise.md)) | Concordata con il BAD |

## 3. Struttura

```
backend/
  pom.xml, mvnw, mvnw.cmd, .mvn/
  src/main/java/it/arcade/backend/
    BackendApplication.java
    config/       sicurezza, JWT, Flyway, DataSource
    security/     token di sviluppo, utente corrente, ruoli
    db/           esecuzione di una richiesta con ruolo e exhibitor_id
    api/          controller: health, me, editions, portal/me
    error/        mappatura degli errori in problem+json
  src/main/resources/
    application.yml, application-dev.yml
  src/test/java/...
```

Ogni parte ha un solo compito:

- **`security/`**: dato un JWT valido, produce l'utente corrente (ruoli ed eventuale `exhibitor_id`). Non conosce il database.
- **`db/`**: dato l'utente corrente e un'operazione, apre una transazione, imposta il ruolo del database e `app.exhibitor_id`, esegue l'operazione. È l'unico punto che fa `SET LOCAL ROLE`.
- **`api/`**: riceve la richiesta, chiede a `db/` di eseguire la query, restituisce il DTO del contratto OpenAPI.
- **`error/`**: converte ogni eccezione in `application/problem+json`.

## 4. Autenticazione e ruoli

- **Verifica.** Spring Security come resource server: valida firma, scadenza e ruoli del JWT. In sviluppo la chiave è HMAC (HS256), letta da una variabile d'ambiente (`JWT_DEV_SECRET`), non scritta nel repository. Per passare a Entra ID si sostituisce con l'indirizzo dell'emittente e le sue chiavi, senza modificare i controller.
- **Token di sviluppo.** `POST /dev/token` esiste **solo con il profilo `dev`**. Riceve il ruolo richiesto (e l'`exhibitor_id` per l'espositore) e restituisce un token con scadenza breve. Con un altro profilo l'endpoint non viene registrato.
- **Claim.** `sub` (utente), `roles` (elenco), `exhibitor_id` (solo per l'espositore).
- **Ruoli applicativi.** Quelli del contratto (`x-roles` in `docs/api/openapi.yaml`): `ADMIN`, `COMMERCIAL`, `OPS`, `EXHIBITOR`, `SCANNER`, `BI_READER`. Gli endpoint permessi a ciascuno si leggono dal contratto e non vengono ridefiniti qui. `ADMIN`, `COMMERCIAL` e `OPS` sono "staff" e usano il ruolo database `arcade_app`; `EXHIBITOR` usa `arcade_portal`.

## 5. Ruolo del database per richiesta

| Chi chiama | Ruolo database | Parametri di sessione |
|---|---|---|
| Staff | `arcade_app` | nessuno |
| Espositore | `arcade_portal` | `app.exhibitor_id` = valore del claim |

Per ogni richiesta: `BEGIN`, `SET LOCAL ROLE <ruolo>`, per l'espositore `set_config('app.exhibitor_id', '<id>', true)`, query, `COMMIT`. Senza `exhibitor_id` la RLS non restituisce righe (comportamento già definito in V3).

**Account di login del database.** Il backend si collega con un account dedicato (`arcade_backend`, `IN ROLE arcade_app, arcade_portal`, come previsto in V3), mai con il superutente. La sua password sta in `.env`, non nel repository. Uno script locale (`backend/scripts/crea-ruolo-backend.sql`, senza password) lo crea sul database di sviluppo.

## 6. Migrazioni (Flyway)

- Flyway legge le migrazioni da `database/migrations` (`classpath` non usato: nessuna copia dei file).
- Il database locale è già stato creato da quelle stesse migrazioni tramite Docker, senza lo storico di Flyway. `baselineOnMigrate` non è affidabile qui (lo schema `public` può sembrare vuoto e Flyway rieseguirebbe V1), quindi `BaselineExistingSchemaStrategy` controlla se esiste `core.edition`: se sì e lo storico manca, imposta il riferimento alla **versione 5** (`baseline-version: 5`) senza rieseguire nulla; se il database è vuoto migra normalmente.
- Flyway usa un account **diverso** da quello di esecuzione (`arcade_backend` non può creare tabelle). In sviluppo usa l'utente del database locale (`POSTGRES_USER`).
- Le migrazioni future (V6 e successive) si aggiungono nella stessa cartella.

**Rischio da verificare:** `docker-compose.yml` esegue le migrazioni all'avvio con volume vuoto, e Flyway le vedrebbe in una cartella montata. Va controllato che i due meccanismi non si pestino i piedi su un database nuovo.

## 7. Endpoint di B2

| Endpoint | Chi | Cosa fa |
|---|---|---|
| `GET /health` | Tutti (senza token) | Stato del backend e raggiungibilità del database |
| `GET /me` | Autenticato | Utente, ruoli ed eventuale `exhibitor_id` dal token |
| `GET /editions` | `ADMIN`, `COMMERCIAL`, `OPS`, `EXHIBITOR` (come da contratto) | Elenco delle edizioni dal `core` (dati pubblici, leggibili anche da `arcade_portal`) |
| `GET /portal/me` | Espositore | Dati dell'espositore corrente, letti con il ruolo `arcade_portal` |

Le risposte seguono i DTO di `docs/api/openapi.yaml`. Se un DTO nel contratto non coincide con ciò che la query restituisce, **si corregge il contratto con una pull request** e si avvisa il BAD (regole di modifica in `docs/api/README.md`).

## 8. Errori e log

- Ogni errore esce come `application/problem+json` con `type`, `title`, `status`, `detail` e un identificativo di richiesta, come da OpenAPI.
- `401` senza o con token non valido; `403` con ruolo non permesso; `404` risorsa assente; `500` mai con dettagli interni.
- Ogni richiesta ha un identificativo nei log. Nei log non finiscono token, password né dati personali.

## 9. Test

- **Unitari:** lettura del token e mappatura dei ruoli.
- **Integrazione, con PostgreSQL in container (Testcontainers)** su un database creato dalle migrazioni V1–V5, con dati di prova minimi:
  1. senza token → 401;
  2. token staff su `/editions` → 200 con dati;
  3. token espositore su `/editions` → 200 (permesso dal contratto); token `SCANNER` su `/editions` → 403;
  4. token espositore A su `/portal/me` → solo i dati di A;
  5. token espositore B → non vede nulla di A;
  6. espositore senza `exhibitor_id` → nessuna riga (fail-closed).
- B21 estenderà questi test con tentativi su URL e parametri.

## 10. Fuori da B2

Preventivi, contratti, acconti, anti-doppia vendita e `Idempotency-Key` (B3); API KPI e report espositore (B20); import e anomalie; container del backend e `docker-compose` (B17); Entra ID reale; Power Apps.

## 11. Cosa non sarà verificato in B2

- Compatibilità di Spring Boot 3.5 con Java 25: si prova alla prima compilazione; se non va, si scende a Java 21 e si aggiorna questa specifica.
- Passaggio a Entra ID: previsto nel disegno, non provato.
- Conformità completa al contratto OpenAPI: solo i quattro endpoint sopra.
- Comportamento sul server Azure reale: i test usano il database locale.

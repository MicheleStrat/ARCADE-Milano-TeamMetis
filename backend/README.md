# Backend ARCADE Milano (API base + B3a)

Spring Boot 3.5, Java 25, Maven (wrapper). Implementa le API base, il profilo minimo del portale e il percorso B3a preventivo→contratto del contratto `docs/api/openapi.yaml`:

- `GET /health`, `GET /me`, `GET /editions`, `GET /editions/{id}`, `GET /pavilions`, `GET /exhibitor-categories`.
- `GET /editions/{id}/floorplan`, `GET /editions/{id}/stands`, `GET /editions/{id}/price-list`, `PATCH /price-items/{id}`.
- `GET /exhibitors`, `POST /exhibitors`, `GET /exhibitors/{id}`, `PUT /exhibitors/{id}`; i contatti sono visibili solo a ADMIN e COMMERCIAL.
- `GET /portal/me`.
- `POST /quotes`, `GET /quotes/{id}`, `POST /quotes/{id}/send`, `POST /quotes/{id}/confirm`.
- `POST /quotes/{id}/contract`, `GET /contracts/{id}`.

Il token di sviluppo `POST /dev/token` è registrato solo con il profilo `dev`.

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

Servono Docker avviato (i test creano un PostgreSQL in container). I test non toccano il database locale.
La suite include test API per cataloghi e anagrafiche oltre ai flussi già implementati; per verificare la branch eseguire il comando sopra.

## Preventivi e contratti (B3a)

Endpoint: `POST /quotes` (con `Idempotency-Key`), `GET /quotes/{id}`, `POST /quotes/{id}/send` e `/confirm` (con `If-Match`), `POST /quotes/{id}/contract` (con `Idempotency-Key`), `GET /contracts/{id}`. Specifica: `docs/superpowers/specs/2026-11-16-b3a-contratto-venduto-design.md`.

Impostazioni (assunzioni da confermare): `arcade.quote.reservation-days` (14) e `arcade.contract.deposit-due-days` (15).

**Regola per le migrazioni dopo V5:** devono essere ripetibili (`IF NOT EXISTS`, vincoli protetti da `DO`), perché Docker le esegue su un volume nuovo e Flyway, che parte dal riferimento alla versione 5, può rieseguirle.

Limiti: il listino e le date 2026 reali non esistono nel database; la conversione risponde `422 EDITION_DATES_MISSING` finché mancano i giorni di apertura. Provato solo con dati di test.

## Limiti noti

- Il token di sviluppo usa una chiave locale: Entra ID non è configurato né provato.
- Restano fuori da questa task il report espositore (B20), gli altri operation commerciali B3b, KPI, operativi, ingestione e portale esteso.
- Provato solo sul database locale, non sul server Azure.

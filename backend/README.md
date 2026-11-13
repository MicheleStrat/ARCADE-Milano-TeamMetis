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

Servono Docker avviato (i test creano un PostgreSQL in container). I test non toccano il database locale.

## Limiti noti

- Il token di sviluppo usa una chiave locale: Entra ID non è configurato né provato.
- Solo quattro endpoint; il resto del contratto non è implementato.
- Provato solo sul database locale, non sul server Azure.

#!/usr/bin/env bash
# Salva i DATI del database sorgente (Azure) e li carica nel database Docker locale.
#
#   scripts/azure-db.sh backup                 salva i dati in local-data/arcade-data-AAAAMMGG-HHMMSS.dump
#   scripts/azure-db.sh restore-local [file]   SVUOTA i dati del database locale e carica il dump
#                                              (se manca il file usa il piu' recente in local-data/)
#
# La struttura (tabelle, viste, ruoli) NON e' nel dump: viene dalle migrazioni in database/migrations.
# Il database locale deve essere avviato con:  docker compose up -d
# I dump contengono dati del cliente: restano in local-data/ (ignorata da git). Non committarli.
# Configurazione: file .env (vedi .env.example). La password della sorgente non e' mai salvata:
# viene chiesta oppure letta da PGPASSWORD.
set -euo pipefail
export MSYS_NO_PATHCONV=1          # Git Bash su Windows: non alterare i percorsi /out
cd "$(dirname "$0")/.."

# Il file .env modificato con un editor di Windows ha i ritorni a capo CR+LF: senza toglierli ogni valore
# (utente, host, database) finirebbe con un carattere invisibile in piu' e l'accesso verrebbe rifiutato.
if [ -f .env ]; then set -a; . <(tr -d '\r' < .env); set +a; fi

PG_CLIENT_IMAGE="${PG_IMAGE:-postgres:16-alpine}"
DST_CONTAINER="${DST_CONTAINER:-arcade-db}"
DST_DB="${POSTGRES_DB:-arcade}"
DST_USER="${POSTGRES_USER:-postgres}"
SCHEMAS=(--schema=core --schema=staging --schema=dq)
HOSTDIR="$(pwd -W 2>/dev/null || pwd)"

cmd="${1:-}"
case "$cmd" in
  backup)
    : "${SRC_HOST:?Compila SRC_HOST nel file .env}"
    : "${SRC_DB:?Compila SRC_DB nel file .env}"
    : "${SRC_USER:?Compila SRC_USER nel file .env}"
    if [ -z "${PGPASSWORD:-}" ]; then
      read -r -s -p "Password di ${SRC_USER}@${SRC_HOST}: " PGPASSWORD; echo
    fi
    PGPASSWORD="${PGPASSWORD%$'\r'}"   # la console di Windows aggiunge un CR alla riga digitata
    export PGPASSWORD
    mkdir -p local-data
    name="arcade-data-$(date +%Y%m%d-%H%M%S).dump"
    echo "Salvo i dati di ${SRC_DB} su ${SRC_HOST} (solo dati degli schemi core, staging, dq)..."
    docker run --rm -e PGPASSWORD -v "$HOSTDIR/local-data:/out" "$PG_CLIENT_IMAGE" \
      pg_dump "host=${SRC_HOST} port=${SRC_PORT:-5432} dbname=${SRC_DB} user=${SRC_USER} sslmode=${SRC_SSLMODE:-require}" \
      --data-only --format=custom --no-owner --no-privileges "${SCHEMAS[@]}" --file="/out/$name" \
      || { rm -f "local-data/$name"; echo "Backup NON riuscito: file parziale rimosso." >&2; exit 1; }
    echo "Fatto: local-data/$name ($(du -h "local-data/$name" | cut -f1))"
    ;;

  restore-local)
    file="${2:-}"
    if [ -z "$file" ]; then file="$(ls -1t local-data/*.dump 2>/dev/null | head -1 || true)"; fi
    [ -n "$file" ] && [ -f "$file" ] || { echo "Nessun dump trovato: esegui prima 'backup' o indica il file." >&2; exit 1; }
    docker inspect -f '{{.State.Running}}' "$DST_CONTAINER" 2>/dev/null | grep -q true \
      || { echo "Il database locale '$DST_CONTAINER' non e' avviato: esegui 'docker compose up -d'." >&2; exit 1; }
    echo "ATTENZIONE: i dati del database locale '$DST_CONTAINER' verranno cancellati e sostituiti con $file."
    if [ "${ASSUME_YES:-}" != "1" ]; then
      read -r -p "Continuo? (scrivi si) " ans; [ "$ans" = "si" ] || { echo "Annullato."; exit 1; }
    fi
    echo "1/3 Svuoto i dati locali (la struttura resta)..."
    docker exec -i "$DST_CONTAINER" psql -U "$DST_USER" -d "$DST_DB" -v ON_ERROR_STOP=1 -q <<'SQL'
SET client_min_messages = warning;
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT format('%I.%I', schemaname, tablename) FROM pg_tables
            WHERE schemaname IN ('core', 'staging', 'dq')
  LOOP
    EXECUTE 'TRUNCATE TABLE ' || t || ' RESTART IDENTITY CASCADE';
  END LOOP;
END $$;
SQL
    echo "2/3 Carico i dati da $file..."
    docker exec -i "$DST_CONTAINER" pg_restore -U "$DST_USER" -d "$DST_DB" \
      --data-only --no-owner --no-privileges --disable-triggers --exit-on-error < "$file"
    echo "3/3 Righe nelle tabelle principali:"
    docker exec -i "$DST_CONTAINER" psql -U "$DST_USER" -d "$DST_DB" -At -F ' : ' <<'SQL'
SELECT 'core.exhibitor', count(*) FROM core.exhibitor
UNION ALL SELECT 'core.contract', count(*) FROM core.contract
UNION ALL SELECT 'core.ticket', count(*) FROM core.ticket
UNION ALL SELECT 'core.gate_reading', count(*) FROM core.gate_reading
UNION ALL SELECT 'core.stand_visit_hourly', count(*) FROM core.stand_visit_hourly
UNION ALL SELECT 'dq.anomaly', count(*) FROM dq.anomaly;
SQL
    ;;

  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

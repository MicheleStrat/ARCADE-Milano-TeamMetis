# Database su Azure e copia locale in Docker

Aggiornato: 9 novembre 2026

## Come stanno le cose

| | Azure | Docker locale |
|---|---|---|
| Servizio | Azure Database for PostgreSQL | PostgreSQL 16 in un container sul PC |
| Ruolo | **Database condiviso** (Power Apps, Power BI, demo, dati caricati) | **Copia** per i test e come riserva |
| Chi lo usa | Tutto il team | Ognuno sul proprio PC |
| Struttura | Migrazioni `V1..V5` | Le stesse migrazioni, applicate automaticamente |
| Dati | Quelli veri caricati | Vuoti, oppure copiati da Azure con lo script |

**I due database non si sincronizzano da soli.** Sono indipendenti: la copia locale è una fotografia dei dati di Azure al momento in cui la scatti. Se cambiano i dati su Azure, la copia resta com'era finché non la rifai.

## Avvio del database locale

1. Copia `.env.example` in `.env` e scegli `POSTGRES_PASSWORD` (serve solo per il database locale; non riusare password vere).
2. Avvia:

```bash
docker compose up -d
```

Al primo avvio PostgreSQL esegue `database/migrations/V1..V5` in ordine. Se una migrazione fallisce il database non parte (voluto). Il database è raggiungibile solo da questo computer (`127.0.0.1`).

3. Verifica:

```bash
docker exec arcade-db psql -U postgres -d arcade -c "SELECT count(*) FROM information_schema.tables WHERE table_schema IN ('core','staging','dq');"
```

Risultato atteso: `58`.

Per ripartire da zero (cancella i dati locali e rilegge le migrazioni; serve lo stesso file `.env`):

```bash
docker compose down -v
```

## Copiare i dati da Azure al database locale

La struttura viene dalle migrazioni, i **dati** dal dump.

1. Nel file `.env` compila `SRC_HOST`, `SRC_DB`, `SRC_USER` (e `SRC_SSLMODE=require`). **La password non va nel file**: lo script la chiede.
2. Il tuo indirizzo IP deve essere autorizzato nel firewall del server Azure.
3. Salva i dati:

```bash
bash scripts/azure-db.sh backup
```

4. Carica la copia nel database locale (cancella i dati locali e li sostituisce):

```bash
bash scripts/azure-db.sh restore-local
```

Il file del dump finisce in `local-data/`, cartella esclusa da Git. Contiene **dati del cliente**: non committarlo, non inviarlo e cancellalo quando non serve.

## Se si perde il database su Azure

Procedura di ripristino, **non ancora provata su Azure**:

1. Crea un nuovo database PostgreSQL su Azure e consenti l'estensione `pg_trgm` (parametro `azure.extensions`).
2. Applica `V1..V5` in ordine, con un utente che può creare ruoli.
3. Carica i dati dall'ultimo dump:

```bash
docker run --rm -e PGPASSWORD -v "$(pwd)/local-data:/in" postgres:16-alpine pg_restore -d "host=<server> dbname=<db> user=<utente> sslmode=require" --data-only --no-owner --no-privileges --exit-on-error /in/<file>.dump
```

4. Ricrea gli account di login dei ruoli (`arcade_app`, `arcade_portal`, `arcade_etl`, `arcade_bi`), le cui password non sono nel dump né nel repository.

Azure di norma conserva anche backup automatici del server, per alcuni giorni: va controllato nel portale e non sostituisce un dump tuo, ma è la prima cosa da provare.

## Cosa contiene e cosa no il dump

| Incluso | Non incluso |
|---|---|
| Dati degli schemi `core`, `staging`, `dq` | Struttura (viene dalle migrazioni) |
| | Ruoli e password del database |
| | Impostazioni del server |

## Cosa è stato provato e cosa no

| Verificato | Non verificato |
|---|---|
| Avvio con `docker compose`, rifiuto senza password, 58 tabelle, 4 procedure V5, 38 regole, 4 ruoli | Collegamento a **Azure reale**: la prova è stata fatta con un secondo PostgreSQL locale al posto di Azure |
| Salvataggio e ripristino: 58 tabelle e 292 righe identiche tra origine e copia, campi binari uguali | Versione di PostgreSQL del server Azure (deve avere la stessa versione maggiore di `PG_IMAGE`) |
| Ripristino ripetuto senza duplicati; identificativi che ripartono senza collisioni | Ripristino su Azure, firewall e SSL |
| | Prestazioni con milioni di righe (il caricamento completo di biglietteria e tornelli porta alcune centinaia di migliaia di righe) |

## Precauzioni

- **Versione**: se il server Azure usa PostgreSQL 17, imposta `PG_IMAGE=postgres:17-alpine` nel file `.env`, altrimenti il dump non è leggibile.
- **Password**: mai nei file del repository. Per Azure sono richieste solo al momento dell'uso.
- **Test distruttivi**: eseguili sul database locale, non su quello condiviso.
- **Costi su Azure**: i crediti sono limitati, quindi conviene spegnere il server quando non serve.

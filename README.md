# ARCADE Milano — Team Metis (ramo BID)

Piattaforma integrata per la gestione commerciale, operativa e analitica di **ARCADE Milano**, festival fittizio del videogioco organizzato da Factory Studios. Progetto formativo.

Questo ramo contiene l'area **BID**: database PostgreSQL, (in futuro) backend Java/Spring Boot, ETL e interfacce Web. L'area Power Platform (Power Apps, Power Automate, Power BI) è sul ramo `BAD`.

## Stato reale

| Componente | Stato |
|---|---|
| Schema PostgreSQL (V1–V4) | **Scritto e provato** su PostgreSQL 16 con dati di prova |
| Dati di riferimento e regole di qualità | **Scritti** (V2) |
| Ruoli, grant e Row Level Security | **Scritti e provati** in SQL |
| Schemi `analytics` e `portal` (KPI) | **Scritti e provati** con dati di prova |
| ETL / caricamento dei file del cliente | **Da fare** |
| Backend Spring Boot e contratto API | **Da fare** |
| Frontend Angular (dashboard staff, portale espositori, scansione stand) | **Da fare** |
| Integrazione con Power Apps / Power BI | **Da configurare** (dipende da tenant e licenze Microsoft) |

Nessun dato del cliente è ancora stato caricato nel database. I KPI su dati reali non sono stati calcolati.
Cosa è stato provato e cosa no è nel dettaglio in [docs/01-lavoro-svolto.md](docs/01-lavoro-svolto.md).

## Struttura

```
database/
  migrations/   V1 schema · V2 dati di riferimento · V3 ruoli e RLS · V4 analytics e portal
  tests/        script SQL di prova (vincoli, KPI, sicurezza)
docs/           documentazione (parti dall'indice)
divisione-bid-bad-integrazione.md   chi fa cosa e come si collegano i componenti
```

## Documentazione

Parti da [docs/00-indice.md](docs/00-indice.md).

| File | Contenuto |
|---|---|
| [docs/01-lavoro-svolto.md](docs/01-lavoro-svolto.md) | Cosa è stato fatto e come è stato verificato |
| [docs/02-guida-database.md](docs/02-guida-database.md) | Come è fatto il database, avvio locale e test |
| [docs/03-lavoro-futuro.md](docs/03-lavoro-futuro.md) | Attività rimanenti con scadenze |
| [docs/04-domande-cliente.md](docs/04-domande-cliente.md) | Domande per il cliente, ordinate per priorità |
| [docs/data-model.md](docs/data-model.md) | Progettazione tecnica completa del modello dati |
| [divisione-bid-bad-integrazione.md](divisione-bid-bad-integrazione.md) | Divisione dei compiti BID/BAD e integrazione |

## Avvio rapido del database (locale, con Docker)

Dettagli e risoluzione dei problemi: [docs/02-guida-database.md](docs/02-guida-database.md).

```bash
docker run -d --name arcade-db -e POSTGRES_PASSWORD=test -e POSTGRES_DB=arcade -v "$(pwd)/database/migrations:/m:ro" postgres:16-alpine
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V1__core_schema.sql
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V2__reference_data.sql
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V3__roles_grants_rls.sql
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V4__analytics.sql
```

La password `test` serve **solo** per prove locali con un database usa e getta. Nel repository non ci sono password, token o segreti: gli account di login dei ruoli del database si creano per ambiente.

## Limiti noti

- I file di migrazione seguono la convenzione di Flyway ma non sono stati eseguiti con Flyway.
- Le presenze nei padiglioni sono solo **stimate**: i tornelli non registrano le uscite.
- Il costo per contatto qualificato non è calcolabile con i dati ricevuti.
- Le domande al cliente (`docs/04-domande-cliente.md`) sono ancora senza risposta.

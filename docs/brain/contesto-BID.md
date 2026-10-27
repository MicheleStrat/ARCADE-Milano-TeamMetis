# ARCADE Milano — Contesto team BID ("Team Redis")

> **Proprietario: team BID.** Questa prima versione l'ha ricostruita il BAD dallo zip `Progetto_Team_Redis`. Da qui in avanti la aggiorna solo il BID, che deve anche verificarla.
> Collegamenti: [[00-indice]] · [[contesto-BAD]] · [[decisioni-condivise]]

Ultimo aggiornamento: 23 ottobre 2026 (fonte: zip `Progetto_Team_Redis` ricevuto dal BID)
Regola: qui si registra cosa ha fatto e deciso il BID. Le decisioni BAD stanno in [[contesto-BAD]].

## Stack e perimetro
- Stack: PostgreSQL 16, Java Spring Boot (monolite modulare), ETL, Angular.
- Perimetro: database, backend e API, ETL dai file del cliente, frontend Angular (dashboard staff, portale espositori, PWA scansione stand), test, DevOps (docker-compose).

## Decisioni del BID
| # | Decisione |
|---|---|
| R-01 | Architettura semplice: un backend Spring Boot, un PostgreSQL, niente microservizi |
| R-02 | PostgreSQL è la fonte unica di verità; le app comunicano tramite API |
| R-03 | Power Apps e Power Automate usano **solo le API** (custom connector da OpenAPI + Entra ID OAuth2). Power BI è l'unico che legge il DB, solo viste `analytics` |
| R-04 | Logica critica (doppia vendita, importi, stati) nel backend, non in Power Apps |
| R-05 | Angular e Power Apps restano frontend separati, collegati da link `Launch(...)`; no embedding |
| R-06 | Privacy: email dei contatti salvate solo come hash; 14 contatti minorenni in revisione |
| R-07 | Presenze solo **stimate** (tornelli senza uscite, permanenza ipotetica 90′) |
| R-08 | Nessun dato scartato in silenzio: anomalie in `dq.anomaly`, record dubbi in `dq.quarantine` |

## Lavoro svolto (dichiarato dal BID)
| Cosa | Stato |
|---|---|
| Analisi del brief e profiling dei file del cliente (135 espositori, 130 stand, 198 contratti, ~78k biglietti, ~103k passaggi tornelli) | Fatto |
| Migrazioni V1 (schema: `core`, `staging`, `dq`, 58 tabelle), V2 (dati di riferimento, 37 regole qualità) | Scritte e provate su PostgreSQL 16 in Docker |
| V3 ruoli e RLS (`arcade_app`, `arcade_portal`, `arcade_etl`, `arcade_bi`), V4 schema `analytics` e `portal` con i KPI | Scritte e provate con dati sintetici |
| Test SQL (`constraints_smoke`, `kpi_rls_smoke`) | Salvati in `database/tests/` |
| Domande al cliente D1–D23 + interne T1–T4 | Pronte, **ancora senza risposta** |

## Non ancora fatto (dichiarato dal BID)
ETL e caricamento dati reali, backend Java, contratto OpenAPI (solo bozza), frontend Angular, test con Flyway, test di prestazioni.

## Punti che toccano il BAD (da discutere, nessuna decisione presa)
| Punto | Conflitto o dipendenza |
|---|---|
| R-03 vs decisione BAD B-02 | **Risolto il 23/10**: si usa l'on-premises data gateway (decisione B-07). Backend e DB restano in locale |
| Domanda T1 (licenze premium) | Parzialmente risposta dal BAD: ambiente Developer con connettori premium |
| Domanda T2 (dove gira il backend) | Risposta: in locale, raggiunto via gateway |
| Domanda T3 (Power BI) | Risposta: Power BI Service tramite gateway (decisione BAD B-09) |
| R-03 vs decisione BAD B-08 | **Conflitto da comunicare**: il BAD ha scelto l'accesso diretto di Power Apps a PostgreSQL, non via API. Va concordato col BID quali regole restano nel DB e un utente DB dedicato a Power Apps |
| Domanda T4 (Entra ID) | Per Power Apps non serve più (niente custom connector); resta aperta solo per il backend/portale BID |
| App di scansione allo stand | Il BID la mette nella PWA Angular, il PDF ufficiale la assegna al BAD: da chiarire |
| Congelamento schema 30/10 | Il BID aspetta la revisione del BAD su V1–V4 |

## Avanzamenti successivi
| Data | Cosa |
|---|---|
| 23/10 | Ricezione della documentazione BID da parte del BAD |
| 23/10 | Scelto l'on-premises data gateway per il collegamento Power Platform → backend locale (decisione B-07) |
| 24/10 | Il BAD sceglie accesso diretto a PostgreSQL da Power Apps (B-08) e Power BI Service (B-09): da comunicare al BID |

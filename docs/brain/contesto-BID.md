# ARCADE Milano — Contesto team BID

> **Proprietario: team BID.** Lo aggiorna solo il BID.
> Collegamenti: [[00-indice]] · [[contesto-BAD]] · [[decisioni-condivise]] · [[anomalie-dati]] · [[kpi]] · [[calendario]]

Ultimo aggiornamento: 11 novembre 2026. È la sintesi in un solo file della documentazione del ramo `BID` (commit `acf8ca0` del 9/11: `README.md`, `divisione-bid-bad-integrazione.md`, `docs/00…07`, `docs/data-model.md`, `docs/api/README.md`, `docs/api/openapi.yaml`). L'ha compattata il BAD: il BID deve verificarla. Per i dettagli tecnici fa fede il ramo `BID`.

Regola: qui si registra cosa ha fatto e deciso il BID. Le decisioni BAD stanno in [[contesto-BAD]].

## Team e regole di lavoro
- **Mattia Billong** (team leader), **Alessandro De Filippis**, **Michele Strat**, **Andrea Cacioppo**.
- Nessun push diretto su `BID`: ognuno lavora sul suo ramo (`nome-argomento`) e apre una pull request, che il team leader rivede e unisce.
- Ogni task consegnato dice: file modificati, come si esegue, cosa è stato provato davvero e cosa no.
- Niente dati personali, password o segreti nel repository. I dati sintetici sono sempre marcati demo.
- Si distingue sempre tra *implementato*, *testato*, *simulato* e *da configurare*.

## Stack e perimetro
- Stack: PostgreSQL 16, Java Spring Boot (monolite modulare), ETL in SQL, Angular, docker-compose.
- Perimetro BID: database e migrazioni, ETL dai file del cliente, backend e API, frontend Angular (dashboard staff, portale espositori, app di scansione stand), test, DevOps.
- Perimetro BAD secondo il BID: processo commerciale, Power Apps back-office, Power Automate, Power BI direzionale (5 pagine), solution versionata in `power-platform/`.
- Da fare insieme: schema dati, contratto API, definizioni dei KPI, regole di qualità, privacy, test di integrazione, riconciliazione, demo.

## Decisioni del BID
| # | Decisione |
|---|---|
| R-01 | Architettura semplice: un backend Spring Boot, un PostgreSQL, niente microservizi |
| R-02 | PostgreSQL è la fonte unica di verità; le app comunicano tramite API e contratti espliciti |
| R-03 | Power Apps e Power Automate usano **solo le API** (custom connector da OpenAPI + Entra ID). Power BI è l'unico a leggere il DB, solo dalle viste `analytics`, con ruolo di sola lettura |
| R-04 | La logica critica (doppia vendita, importi, stati) sta nel backend e nei vincoli del DB, non in Power Apps |
| R-05 | Angular e Power Apps restano due frontend separati, collegati da un link `Launch(...)`. Niente Angular dentro Power Apps |
| R-06 | Privacy: l'email dei contatti stand non entra nel `core`, solo un hash. Contatti dei minori in revisione privacy |
| R-07 | Le presenze sono solo **stimate**: i tornelli non hanno uscite, permanenza ipotetica 90′, calcolo ogni 15′ |
| R-08 | Nessun dato scartato in silenzio: anomalie in `dq.anomaly`, record dubbi in `dq.quarantine` con la riga originale |
| R-09 | Ogni KPI ha **una sola definizione**, in una vista SQL: API, portale e Power BI leggono le stesse viste |
| R-10 | Importare due volte lo stesso file non duplica nulla (impronta SHA-256 del file e chiave per riga) |
| R-11 | Listini 2024 e 2025 **ricostruiti** dalle righe contratto, marcati `RECONSTRUCTED_FROM_CONTRACTS`, da far validare |
| R-12 | Portale espositori: ogni espositore vede solo i suoi dati (backend + RLS, fail-closed). Il confronto di mercato è solo aggregato, con almeno 5 espositori per categoria |
| R-13 | Il **DB condiviso è Azure** Database for PostgreSQL; il Docker locale è solo una copia per test e riserva. I due non si sincronizzano da soli: la copia si rifà con `scripts/azure-db.sh` |
| R-14 | Dopo il congelamento, schema e API cambiano solo con modifica concordata: compatibile → si aggiunge; incompatibile → `/api/v2`. Sempre con PR che descrive l'effetto su BAD e Angular |

## Database
**Schemi**: `staging` (copia grezza dei file, tutto testo), `core` (dati veri con vincoli), `dq` (batch, regole, anomalie, quarantena, riconciliazioni), `analytics` (dimensioni, fatti, KPI), `portal` (viste per gli espositori).

**Idee chiave**: stand fisico ≠ occupazione nell'edizione (`stand` / `stand_edition`); azienda ≠ contratto (`exhibitor` / `contract`); doppia vendita impossibile per vincolo (`ux_contract_stand_active`); fusi orari gestiti, tutto in `timestamptz`, giorno calcolato in `Europe/Rome`.

**Migrazioni**
| File | Contenuto | Stato dichiarato dal BID |
|---|---|---|
| V1 | Schemi `core`, `staging`, `dq`: 58 tabelle, 3 viste di controllo | Provata, 8 test sui vincoli come atteso |
| V2 | Dati di riferimento, 37 regole di qualità (poi 38), 8 controlli di riconciliazione | Provata |
| V3 | Ruoli, grant, RLS | Provata in SQL |
| V4 | Schemi `analytics` e `portal` con i KPI | Provata con dati sintetici |
| V5 | Caricamento biglietteria, tornelli (2024-2025) e visite stand (2025) | Verificata sui file reali per biglietteria e tornelli (4/11); visite solo con dati sintetici |

**Ruoli del DB**
| Ruolo | Chi | Può fare |
|---|---|---|
| `arcade_app` | backend (staff) | legge e scrive `core`; audit solo in aggiunta |
| `arcade_portal` | backend per un espositore | sola lettura, solo le proprie righe (RLS) |
| `arcade_etl` | caricamento dati | scrive `staging` e `core`, non cancella dal `core` |
| `arcade_bi` | Power BI | solo lo schema `analytics` |

Gli account di login si creano per ambiente; le password non stanno nel repository.

**Esito V5 sui file reali** (4/11): biglietteria e tornelli 2024/2025 caricati per intero, quarantena 0, riconciliazioni REC-02 e REC-03 in accordo. Le anomalie sono in [[anomalie-dati]].

**Azure** (9/11): backup da Azure reale provato con l'utente `arcade_bid_etl` (dump di 6,2 MB, ripristinato in Docker con 135 espositori, 198 contratti, 78.275 biglietti, 102.816 letture varchi, 2.451 visite stand, 48.967 anomalie). **Non provato**: il ripristino *verso* Azure.

## KPI (viste `analytics`)
| KPI | Vista | Definizione del BID |
|---|---|---|
| Visitatori | `kpi_visitors_edition`, `_daily` | Venduti, persone, validati, passaggi, ingressi-giorno: misure diverse, **non si sommano**. Le persone uniche non sono calcolabili |
| Picco presenze | `kpi_presence_peak`, `presence_estimate()` | Stima, permanenza 90′, padiglioni non sommabili |
| Saturazione | `kpi_saturation` | m² venduti / m² commercializzabili |
| Ricavo e ricavo/m² | `kpi_commercial_edition`, `kpi_space_revenue_pavilion` | Contrattualizzato netto sconto, IVA esclusa. Ricavo/m² = (spazio + maggiorazioni) / m² venduti; extra e sponsor a parte. Incassato separato |
| Costo per contatto | `kpi_exhibitor_edition` | **Non calcolabile** (mancano costi e definizione di "qualificato"); sostituito da `contract_value_per_visit` |
| Confronto edizioni, rinnovo | `kpi_edition_comparison`, `kpi_renewal_edition` | Variazione vuota se mancano dati (niente falsi −100 %) |
| Qualità dati, riconciliazione | `kpi_data_quality_*`, `reconciliation_status` | Riconciliazione deve dire `MATCH` |

Le definizioni concordate tra i team sono in [[kpi]].

## Contratto API (`docs/api/openapi.yaml`)
Bozza v1.0.0, **non congelata e non implementata**: 58 operazioni su 53 percorsi, OpenAPI 3.0.3, validata con `@redocly/cli`.
- Base `/api/v1`; date `YYYY-MM-DD`, istanti UTC; importi in euro IVA esclusa; il server calcola i prezzi, il client no.
- Errori `application/problem+json` con codice stabile (es. `STAND_ALREADY_SOLD`, `QUOTE_NOT_CONFIRMED`, `OPTIMISTIC_LOCK_CONFLICT`, `PAYMENT_EXCEEDS_CONTRACT`).
- `Idempotency-Key` obbligatoria su preventivi, conversione in contratto, pagamenti, prelazioni, acquisizione dati, importazioni. `rowVersion` + `If-Match` sulle azioni di stato.
- Ruoli: `ADMIN`, `COMMERCIAL`, `OPS`, `EXHIBITOR`, `SCANNER`, `BI_READER`. Il portale (`/portal/me/**`) non accetta mai un `exhibitorId` dal client e risponde 404 per le risorse altrui.
- Conversione preventivo → contratto: un'unica operazione transazionale (`POST /quotes/{id}/contract`).
- Importazione in Power Platform **mai provata**; autenticazione Entra ID da configurare.

## Domande al cliente (`docs/04-domande-cliente.md`)
- **P1** (entro 30/10) D1–D10, **P2** (entro 13/11) D11–D18 e D24–D27, **P3** (entro 27/11) D19–D23 e D28–D32. Interne al team: T1–T4.
- **Risolte il 9/11**: D24 (letture prima dell'acquisto, GAT-006), D25 (visite fuori orario, VIS-003), D26 (esiti KO, GAT-003), D27 (codici inesistenti, GAT-001), D28 (superficie lorda di edificio e padiglioni). Gli esiti **non sono ancora scritti** nel file.
- **Chiuse il 9/11**: D30, il cliente non ha una planimetria e si usa quella di Rho Fiera come riferimento, con le posizioni degli stand disegnate a mano; D31, dalle telecamere solo conteggi aggregati, nessuna immagine nel DB (resta da chiarire chi fa l'informativa privacy e dove si montano).
- **Aperte**: D1–D23, D29 (stand fissi o modulari), D32 (sito pubblico di prenotazione: chi incassa, condizioni, IVA).

## Task BID (`docs/06-assegnazione-task-bid.md`, proposta del team leader)
| Chi | Task | Scadenza |
|---|---|---|
| Mattia | B4 contratto OpenAPI da congelare · B1 decisione Power Apps API o accesso diretto · B5 revisione e unione V5, congelamento schema | 6/11 |
| Mattia | B2 scheletro backend (Flyway, JWT, ruoli) · B3 API commerciali con anti-doppia vendita e idempotenza | 10/11 · 12/11 |
| Mattia | B21 test di sicurezza via backend | dopo il 13/11 |
| Alessandro | B7 caricamento Excel commerciale · B8 riconciliazione nomi 2024 · B9 orchestratore caricamento CSV | 10-11/11 |
| Alessandro | B12 riconciliazioni REC-01…08 · B11 prestazioni · B20 API KPI e report espositore | 12/11 · dopo il 13/11 |
| Michele | B13 progetto Angular · B14 dashboard staff con indicatore demo/reale · B15 generatore eventi demo | 9/11 · 12/11 · dopo il 13/11 |
| Andrea | B17 docker-compose · B16 portale espositori · B18 documentazione · B19 casi di prova | 9/11 · 12/11 · continuo · 11/11 |

Opzionali dopo il SAL 2 (da validare col cliente): mappa interattiva degli stand con riserva a tempo, sito pubblico di prenotazione, conteggio persone con sensori (solo simulato).

## Stato reale
**Fatto**: schema V1–V4 con test; V5 verificata su biglietteria e tornelli reali; bozza OpenAPI; DB su Azure con backup provato; `docker compose` per la copia locale; domande al cliente D1–D32.

**Non ancora fatto** (dichiarato dal BID): backend Java, frontend Angular, contratto API congelato, test con Flyway, prestazioni su volumi reali, test di isolamento attraverso il backend. Alcune regole di qualità non hanno ancora una misura (TKT-007, GAT-004, COM-*).

⚠️ I documenti del BID non sono allineati tra loro: `README.md` e `01-lavoro-svolto.md` dicono "nessun dato del cliente caricato", mentre `07-database-azure-e-docker.md` (9/11) descrive il DB su Azure con i dati veri. Vale il più recente.

## Punti che toccano il BAD (da discutere)
| Punto | Posizione BID | Situazione lato BAD |
|---|---|---|
| Accesso di Power Apps ai dati (task B1) | Solo API (R-03). Se prevale l'accesso diretto, preventivi, contratti e pagamenti restano comunque nell'API | Accesso diretto a PostgreSQL già in uso (B-08); conversione preventivo → contratto via API quando sarà pubblicata (A-08) |
| Caricamento dati reali (B7, B8, B9) | Assegnato ad Alessandro | Già fatto dal BAD l'8/11 con V6 e V5 del BID, 9 nomi 2024 confermati (B-32, B-33) |
| Contatti dei minori (LED-002) | Quarantena | Caricati con `PRIVACY_REVIEW`, fuori da KPI e portale (B-34) |
| Lettura ai varchi e generatore demo | App di scansione web (attività 20 in `03-lavoro-futuro`) e generatore di eventi demo (B15) | App scanner in Power Apps (B-23); agli stand QR + telecamere simulate (B-25) |
| Chiavi per Power Apps | — | V8 eseguita su Azure dal BAD l'11/11 (B-38): output dei test BID identico |
| Congelamento schema | Era il 30/10, serve confermare lo stato e unire la V5 | V5 aggiornata sul server; V6, V7, V8 del BAD da portare nel repo con una PR |
| Ruoli nelle app | Ruoli API `ADMIN`…`BI_READER` | Aggiunto `DIRECTION` in `core.app_role` (B-36) |

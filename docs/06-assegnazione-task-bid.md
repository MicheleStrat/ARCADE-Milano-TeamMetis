# Assegnazione dei task BID

Aggiornato: 16 novembre 2026 · Team leader: Mattia Billong

**I task di questo documento sono quelli delle issue su GitHub** (repository `MicheleStrat/ARCADE-Milano-TeamMetis`): stessi codici, stessi titoli, stesso numero di issue. Le issue sono la fonte; qui si aggiungono responsabile, note e punti aperti. Il Project di GitHub non è stato letto (non è pubblico): se ha stati propri, vanno ricontrollati lì.

Lo **stato** (aperta/chiusa) è quello delle issue al 16/11. Le **note** sono mie, ricostruite dal repository e da quanto dichiarato dal team leader.

## Stato in sintesi

| Area | Issue | Stato | Responsabile |
|---|---|---|---|
| Analisi e profilazione dei dati | BID-01 | Chiusa | Michele |
| Modello dati condiviso | BID-02 | Chiusa | Michele |
| Pipeline di acquisizione dati | BID-03 | Chiusa su GitHub (PR #96 unita); Alessandro la rimette in corso | Alessandro |
| API REST Spring Boot | BID-04 | **Aperta** (Alessandro la mette in corso) | Alessandro; nel repository c'è già il backend di B2 e B3a (Mattia) |
| Dashboard operativa per lo staff | BID-05 | **Aperta** | Mattia |
| Portale web per gli espositori | BID-06 | **Aperta** | Mattia |

Le assegnazioni sono quelle delle issue su GitHub al 16/11. **Andrea non ha issue BID assegnate.** Le issue SHARED-01 non sono in questo documento.

## Date

Il SAL 2 è stato spostato. Non ci sono nuove scadenze per i singoli task.

| Data | Evento |
|---|---|
| **Ven 4/12** | **SAL 2**: edizioni 2024/2025 caricate, anomalie e riconciliazione, un contratto 2026 venduto, prime dashboard |
| Ven 4/12 | Presentazione finale |

## Regole di lavoro

- Nessun push diretto su `BID`: ogni persona lavora sul proprio ramo (`nome-argomento`) e apre una pull request.
- Il team leader rivede e unisce le PR.
- Ogni task consegnato riporta: file modificati, come eseguirlo, cosa è stato provato davvero e cosa no.
- Niente dati personali o segreti nel repository.

---

## BID-01 — Analisi e profilazione dei dati sorgente (`#2`, chiusa)

Responsabile: Michele.

| Issue | Task | Stato |
|---|---|---|
| `#4` | BID-01-01 Esaminare i file di biglietteria, letture ai tornelli e visite agli stand. | Chiusa |
| `#5` | BID-01-02 Verificare colonne, formati, identificativi e relazioni tra file | Chiusa |
| `#7` | BID-01-03 Individuare duplicati, valori nulli, date incoerenti e riferimenti mancanti. | Chiusa |
| `#8` | BID-01-04 Documentare le anomalie e proporre le regole di correzione | Chiusa |
| `#9` | BID-01-05 Concordare con il team BAD le anomalie che riguardano i dati commerciali. | Chiusa |
| `#6` | BID-01-01 Esaminare i file di biglietteria… (stesso titolo di `#4`) | **Aperta**: doppione di `#4` |

## BID-02 — Progettazione del modello dati condiviso PostgreSQL (`#10`, chiusa)

Responsabile: Michele.

| Issue | Task | Stato |
|---|---|---|
| `#11` | BID-02-01 Identificare entità, relazioni e identificativi univoci. | Chiusa |
| `#12` | BID-02-02 Progettare tabelle, chiavi primarie, chiavi esterne e vincoli. | Chiusa |
| `#13` | BID-02-03 Modellare edizioni, espositori, stand, padiglioni, contratti, biglietti, accessi e visite. | Chiusa |
| `#14` | BID-02-04 Progettare la struttura adatta alle analisi e ai confronti tra edizioni. | Chiusa |
| `#15` | BID-02-05 Condividere lo schema con il BAD e documentarlo. | Chiusa |

Nota: la V6 di B3a (16/11) ha aggiunto `stand_edition.reserved_by_quote_id` e la tabella `core.idempotency_key`: lo schema non è più quello congelato. Da confermare con Michele, Alessandro e il BAD.

## BID-03 — Sviluppo delle pipeline di acquisizione dati (`#16`, chiusa)

Responsabile: Alessandro. Pipeline unita su `BID` con la PR #96; V5 e correzioni con la PR #89. Le issue sono chiuse su GitHub, ma Alessandro la rimette in corso.

| Issue | Task | Stato |
|---|---|---|
| `#17` | BID-03-01 Sviluppare i processi di importazione dai file sorgente. | Chiusa |
| `#18` | BID-03-02 Validare i record prima del caricamento. | Chiusa |
| `#19` | BID-03-03 Gestire duplicati, valori mancanti ed errori di formato. | Chiusa |
| `#20` | BID-03-04 Registrare gli errori di importazione e il numero di record elaborati. | Chiusa |
| `#21` | BID-03-05 Predisporre l'elaborazione dei nuovi eventi di scansione in modo da aggiornare le viste operative. | Chiusa |

## BID-04 — API REST con Java e Spring Boot (`#22`, aperta)

Responsabile: Alessandro. **Nel repository c'è già un backend Spring Boot**, scritto da Mattia (B2 e B3a, PR #95 e #97, cartella `backend/`, con 89 test): Alessandro deve partire da quello e non riscriverlo. Da concordare tra i due chi fa gli endpoint che mancano (elenco nella tabella).

| Issue | Task | Stato | Note |
|---|---|---|---|
| `#23` | BID-04-01 Configurare il progetto Spring Boot. | Aperta | **Fatto** con B2 (PR #95): da chiudere. |
| `#24` | BID-04-02 Definire gli endpoint sulla base dei requisiti concordati. | Aperta | In corso. Fatti `/health`, `/me`, `/editions`, `/portal/me` e, con B3a, preventivi (crea, leggi, invia, conferma), conversione in contratto e `GET /contracts/{id}`. **Mancano** rifiuto preventivo, annullamento contratto, pagamenti, elenchi (B3b) e le API KPI e report espositore. |
| `#25` | BID-04-03 Implementare accesso al database e validazione dei parametri | Aperta | **Fatto** per gli endpoint esistenti (ruolo del database per richiesta, parametri validati). Chiudere dopo gli endpoint che mancano. |
| `#26` | BID-04-04 Gestire risposte, errori e codici HTTP. | Aperta | **Fatto** (errori `problem+json`, codici stabili, `Idempotency-Key`, `If-Match`): da chiudere. |
| `#27` | BID-04-05 Documentare il contratto API e predisporre test automatici. | Aperta | In corso. Contratto in `docs/api/openapi.yaml` (bozza, PR #88), non congelato; i quattro codici di errore nuovi di B3a sono solo in `docs/api/README.md`. 89 test automatici sul backend. |

## BID-05 — Dashboard operativa per lo staff (`#28`, aperta)

Responsabile: Mattia. Non iniziata (nessun codice Angular nel repository). Dipende dagli endpoint `/ops/*` e `/kpi/*` di BID-04, che oggi non esistono.

| Issue | Task | Stato |
|---|---|---|
| `#29` | BID-05-01 Visualizzare ingressi e visitatori presenti secondo le definizioni concordate. | Aperta |
| `#30` | BID-05-02 Mostrare i dati aggregati per padiglione. | Aperta |
| `#31` | BID-05-03 Evidenziare i picchi di presenza e l'andamento degli accessi. | Aperta |
| `#32` | BID-05-04 Visualizzare le visite registrate presso gli stand. | Aperta |
| `#33` | BID-05-05 Collegare le viste alle API e gestire l'aggiornamento dei dati. | Aperta |

## BID-06 — Portale web per gli espositori (`#34`, aperta)

Responsabile: Mattia. Non iniziata. Dipende da `/portal/me/**` di BID-04: oggi c'è solo `/portal/me`.

| Issue | Task | Stato | Note |
|---|---|---|---|
| `#35` | BID-06-01 Implementare l'accesso degli espositori. | Aperta | Il backend ha già il login con ruolo espositore (token di sviluppo; Entra ID non configurato). |
| `#36` | BID-06-02 Visualizzare le visite ricevute dai relativi stand. | Aperta | |
| `#37` | BID-06-03 Predisporre il riepilogo delle prestazioni e il confronto tra edizioni. | Aperta | |
| `#38` | BID-06-04 Recuperare i dati dalle API e dal modello condiviso. | Aperta | Endpoint `/portal/me/**` del contratto: solo `/portal/me` è implementato. |
| `#39` | BID-06-05 Separare rigorosamente i dati appartenenti a espositori diversi. | Aperta | Isolamento a livello database e `/portal/me` provato dai test di B2; i test di sicurezza completi via backend (URL e parametri) sono da fare. |

---

## Task del BAD (riferimento)

Sono del team BAD (Lorenzo, Fabrizio) e stanno su GitHub con gli stessi codici. Qui sono elencati perché alcuni dipendono dalle nostre API.

| Issue | Task | Stato |
|---|---|---|
| `#46` | BAD-01 Infrastruttura Power Platform e coordinamento con il BID | Chiusa |
| `#47` | BAD-01-01 Installare e registrare l'on-premises data gateway. | Chiusa |
| `#48` | BAD-01-02 Creare con il BID gli utenti database dedicati a Power Apps e Power BI. | Chiusa |
| `#49` | BAD-01-03 Comunicare al BID l'accesso diretto al database e Power BI Service. | Chiusa |
| `#50` | BAD-01-04 Revisionare lo schema V1–V4 per la parte commerciale. | Chiusa |
| `#51` | BAD-01-05 Creare la solution Power Platform e versionarla nel repository. | Chiusa |
| `#52` | BAD-02 Processo commerciale | Aperta |
| `#53` | BAD-02-01 Documentare il flusso preventivo → contratto → acconto → saldo → prelazione. | Chiusa |
| `#54` | BAD-02-02 Concordare con il BID quali regole garantisce il database e quali Power Apps. | Chiusa |
| `#55` | BAD-03 Power Apps: back-office commerciale (MVP SAL 2) | Aperta |
| `#56` | BAD-03-01 Collegare l'app a PostgreSQL tramite gateway. | Chiusa |
| `#57` | BAD-03-02 Creare la struttura dell'app e la navigazione. | Chiusa |
| `#58` | BAD-03-03 Gestire l'anagrafica espositori con lo storico contratti. | Aperta |
| `#59` | BAD-03-04 Visualizzare il listino 2026. | Chiusa |
| `#60` | BAD-03-05 Mostrare la planimetria 2026 con lo stato commerciale degli stand. | Chiusa |
| `#61` | BAD-03-06 Creare un preventivo dalle voci di listino. | Aperta |
| `#62` | BAD-03-07 Convertire un preventivo in contratto. | Aperta |
| `#63` | BAD-03-08 Firmare il contratto e generare acconto e saldo. | Aperta |
| `#64` | BAD-03-09 Registrare i pagamenti ricevuti. | Aperta |
| `#65` | BAD-04 Power Apps: prelazioni, sponsorizzazioni e funzioni avanzate | Aperta |
| `#66` | BAD-04-01 Gestire le prelazioni: esercizio e rinuncia. | Aperta |
| `#67` | BAD-04-02 Vendere sponsorizzazioni rispettando la disponibilità. | Aperta |
| `#68` | BAD-04-03 Gestire la riserva temporanea degli stand. | Aperta |
| `#69` | BAD-04-04 Realizzare il cruscotto commerciale nell'app. | Aperta |
| `#70` | BAD-04-05 Collegare l'app al portale espositori del BID. | Aperta |
| `#71` | BAD-05 Flussi Power Automate | Aperta |
| `#72` | BAD-05-01 Verificare azioni e trigger del connettore PostgreSQL via gateway. | Chiusa |
| `#73` | BAD-05-02 Configurare le variabili d'ambiente per destinatari e soglie. | Chiusa |
| `#74` | BAD-05-03 Inviare i promemoria per acconti e saldi in scadenza. | Chiusa |
| `#75` | BAD-05-04 Avvisare delle prelazioni in scadenza. | Aperta |
| `#76` | BAD-05-05 Segnalare le anomalie dei dati aperte. | Aperta |
| `#77` | BAD-05-06 Notificare la firma di un contratto. | Aperta |
| `#78` | BAD-06 Report Power BI per la direzione | Chiusa |
| `#79` | BAD-06-01 Collegare Power BI alle viste analytics del modello condiviso. | Chiusa |
| `#80` | BAD-06-02 Costruire il modello a stella. | Chiusa |
| `#81` | BAD-06-03 Realizzare le pagine v1: ricavi, saturazione, qualità dati. | Chiusa |
| `#82` | BAD-06-04 Pubblicare su Power BI Service con refresh tramite gateway. | Chiusa |
| `#83` | BAD-06-05 Completare le pagine direzionali e il confronto tra edizioni. | Chiusa |
| `#84` | BAD-06-06 Verificare che i totali tornino con la riconciliazione. | Chiusa |
| `#85` | BAD-06-07 Etichettare stime e indicatori non calcolabili. | Chiusa |

Le issue `#61`, `#62`, `#63`, `#64` e `#68` del BAD (preventivo, conversione, firma, pagamenti, riserva) usano le API di `#24`: B3a copre creazione, conversione e riserva; i pagamenti arrivano con B3b.

---

## Vecchi codici `B1`…`B21`

Il documento del 4 novembre usava codici `B…` che compaiono ancora in commit e documenti. Corrispondenza con le issue:

| Vecchio codice | Issue |
|---|---|
| B1 decisione Power Apps ↔ dati (**fatta**, `docs/08-decisioni-condivise.md`) | `#48`, `#49`, `#54` |
| B2 scheletro backend (**fatto**) | `#23`, `#25`, `#26` |
| B3 API commerciali (**B3a fatto**, B3b da fare) | `#24` |
| B4 contratto OpenAPI (bozza unita) | `#27` |
| B5 revisione V5 (**fatta**) | `#16`…`#21` |
| B21 test di sicurezza via backend (non iniziato) | `#39` |
| B7, B8, B9 caricamenti e riconciliazione nomi (**fatti**) | `#17`…`#20` |
| B13 progetto Angular, B14 dashboard staff | `#28`…`#33` |
| B16 portale espositori | `#34`…`#39` |
| B20 API KPI e report espositore | `#24`, `#33` |
| B11 prestazioni, B12 riconciliazione REC-01…08, B15 eventi demo, B17 docker-compose, B18 documentazione, B19 casi di prova | **Nessuna issue**: stato da verificare |

## Estensioni opzionali (dopo il SAL 2, da validare col cliente)

| Funzione | Proposta di assegnazione |
|---|---|
| Mappa interattiva degli stand (selezione, prezzo, riserva a tempo) | Michele e Andrea per la parte Angular; Mattia per le API di riserva (la riserva temporanea è già in B3a); planimetria vera da chiedere al cliente |
| Sito pubblico con contatto e richiesta di prenotazione | Mattia (API e regole), Andrea (interfaccia) |
| Conteggio persone con sensori | Alessandro, **solo simulato** finché il referente privacy non decide |

## Punti che il team leader deve sciogliere

1. **Conversione preventivo → contratto: due implementazioni.** Il BAD ha realizzato la conversione con un trigger nel database (B-51, ramo `BAD`, 16/11) e usa l'accesso diretto (`arcade_powerapp`); B3a la fa via API (`#24`). La decisione B1 prevede le scritture solo via API. Va deciso quale resta e come si evita il doppione (regole, numerazione dei contratti).
2. **Congelamento dello schema:** vedi la nota sotto BID-02 (V6 di B3a).
3. **BID-04 e il backend già esistente:** `BID-04` è assegnata ad Alessandro, ma il backend (B2 e B3a) è già nel repository, scritto da Mattia. Concordare che Alessandro parta da quello e chi fa gli endpoint mancanti (B3b, `/ops/*`, `/kpi/*`, `/portal/me/**`, ingest delle scansioni).
4. **Date 2026 e listino reale:** senza giorni di apertura nell'edizione 2026 la conversione risponde `422 EDITION_DATES_MISSING`; chiedere ad Alessandro se il caricamento (BID-03) le ha già inserite.
5. **App di scansione agli stand:** il BAD ha nel PDF ufficiale la sua assegnazione, il BID la mette nella PWA Angular.
6. **Risposte del cliente:** D1, D2, D3, D4, D6 e D34 incidono sui caricamenti e sull'acconto di B3a.
7. **Project di GitHub:** ricontrollare gli stati sulla bacheca (non è stata letta).

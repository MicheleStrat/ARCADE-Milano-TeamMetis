# Assegnazione dei task BID

Aggiornato: 4 novembre 2026 · Team leader: Mattia Billong

Fonti: l'elenco dei task è in [03-lavoro-futuro.md](03-lavoro-futuro.md); lo stato del lavoro è tratto dai rami del repository (`BID`, `alessandro`, `main`). Le assegnazioni sono una **proposta del team leader**: i livelli di Michele e Andrea sono stimati, non misurati.

## Stato di partenza (verificato sul repository)

| Cosa | Stato |
|---|---|
| Schema V1–V4, test SQL, documentazione | Su `BID` (PR #86 unita il 28/10) |
| V5: procedure di caricamento di biglietteria, tornelli e visite stand (2024–2025) | Su ramo `alessandro` (31/10), **non ancora unito a `BID`**, non rivisto |
| Caricamento dei file Excel (espositori, stand, listino, contratti) | **Non fatto** |
| Backend Spring Boot, contratto OpenAPI, Angular | **Non fatti** |
| Domande al cliente D1–D33 | Pronte; risolte D24–D28 e D30–D31, le altre senza risposta |
| Conflitto con il BAD sull'accesso di Power Apps ai dati | **Aperto**: il BAD ha scelto l'accesso diretto a PostgreSQL (B-08), il BID l'accesso solo via API (R-03) |

## Date

| Data | Evento |
|---|---|
| Ven 6/11 | Controllo di avanzamento settimanale |
| Mer 11/11 | Fine sviluppo funzioni per il SAL 2; poi solo integrazione e prove |
| **Ven 13/11** | **SAL 2**: edizioni 2024/2025 caricate, anomalie e riconciliazione, un contratto 2026 venduto, prime dashboard |
| 16/11 – 4/12 | Sviluppo autonomo e integrazione |
| Ven 4/12 | Presentazione finale |

## Regole di lavoro

- Nessun push diretto su `BID`: ogni persona lavora sul proprio ramo (`nome-argomento`) e apre una pull request.
- Il team leader rivede e unisce le PR.
- Ogni task consegnato riporta: file modificati, come eseguirlo, cosa è stato provato davvero e cosa no.
- Niente dati personali o segreti nel repository.

---

## Mattia Billong — team leader (5 task, i più complessi)

| ID | Task | Difficoltà | Scadenza | Dipende da | Consegna |
|---|---|:-:|---|---|---|
| B4 | **Contratto OpenAPI v1** da congelare (endpoint, DTO, errori, ruoli) | ●●● | 6/11 | — | `docs/api/openapi.yaml`; sblocca Angular e BAD |
| B1 | **Decisione architettura Power Apps ↔ dati**: API o accesso diretto (conflitto R-03/B-08); eventuale ruolo DB dedicato con grant minimi | ●●● | 6/11 | Confronto col BAD | Voce in `decisioni-condivise` |
| B2 | **Scheletro backend Spring Boot**: Flyway, sicurezza JWT e ruoli, uso di `arcade_portal` + `app.exhibitor_id`, errori `problem+json`, log | ●●●● | 10/11 | B4 | Backend che parte e legge dal DB |
| B3 | **API commerciali**: preventivi → contratti → acconti, anti-doppia vendita (409), `Idempotency-Key`, transazioni e concorrenza | ●●●●● | 12/11 | B2 | Un contratto 2026 venduto da API |
| B5 | **Revisione e unione della V5** di Alessandro; decisione sul congelamento dello schema | ●● | 6/11 | — | PR unita, schema congelato |
| B21 | **Test di sicurezza via backend**: un espositore non accede ai dati di un altro (URL, parametri) | ●●●● | dopo il 13/11 | B2, B3 | Test automatici verdi |

Continuativo: riferimento verso il cliente (domande P1) e verso il BAD.

## Alessandro De Filippis (6 task)

| ID | Task | Difficoltà | Scadenza | Dipende da | Consegna |
|---|---|:-:|---|---|---|
| B7 | **Caricamento Excel commerciale**: espositori, stand, stand per edizione, listino 2026, listini 2024/25 ricostruiti, contratti, righe e pagamenti derivati | ●●●●● | 10/11 | B5 | 198 contratti e 950 righe nel `core`, con anomalie |
| B8 | **Riconciliazione dei nomi 2024** (esatto, normalizzato, fuzzy con conferma, quarantena dei 9 non risolti) | ●●●● | 10/11 | B7 | `exhibitor_alias` popolata, elenco dei casi |
| B9 | **Orchestratore del caricamento CSV**: impronta del file, batch, copia in staging, chiamata delle procedure V5, report; riesecuzione senza duplicati | ●●●● | 11/11 | V5 | Tutti i file 2024/25 caricati |
| B12 | **Riconciliazione REC-01…REC-08**: popolare `dq.reconciliation_result` | ●●● | 12/11 | B7, B9 | Report MATCH/MISMATCH |
| B11 | **Prestazioni**: `presence_estimate()` e `fact_gate_reading` su volumi reali; materializzare se serve | ●●● | dopo il 13/11 | B9 | Misure e correzioni |
| B20 | **API KPI e report espositore** (lettura dalle viste `analytics`/`portal`) | ●●● | dopo il 13/11 | B2 | Endpoint documentati |

## Michele Strat (3 task)

| ID | Task | Difficoltà | Scadenza | Dipende da | Consegna |
|---|---|:-:|---|---|---|
| B13 | **Progetto Angular**: struttura, client generato da OpenAPI, login e ruoli, layout | ●●● | 9/11 | B4 | App che parte e chiama l'API (anche finta) |
| B14 | **Dashboard staff**: affluenza, presenze **stimate** (etichettate), visite stand, anomalie, ultimo aggiornamento, indicatore **demo/reale** | ●●● | 12/11 | B13 | Dashboard su dati caricati |
| B15 | **Generatore di eventi demo** controllato (marcati `is_demo`) per mostrare l'aggiornamento in diretta | ●● | dopo il 13/11 | B9 | Script o endpoint documentato |

## Andrea Cacioppo (4 task)

| ID | Task | Difficoltà | Scadenza | Dipende da | Consegna |
|---|---|:-:|---|---|---|
| B17 | **docker-compose** (database, backend, frontend), `.env.example`, istruzioni di avvio | ●● | 9/11 | — | `docker compose up` funzionante |
| B16 | **Portale espositori in Angular**: contratto, stand, pagamenti, visite, confronto con le edizioni precedenti, informazioni su prelazione | ●●● | 12/11 | B13 | Portale su dati finti, poi veri |
| B18 | **Documentazione**: dizionario dati, registro assunzioni, decisioni e anomalie, script della demo | ●● | continuativo | — | File in `docs/` |
| B19 | **Casi di prova** funzionali e checklist di accettazione (precondizioni, azioni, risultato atteso, esito reale) | ●● | 11/11 | — | `docs/` con esiti compilati solo dopo l'esecuzione |

---

## Estensioni opzionali (dopo il SAL 2, da validare col cliente)

| Funzione | Proposta di assegnazione |
|---|---|
| Mappa interattiva degli stand (selezione, prezzo, riserva a tempo) | Michele e Andrea per la parte Angular; Mattia per le API di riserva; planimetria vera da chiedere al cliente |
| Sito pubblico con contatto e richiesta di prenotazione | Mattia (API e regole), Andrea (interfaccia) |
| Conteggio persone con sensori | Alessandro, **solo simulato** finché il referente privacy non decide |

## Punti che il team leader deve sciogliere

1. **B1**: accesso diretto del BAD a PostgreSQL oppure solo API (blocca il disegno di B2 e B3).
2. **Congelamento dello schema**: il 30/10 era la scadenza; serve confermare lo stato e unire la V5.
3. **App di scansione agli stand**: il BAD ha nel PDF ufficiale la sua assegnazione, il BID la mette nella PWA Angular.
4. **Risposte del cliente**: D1, D2, D3, D4, D6 incidono su B7 e B9.

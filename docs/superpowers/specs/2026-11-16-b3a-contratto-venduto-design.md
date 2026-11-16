# B3a — Percorso "contratto venduto" via API: specifica

**Data:** 16 novembre 2026 · **Responsabile:** Mattia Billong · **Stato:** implementata

## 1. Obiettivo

Dal backend (B2) si crea un preventivo con prezzi calcolati dal server e stand riservati, lo si invia e conferma, e lo si converte in contratto con piano di pagamento. Due richieste concorrenti non possono vendere lo stesso stand, e una ripetizione con la stessa `Idempotency-Key` non duplica nulla.

**Criterio di riuscita:** con un token `COMMERCIAL`, `POST /quotes` → `/send` → `/confirm` → `/contract` produce un contratto 2026 `SIGNED` con stand `SOLD`, acconto e saldo; ripetere ogni POST con la stessa chiave restituisce la stessa risposta; due conversioni o due preventivi concorrenti sullo stesso stand hanno un solo vincitore e l'altro riceve `409`.

Non include: rifiuto del preventivo, annullamento del contratto, registrazione dei pagamenti, elenchi con paginazione, scadenza automatica delle riserve (sono B3b).

## 2. Decisioni già prese

| Tema | Decisione |
|---|---|
| Divisione di B3 | B3a = percorso "venduto"; B3b = resto |
| Date dell'edizione 2026 | Non note (domanda aperta coi product owner). Se l'edizione non ha giorni di apertura la conversione risponde `422 EDITION_DATES_MISSING`. Le prove usano date provvisorie solo nei dati di test |
| Regole non confermate dal cliente | Si usano assunzioni dichiarate e configurabili (§8) |
| Ruoli | `ADMIN` e `COMMERCIAL` su preventivi e conversione; `ADMIN`, `COMMERCIAL`, `OPS` su `GET /contracts/{id}` (come da contratto) |

## 3. Endpoint

| Endpoint | Cosa fa | Intestazioni | Esito |
|---|---|---|---|
| `POST /quotes` | Crea il preventivo `DRAFT`, calcola i prezzi, riserva gli stand | `Idempotency-Key` | `201` `Quote` |
| `GET /quotes/{quoteId}` | Dettaglio con righe | — | `200`, `404` |
| `POST /quotes/{quoteId}/send` | `DRAFT` → `SENT` | `If-Match` (rowVersion) | `200` |
| `POST /quotes/{quoteId}/confirm` | `SENT` → `CONFIRMED` | `If-Match` | `200` |
| `POST /quotes/{quoteId}/contract` | `CONFIRMED` → `CONVERTED`, crea il contratto | `Idempotency-Key` | `201` `Contract` |
| `GET /contracts/{contractId}` | Contratto con stand, righe e pagamenti | — | `200`, `404` |

DTO e nomi dei campi: quelli di `docs/api/openapi.yaml` (`QuoteCreate`, `Quote`, `ContractFromQuote`, `Contract`, `Payment`, `DocumentLine`).

## 4. Calcolo dei prezzi (solo server)

Il client invia `editionId`, `exhibitorId`, `discountPct`, `validUntil` e le righe (`priceItemId`, `standEditionId`, `quantity`, `description`). I prezzi inviati non esistono nel contratto.

- **Listino:** quello dell'edizione, che deve essere `PUBLISHED`; altrimenti `422 VALIDATION_ERROR`.
- **Riga `SPACE`:** richiede `standEditionId`. La voce deve essere di tipo `SPACE` e del padiglione dello stand. Quantità = metratura dello stand (la quantità inviata è ignorata); importo = `round(quantità × prezzo, 2)`.
- **Maggiorazione automatica:** per ogni stand con posizione diversa da `LINEA` il server aggiunge una riga `SURCHARGE`: voce del listino con la stessa posizione, quantità 1, prezzo e importo = `round(importo dello spazio × pct, 2)`, legata allo stesso stand. Se manca la voce → `422`. Il client non può inviare righe `SURCHARGE`.
- **Righe `EXTRA` e `SPONSORSHIP`:** quantità inviata, prezzo dal listino, quantità non oltre `max_quantity` se presente.
- **Totali:** `listAmount` = somma delle righe; `netAmount` = `round(listAmount × (1 − discountPct), 2)`, come richiede il vincolo del database.
- **Controlli:** edizione `SALES_OPEN`; espositore esistente; stand dell'edizione indicata; nessuno stand ripetuto; al massimo 200 righe (`413 PAYLOAD_TOO_LARGE`). Gli errori di dati sono `422 VALIDATION_ERROR` con `errors[]`; stand `FREE` o `NOT_SELLABLE` sono `422 STAND_NOT_SELLABLE`.
- Il calcolo è una funzione senza accesso al database (`PricingCalculator`), provata con numeri esatti.

## 5. Riserva degli stand e concorrenza

- **Colonna nuova** `core.stand_edition.reserved_by_quote_id` (V6): dice quale preventivo ha riservato lo stand. Vincolo: valorizzata solo se lo stato è `RESERVED`.
- **Creazione del preventivo, in una transazione:** gli stand si bloccano con `SELECT … FOR UPDATE` **in ordine di `stand_edition_id`**, così due preventivi con gli stessi stand in ordine opposto non vanno in stallo. Per ogni stand:
  - `SOLD` → `409 STAND_ALREADY_SOLD`;
  - `RESERVED` con `reserved_until` nel futuro → `409 STAND_ALREADY_RESERVED`;
  - `AVAILABLE`, o `RESERVED` scaduta → diventa `RESERVED`, con `reserved_until` = ora + durata della riserva e `reserved_by_quote_id` = il nuovo preventivo.
  Ogni modifica incrementa `row_version`.
- **Conversione, in una transazione:** si blocca il preventivo e poi i suoi stand (stesso ordine). Ogni stand deve avere `reserved_by_quote_id` = questo preventivo; altrimenti `409 STAND_ALREADY_SOLD` (stato `SOLD`) o `409 STAND_ALREADY_RESERVED` (riservato da un altro preventivo). Una riserva scaduta ma ancora del nostro preventivo resta valida: nessun altro l'ha presa.
- **Ultima difesa:** l'indice univoco `ux_contract_stand_active` impedisce comunque due contratti attivi sullo stesso stand; la violazione diventa `409 STAND_ALREADY_SOLD`.

## 6. Stati del preventivo

`DRAFT` → `SENT` → `CONFIRMED` → `CONVERTED`. `send` e `confirm` richiedono `If-Match` con la `rowVersion` attuale (`409 OPTIMISTIC_LOCK_CONFLICT` se è cambiata). Un passaggio non permesso dallo stato attuale risponde `409 INVALID_STATE_TRANSITION`. La conversione di un preventivo non `CONFIRMED` risponde `409 QUOTE_NOT_CONFIRMED`. Se `validUntil` è passato, `confirm` e conversione rispondono `409 QUOTE_EXPIRED` (lo stato `EXPIRED` assegnato in automatico è B3b).

## 7. Conversione in contratto

Una sola transazione, con gli stessi blocchi di §5:

1. Numero contratto `C{anno}-{NNNN}` (progressivo per anno, assegnato sotto un blocco consultivo per edizione; il vincolo `UNIQUE` resta come difesa).
2. `core.contract` `SIGNED` con `signedOn` e `isRenewal` dalla richiesta; importi e sconto copiati dal preventivo; `quote_id` valorizzato (un preventivo, al massimo un contratto).
3. `core.contract_stand` per ogni stand; `core.contract_line` copiate dalle righe del preventivo (le righe `SPACE` e `SURCHARGE` legate al proprio stand); `core.sponsorship` (`SOLD`) per le righe `SPONSORSHIP`.
4. Piano di pagamento, due righe con `due_amount_basis = RULE_DERIVED`:
   - **Acconto:** importo = `round(netAmount × deposit_pct, 2)`; scadenza = `signedOn` + giorni dell'acconto (§8), e comunque non oltre la scadenza del saldo.
   - **Saldo:** importo = `netAmount` − acconto; scadenza = primo giorno dell'edizione − `balance_days_before`.
   - Mancano le date dell'edizione → `422 EDITION_DATES_MISSING`. Mancano `deposit_pct` o `balance_days_before` nel listino → `422 PRICE_LIST_CONDITIONS_MISSING`.
5. Stand a `SOLD` (`reserved_until` e `reserved_by_quote_id` azzerati); preventivo a `CONVERTED`.

## 8. Assunzioni dichiarate (da confermare coi product owner)

| Assunzione | Valore | Dove si cambia |
|---|---|---|
| Durata della riserva degli stand | 14 giorni dalla creazione del preventivo | `arcade.quote.reservation-days` |
| Scadenza dell'acconto | 15 giorni dopo la firma (la domanda D34 non ha risposta) | `arcade.contract.deposit-due-days` |
| Percentuale d'acconto e giorni del saldo | Dal listino (`deposit_pct`, `balance_days_before`) | Dati |
| Un contratto per espositore ed edizione | Non imposto (il cliente non ha confermato, decisione D-07) | — |
| Listino da usare | Solo `PUBLISHED`; il caricamento dei listini reali è B7 | — |

## 9. Idempotenza

- **Tabella `core.idempotency_key`** (V6): `principal` (il `sub` del token), `operation` (`createQuote` o `convertQuoteToContract`), `key`, `request_hash`, `response_status`, `response_body` (testo, per restituire la risposta identica byte per byte), `created_at`; `UNIQUE (principal, operation, key)`. Solo `arcade_app` la usa; il portale non ha nessun permesso.
- **`request_hash`:** SHA-256 del contenuto della richiesta in forma canonica (campi ordinati) più percorso e metodo.
- **Flusso, nella stessa transazione dell'operazione:** `INSERT … ON CONFLICT DO NOTHING`. Se la riga esiste già:
  - ancora valida (meno di 24 ore) e stesso `request_hash` → si restituisce `response_status` e `response_body` salvati, con l'intestazione `Idempotent-Replayed: true`;
  - `request_hash` diverso (stessa chiave, contenuto diverso) → `409 DUPLICATE_REQUEST`;
  - più vecchia di 24 ore → si riutilizza la riga e l'operazione riparte.
- **Concorrenza sulla stessa chiave:** la seconda richiesta resta in attesa sull'indice univoco finché la prima non termina, poi riceve la risposta salvata (o esegue, se la prima è fallita).
- **Si salvano solo le risposte di successo.** Un errore (409, 422) annulla la transazione, quindi anche la chiave: la stessa richiesta può essere ripetuta.
- `Idempotency-Key` è obbligatoria (8–64 caratteri); se manca → `400 VALIDATION_ERROR`.
- Le righe vecchie non vengono eliminate in B3a (pulizia: B3b).

## 10. Struttura del codice

```
backend/src/main/java/it/arcade/backend/commercial/
  QuoteController, ContractController          (HTTP, header, DTO)
  QuoteService, ContractService                 (regole e transazioni)
  PricingCalculator                             (calcolo puro, senza database)
  StandReservation                              (blocco e cambio di stato degli stand)
  IdempotencyService                            (chiave, hash, risposta salvata)
  QuoteRepository, ContractRepository, PriceListRepository   (SQL con JdbcClient)
  dto/                                          (record del contratto OpenAPI)
backend/src/main/java/it/arcade/backend/db/ScopedDb.java     (nuovo metodo write)
database/migrations/V6__commercial_idempotency_and_reservation.sql
```

- `ScopedDb.write(Function<JdbcClient,T>)`: transazione in lettura e scrittura con `SET LOCAL ROLE arcade_app`; il metodo `read` esistente non cambia.
- Un conflitto di chiave univoca viene tradotto in `ApiException` con il codice giusto; i codici nuovi (`EDITION_DATES_MISSING`, `PRICE_LIST_CONDITIONS_MISSING`, `INVALID_STATE_TRANSITION`, `STAND_NOT_SELLABLE`) si aggiungono alla tabella dei codici di `docs/api/README.md` come modifica compatibile, con avviso al BAD.
- `created_by` resta nullo: l'utente del token non è in `core.app_user`.

## 11. Test

Tutti su PostgreSQL in container, con un database di prova che contiene (solo nei test) un listino 2026 `PUBLISHED`, stand di vari padiglioni e posizioni, giorni provvisori per il 2026 e un'edizione senza date.

- **Unitari, `PricingCalculator`:** spazio, maggiorazioni, sconto, arrotondamenti con numeri esatti.
- **API:** percorso completo fino al contratto; importi di acconto e saldo; stand `SOLD`; `If-Match` errato; passaggi di stato non validi; preventivo scaduto; edizione senza date (`422`); righe non valide.
- **Concorrenza:** due thread creano preventivi sullo stesso stand (un solo `201`); due thread con gli stessi due stand in ordine opposto (nessuno stallo); due conversioni concorrenti dello stesso preventivo con chiavi diverse (un solo contratto).
- **Idempotenza:** ripetizione con la stessa chiave (stessa risposta, un solo preventivo); stessa chiave con corpo diverso (`409 DUPLICATE_REQUEST`); due richieste simultanee con la stessa chiave (un solo effetto).
- **Sicurezza:** `EXHIBITOR`, `OPS` e `SCANNER` non possono creare preventivi (`403`).

## 12. Rischi e cosa non sarà verificato

- Il portale espositori può già leggere `core.stand_edition` (dati pubblici): vedrebbe anche `reserved_by_quote_id`, che è solo un numero. Se non va bene, si limitano le colonne concesse ad `arcade_portal`.
- Nessun blocco con tempo massimo: una transazione bloccata resta in attesa. Da valutare in B3b (`lock_timeout`).
- Il listino reale e le date 2026 non esistono nel database: B3a è provata solo con dati di test e non sul server Azure.
- Nessuna prova di carico.
- Gli importi non sono stati confrontati con contratti reali.

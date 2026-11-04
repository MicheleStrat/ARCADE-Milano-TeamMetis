# Contratto API ARCADE Milano — v1.0.0-draft

File: [openapi.yaml](openapi.yaml) · Task B4 · Responsabile: Mattia Billong · Stato: **bozza, non congelata, non implementata**

Il file descrive 58 operazioni su 53 percorsi e 91 schemi. È un **contratto**: nessun endpoint esiste ancora nel backend. Serve a far lavorare in parallelo backend, Angular e BAD, e va congelato dopo la revisione del team e del BAD.

Controllo eseguito: `@redocly/cli` (versione 1) segnala il file **valido**; restano avvisi di stile (descrizioni dei tag, risposte 4xx non ripetute su ogni lettura, licenza). Non è stato provato con un backend né importato in Power Platform.

## Come verificarlo e visualizzarlo

```bash
npx @redocly/cli@1 lint docs/api/openapi.yaml
npx @redocly/cli@1 preview-docs docs/api/openapi.yaml
```

Quando esisterà il backend con Springdoc, il file generato va confrontato con questo: il contratto vince, non il codice.

## Convenzioni

| Tema | Regola |
|---|---|
| Base | `/api/v1` |
| Formati | Date `YYYY-MM-DD`; istanti in UTC con `Z`; nomi dei campi `camelCase` |
| Importi | Euro, IVA **esclusa**, due decimali, tipo numerico. Il server arrotonda; il client non calcola prezzi |
| Percentuali | Frazione 0–1 (`0.10` = 10 %) per sconti e maggiorazioni; nei KPI i campi `...Pct` sono in punti percentuali (`75.00`) |
| Paginazione | `page` (da 0), `size` (default 20, massimo 200), `sort=campo,asc`. Risposta con `page`, `size`, `totalElements`, `totalPages`, `content` |
| Concorrenza | Le risorse modificabili hanno `rowVersion`; le azioni di stato richiedono `If-Match`. Se è cambiato: `409 OPTIMISTIC_LOCK_CONFLICT` |
| Idempotenza | Header `Idempotency-Key` obbligatorio su creazione preventivi, conversione in contratto, pagamenti, prelazione, acquisizione dati e importazioni. Stessa chiave = stessa risposta, nessun duplicato. Validità 24 ore |
| Errori | `application/problem+json` con `title`, `status`, `code` stabile, `traceId` ed eventuali `errors[]` per campo |
| Autorizzazione | Decisa dal server. Ogni operazione dichiara i ruoli in `x-roles`. Il portale espositore non accetta mai un `exhibitorId` dal client |
| Risorsa di altri | Il portale risponde **404**, non 403, per non rivelare che esiste |

## Ruoli

| Ruolo | Operazioni (sintesi) |
|---|---|
| `ADMIN` | Tutto, compresi listino e annullamento contratti |
| `COMMERCIAL` | Espositori, preventivi, contratti, pagamenti, sponsorizzazioni, prelazioni, KPI commerciali |
| `OPS` | Dashboard operativa, presenze, visite, anomalie, importazioni, riconciliazione |
| `EXHIBITOR` | Solo `/portal/me/**`, limitato ai propri dati |
| `SCANNER` | Solo acquisizione di letture e visite |
| `BI_READER` | Lettura dei KPI e della qualità dei dati |

## Codici di errore stabili

| Codice | HTTP | Quando |
|---|---|---|
| `UNAUTHENTICATED` | 401 | Token mancante o scaduto |
| `FORBIDDEN` | 403 | Ruolo non autorizzato |
| `NOT_FOUND` | 404 | Risorsa inesistente o non visibile |
| `VALIDATION_ERROR` | 400 / 422 | Formato non valido o regola violata (campi in `errors[]`) |
| `STAND_ALREADY_RESERVED` | 409 | Stand riservato da un altro preventivo |
| `STAND_ALREADY_SOLD` | 409 | Stand già assegnato a un contratto attivo |
| `QUOTE_NOT_CONFIRMED` | 409 | Conversione di un preventivo non confermato |
| `QUOTE_EXPIRED` | 409 | Preventivo scaduto |
| `OPTIMISTIC_LOCK_CONFLICT` | 409 | `rowVersion` non più attuale |
| `DUPLICATE_REQUEST` | 409 | Stessa chiave con contenuto diverso |
| `IMPORT_ALREADY_DONE` | 409 | File già importato (risposta con il batch esistente) |
| `PAYMENT_EXCEEDS_CONTRACT` | 422 | Incassi oltre il valore netto del contratto |
| `PREEMPTION_EXPIRED` | 422 | Prelazione oltre la scadenza |
| `PAYLOAD_TOO_LARGE` | 413 | Troppi elementi o file troppo grande |
| `RATE_LIMITED` | 429 | Troppe richieste (`Retry-After`) |

I codici sono parte del contratto: non si cambiano né si rimuovono dopo il congelamento.

## Collegamento con il database

| Area API | Origine dei dati |
|---|---|
| Anagrafiche, preventivi, contratti, pagamenti, prelazioni | tabelle `core.*` |
| `/ops/overview`, `/kpi/visitors` | `analytics.kpi_visitors_edition` |
| `/ops/presence` | `analytics.presence_estimate()` |
| `/ops/stand-visits` | `analytics.fact_stand_visits` |
| `/kpi/commercial`, `/kpi/saturation`, `/kpi/exhibitors`, `/kpi/edition-comparison`, `/kpi/renewal` | viste `analytics.kpi_*` |
| `/kpi/data-quality`, `/imports`, `/anomalies`, `/quarantine`, `/reconciliation` | `dq.*` e `analytics.kpi_data_quality_*`, `reconciliation_status` |
| `/portal/me/**` | schema `portal` (ruolo `arcade_portal`, RLS) |
| `/ingest/**` | procedure di acquisizione (V5 in revisione) e tabelle `core.gate_reading`, `core.stand_visit` |

Le formule dei KPI stanno solo nelle viste SQL: l'API non le ricalcola.

## Regole di dominio incorporate nel contratto

- **Prezzi**: il server li calcola dal listino dell'edizione, con maggiorazioni di posizione (angolo, penisola, isola). Un preventivo non accetta prezzi dal client.
- **Doppia vendita**: un solo contratto attivo per stand ed edizione (vincolo del database). La riserva ha una scadenza.
- **Presenze**: sempre `isEstimate = true`, con metodo e permanenza dichiarati; padiglioni non sommabili.
- **Visitatori**: `ticketsSold`, `personsSold`, `ticketsValidated`, `uniqueDailyEntries`, `passesTotal` sono misure diverse.
- **Costo per contatto qualificato**: il campo esiste ma è sempre `null`, perché mancano costi e definizione di contatto qualificato.
- **Visite**: una visita non è un contatto qualificato.
- **Privacy**: nessuna email o dato anagrafico nei contratti di acquisizione; `visitorToken` è solo pseudonimo; i contatti raccolti non sono esposti.
- **Confronto di mercato**: solo aggregato e solo con almeno 5 espositori nel gruppo.

## Compatibilità con Power Platform

Se si userà un connettore personalizzato (decisione B1 ancora aperta, vedi sotto):

- Il file è OpenAPI **3.0.3**. L'importazione in Power Platform non è stata provata. Se il connettore rifiutasse il 3.0, si converte in 2.0 con uno strumento di conversione.
- Non uso `oneOf`/`anyOf`, che i connettori gestiscono male. Uso `allOf` solo per le pagine.
- Ogni operazione ha un `operationId` e un `summary` in italiano.
- Autenticazione: bearer JWT (OAuth 2.0 con Entra ID da configurare, non ancora fatto).

## Punti aperti che toccano il contratto

| Punto | Effetto sul contratto |
|---|---|
| **B1** — Il BAD ha scelto l'accesso diretto di Power Apps a PostgreSQL; il BID aveva deciso di passare solo dalle API | Se prevale l'accesso diretto, le operazioni di scrittura (preventivi, contratti, pagamenti) restano comunque nell'API per garantire le regole; cambia chi le chiama |
| Domanda D7 — Un espositore può avere più contratti nella stessa edizione? | Il contratto lo ammette; se la risposta è no, si aggiunge un `409` dedicato |
| Domanda D1 — Direzione dei varchi | `direction` è facoltativo e `UNKNOWN` finché non è chiaro |
| Domanda D2 — Contatti stand e minori | Nessun endpoint espone i contatti. Se servono, si aggiungono dopo la decisione privacy |
| Planimetria | `geometry` è `null` finché il cliente non fornisce la pianta |
| Estensioni proposte (mappa con riserva, richieste di contatto dal sito, sensori) | **Non incluse** in v1; vanno aggiunte come modifica concordata |
| Aggregato orario 2025 | Importato solo da file; l'API `/ingest/stand-visits` riceve eventi puntuali |

## Regole di modifica dopo il congelamento

1. Compatibili (campi opzionali nuovi, nuovi endpoint): si aggiungono, con voce nel registro delle decisioni e avviso al BAD.
2. Incompatibili (rimuovere o rinominare campi, cambiare significato o codici di errore): nuova versione `/api/v2`, mai in modifica silenziosa.
3. Ogni modifica passa da una pull request con la descrizione dell'effetto su BAD e su Angular.

## Cosa NON è stato verificato

- Nessuna implementazione, quindi nessun test di conformità del backend al contratto.
- Nessuna importazione in Power Apps/Power Automate.
- La coerenza con la V5 di Alessandro (procedure di caricamento) è assunta dai nomi, non provata.
- Le soglie (1000 letture, 500 visite, 200 elementi per pagina, 24 ore di idempotenza) sono scelte tecniche da validare con i test di prestazioni.

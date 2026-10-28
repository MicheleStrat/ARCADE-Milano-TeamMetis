# Lavoro svolto fino ad oggi (23 ottobre 2026)

Questo file racconta, in ordine, cosa è stato fatto, perché, e con quale risultato **verificato**. Dove qualcosa non è stato provato, è scritto.

---

## Passo 1 — Analisi e progettazione preliminare (16 ottobre, kickoff)

**Cosa**: a partire dal brief ARCADE Milano è stata prodotta la prima analisi: riassunto del progetto, requisiti funzionali e non funzionali, tabella requisiti → componenti BAD/BID, domande per il cliente, assunzioni, architettura (diagramma), bozza di modello dati, bozza API, definizioni preliminari dei 5 KPI, roadmap, rischi, proposta di MVP per il SAL 2 e checklist di accettazione.

**Decisioni principali**
- Architettura **semplice**: un backend Spring Boot (monolite modulare), un database PostgreSQL, nessun microservizio.
- PostgreSQL è la **fonte unica di verità**; le applicazioni parlano tra loro tramite API e contratti espliciti.
- Power Apps/Power Automate usano **solo le API**; Power BI legge **solo viste di sola lettura**.

**Stato**: documento di analisi consegnato nella conversazione. Non è stato salvato in un file (la parte su BID/BAD è nel Passo 2).

---

## Passo 2 — Divisione BID/BAD e integrazione

**Cosa**: file [divisione-bid-bad-integrazione.md](../divisione-bid-bad-integrazione.md).

**Contenuto**
- Task divise tra BID (database, Java, ETL, Angular, test) e BAD (Power Apps, Automate, Power BI).
- Come collegare Power Apps al backend Java: **custom connector** generato dall'OpenAPI, con Entra ID. Richiede backend raggiungibile in HTTPS dal cloud Microsoft e probabilmente licenza premium.
- **Angular non si “mette dentro” Power Apps**: sono due frontend diversi per utenti diversi, collegati da un link (`Launch(...)`).
- Power Apps **non** deve scrivere direttamente su PostgreSQL; solo **Power BI** legge dal database, e solo dalle viste.

**Stato**: scritto. Nulla di tutto questo è ancora configurato.

---

## Passo 3 — Analisi dei file reali del cliente

**Cosa**: è stato aperto lo zip `ARCADE_Milano_dati` e **profilati** tutti i file (Excel con 5 fogli + 6 CSV). Il risultato è nel §2 di [data-model.md](data-model.md).

**File ricevuti**: espositori (135), planimetria (130 stand), listino 2026, contratti 2024-2025 (198), righe contratto (950), biglietteria 2024 (35.719) e 2025 (42.556), tornelli 2024 (46.824) e 2025 (55.992), contatti stand 2025 (1.707), visite stand 2025 (2.451 righe orarie).

**Scoperte importanti**
| Scoperta | Perché conta |
|---|---|
| I contratti 2024 **non hanno id né P.IVA** dell'espositore, solo il nome (a volte sporco) | 9 nomi su 88 non si riconducono con certezza a un espositore |
| I tornelli registrano **solo ingressi**, senza uscite | Le presenze in tempo reale si possono solo **stimare** |
| I varchi sono per padiglione (P1 Nord, P1 Sud, P2 Ovest, P3 Est) | Un passaggio non equivale a “entrato all'evento” |
| Tornelli 2024 in ora locale, 2025 in **UTC** | Serve gestire i fusi orari |
| Date Excel come numeri seriali | Vanno convertite |
| Il listino è **solo 2026** | I listini 2024 e 2025 si ricostruiscono dalle righe contratto e vanno confermati |
| Contatti stand: **email in chiaro**, 14 minori (14-17 anni) con consenso marketing | Problema di privacy: l'email non entra nel database vero, solo un hash; i 14 contatti vanno in revisione |
| Le date reali sono **19-22 dicembre**, il brief dice “fine novembre” | Domanda al cliente |
| Una riga di visite con 912 scansioni alle 08:00 (altrove il massimo è 177) | Sospetto errore, da segnalare |

---

## Passo 4 — Modello dati: V1 (schema) e V2 (dati di riferimento)

**File**
- [database/migrations/V1__core_schema.sql](../database/migrations/V1__core_schema.sql)
- [database/migrations/V2__reference_data.sql](../database/migrations/V2__reference_data.sql)

**V1 — cosa contiene**: tre schemi (`core` dati veri, `staging` copia grezza dei file, `dq` qualità dei dati), **58 tabelle**, 3 viste di controllo.

**Scelte di progetto spiegate semplicemente**
- Lo **stand fisico** (`stand`) è separato da **come è occupato in una edizione** (`stand_edition`). Lo **stesso vale per** espositore e contratto: l'azienda non è il contratto.
- **Doppia vendita impossibile** per vincolo del database (un indice speciale ammette un solo contratto attivo per stand/edizione).
- **Nessun dato viene scartato in silenzio**: i problemi vanno in `dq.anomaly`; i record dubbi in `dq.quarantine`.
- **Riprova sicura (idempotenza)**: importare due volte lo stesso file non duplica nulla.
- **Privacy**: l'email dei contatti non viene salvata, solo il suo hash; i dati di contatto degli espositori sono in una tabella separata.
- I valori **assunti** sono marcati (es. importo pagato assunto uguale al dovuto).

**V2 — cosa contiene**: sorgenti dati con fuso orario, edizioni 2024/2025/2026 con i giorni di apertura (dedotti dai dati), padiglioni, varchi, canali, i tipi di biglietto con i nomi diversi dei due anni, le 21 province con le loro grafie, ruoli, **37 regole di qualità** e 8 controlli di riconciliazione.

**Verifica eseguita** (PostgreSQL 16 in Docker): V1 e V2 senza errori; 8 test sui vincoli con esito atteso (doppia vendita bloccata, stand di un'altra edizione bloccato, importo incoerente bloccato, giorno biglietto fuori edizione bloccato, ecc.).

---

## Passo 5 — Sicurezza e analisi: V3 e V4

**File**
- [database/migrations/V3__roles_grants_rls.sql](../database/migrations/V3__roles_grants_rls.sql)
- [database/migrations/V4__analytics.sql](../database/migrations/V4__analytics.sql)

**V3 — ruoli e isolamento**
| Ruolo | Può fare |
|---|---|
| `arcade_app` | Staff via backend: legge e scrive, l'audit è solo in aggiunta |
| `arcade_portal` | Espositore: **sola lettura**, solo le **proprie** righe (RLS) |
| `arcade_etl` | Carica i dati, non cancella dal core |
| `arcade_bi` | Power BI: **solo** lo schema `analytics` |

Senza l'identificativo dell'espositore la sessione portale non vede **nulla** (comportamento sicuro per default). Le password non sono nel repository.

**V4 — KPI in un posto solo**: schema `analytics` (dimensioni, fatti, KPI) e schema `portal` (viste per gli espositori). Ogni KPI ha **una sola definizione** in SQL, usata da API, portale e Power BI.
- Visitatori: venduti, persone, validati, passaggi, ingressi-giorno, tenuti **separati**.
- Presenze: **stima** con finestra di permanenza (ipotesi 90 minuti), mai presentata come conteggio certo.
- Saturazione, ricavo/m² (solo spazio+maggiorazioni; extra e sponsor a parte), incassato separato dal contrattualizzato.
- Costo per contatto qualificato: **non calcolabile** (mancano costi e definizione di “qualificato”); c'è un indicatore sostitutivo con nome esplicito.
- Confronto tra edizioni, tasso di rinnovo, qualità dati, riconciliazioni.
- Il confronto di mercato per gli espositori è **solo aggregato** e compare solo con almeno 5 espositori nella categoria.

**Verifica eseguita**: V1→V4 senza errori; test con dati sintetici su KPI (valori attesi tutti confermati), riconciliazioni (tutte in accordo), isolamento tra espositori, permessi di ogni ruolo.

**Difetti trovati e corretti**: gli ingressi unici contavano anche i codici sconosciuti; il confronto mostrava un falso −100 % per il 2026 senza contratti; un errore di join in una vista.

---

## Passo 6 — Salvataggio dei test

**Cosa**: gli script di prova sono stati copiati in [database/tests/](../database/tests/).
- `constraints_smoke.sql` — i test sui vincoli.
- `kpi_rls_smoke.sql` — KPI, riconciliazioni, RLS e permessi, con dati sintetici.

Entrambi usano un database vuoto con V1–V4 applicate e **annullano** le modifiche o usano solo dati di prova.

---

## Cosa NON è stato fatto (onestà)

- Nessun dato reale del cliente è stato **caricato**: l'ETL non esiste.
- I valori dei KPI su dati reali sono **sconosciuti**.
- Nessun test con **Flyway** (i file sono nominati secondo la sua convenzione ma non sono stati eseguiti con lo strumento).
- Nessuna misura di **prestazioni** su volumi reali.
- Nessun **backend Java**, nessun frontend Angular, nessuna Power App/Flow/report Power BI.
- Il test di isolamento tra espositori è stato fatto **in SQL**, non attraverso il backend.
- Il contratto API (OpenAPI) è solo una bozza discorsiva, non congelata.
- Le domande Q-01…Q-14 per il cliente sono **ancora aperte**.

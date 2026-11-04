# Ingestione controllata dei dati 2024-2025

La migrazione `V5__ingest_ticketing_turnstiles_stand_visits.sql` implementa il caricamento di biglietteria 2024 e 2025, letture ai tornelli 2024 e 2025 e visite aggregate agli stand 2025.

Il flusso e `staging -> controllo qualita -> core`. Non leggere le viste `analytics` finche il batch non e concluso e il report non e stato esaminato.

## Controlli

| Area | Controlli prima del core | Esito |
|---|---|---|
| Biglietteria | duplicati, tipo/canale non mappato, date e giorno di validita, prezzo e persone, provincia, acquisto dopo l'evento | anomalie; record irrecuperabili in quarantena, duplicati respinti |
| Tornelli | timestamp e varco interpretabili, biglietto orfano, orari di apertura, KO, uso in un giorno diverso, lettura precedente all'acquisto | letture valide caricate; righe non interpretabili in quarantena; gli orfani restano caricati e segnalati |
| Visite stand | chiave stand/giorno/ora duplicata, stand non contrattualizzato, data/ora/scansioni, scansioni fuori apertura, outlier statistico | record non attribuibili in quarantena; outlier caricato e segnalato |

Le anomalie usano le regole gia presenti in `dq.rule` (`TKT-*`, `GAT-*`, `VIS-*`). Ogni record problematico conserva batch e numero di riga; non viene corretto o cancellato silenziosamente.

## Ordine obbligatorio

1. Applica V1-V5.
2. Carica espositori, stand, edizioni stand e contratti firmati. Le visite stand richiedono l'assegnazione dello stand per essere attribuite con certezza.
3. Per ogni CSV, crea un batch `RUNNING`, copia tutte le righe nella rispettiva tabella `staging`, quindi richiama la procedura associata.
4. Esamina `dq.v_import_quality_report`, `dq.anomaly` e `dq.quarantine`; solo dopo approvazione usa i dati per dashboard e KPI.

Esempio (il `COPY` va eseguito dal client con i delimitatori corretti; in `staging` tutti i campi sono testo):

```sql
INSERT INTO dq.import_batch (source_id, file_name, file_sha256, triggered_by)
SELECT source_id, 'biglietteria_2025.csv', '<sha256 minuscolo di 64 caratteri>', 'etl'
FROM core.data_source WHERE code = 'BIGL_2025'
RETURNING batch_id;

-- Copiare il CSV in staging.stg_ticket con batch_id e row_no progressivo.
CALL dq.load_ticket_batch(<batch_id>);

SELECT * FROM dq.v_import_quality_report
WHERE batch_id = <batch_id>
ORDER BY severity DESC NULLS LAST, rule_code;
```

```sql
CALL dq.load_ticket_batch(<batch_id>);       -- BIGL_2024 / BIGL_2025
CALL dq.load_gate_batch(<batch_id>);         -- TORN_2024 / TORN_2025
CALL dq.load_stand_visit_batch(<batch_id>);  -- VISITE_2025
```

Prima del caricamento reale il report deve almeno rendere visibili: codici tornello non presenti in biglietteria, esiti KO, visite alle 08:00 e l'outlier da 912 scansioni. Sono anomalie aperte, non valori ripuliti: una decisione del cliente e necessaria prima di alterarli.

I contatti stand con email e minori restano volutamente fuori da questa migrazione: richiedono una decisione privacy (Q-10) e una gestione separata della chiave di hashing; non e sicuro caricarli nel flusso delle visite.

## Verifica sui file reali (4 novembre 2026)

La V5 è stata eseguita su PostgreSQL 16 (Docker) dopo V1–V4, caricando i file ricevuti dal cliente in un database di prova. Nel repository non ci sono i file del cliente.

| File | Righe lette | Caricate | Quarantena | Scartate | Differenza |
|---|--:|--:|--:|--:|--:|
| biglietteria 2024 | 35.719 | 35.719 | 0 | 0 | 0 |
| biglietteria 2025 | 42.556 | 42.556 | 0 | 0 | 0 |
| tornelli 2024 | 46.824 | 46.824 | 0 | 0 | 0 |
| tornelli 2025 | 55.992 | 55.992 | 0 | 0 | 0 |

Controlli sul risultato: nessuna chiave di lettura duplicata; riconciliazioni REC-02 (biglietti) e REC-03 (letture) in accordo per entrambe le edizioni; i valori coincidono con il profiling dei file.

| Anomalia | 2024 | 2025 | Trattamento |
|---|--:|--:|---|
| TKT-002 provincia in grafia non canonica | 13.383 | 16.133 | normalizzata, informativa |
| TKT-003 provincia assente | 2.158 | 2.525 | caricata, informativa |
| GAT-001 codice tornello inesistente in biglietteria | 35 | 35 | caricata con `ticket_id` vuoto |
| GAT-003 esito KO | 230 | 256 | caricata con esito KO |
| GAT-006 lettura **precedente** all'acquisto | 6.063 | 7.512 | caricata e segnalata (errore) |
| GAT-007 fuso orario convertito | 1 (per batch) | – | informativa |

**GAT-006 è un dato del cliente, non un errore del codice.** Esempio: una tessera acquistata il 21/12/2025 alle 15:48 risulta passata al tornello il 19/12/2025 alle 09:39. Va chiesto al cliente cosa rappresenta la data di acquisto (soprattutto per la cassa).

### Correzioni rispetto alla prima versione della V5

| Problema | Correzione |
|---|---|
| `dq.add_anomaly` non valorizzava le colonne obbligatorie di `dq.anomaly` | usa batch, regola, gravità, area e azione della regola; regola o batch inesistenti sono un errore |
| Espressioni regolari con `\d`, `\s`: in stringhe standard non corrispondono a nulla (date, ore e numeri sempre vuoti) | classi `[0-9]`, `[[:space:]]`, `[.]` |
| `gg/mm/aaaa` letto secondo `DateStyle`: `05/12/2025` diventava 12 maggio senza errore | formato esplicito, indipendente da `DateStyle` |
| Ora delle visite letta come numero | letta come orario `hh:mm` |
| Fuori orario calcolato nel fuso della sorgente (UTC per i tornelli 2025) | fuso dell'edizione |
| Canale «Rivenditore partner» non riconosciuto (3.644 biglietti 2024 in quarantena) | mappato su `PARTNER` |
| Esito `1/0` dei tornelli 2024 non riconosciuto (tutte le letture in quarantena) | `1` = OK, `0` = KO |
| Riferimento ambiguo a `ticket_code` in GAT-005: la procedura dei tornelli non poteva girare | colonne qualificate |
| Rilancio di un batch: i biglietti già inseriti erano segnalati come duplicati | l'esistenza è controllata escludendo lo stesso batch |
| Tabelle temporanee ricreate a ogni chiamata nella stessa transazione | `DROP TABLE IF EXISTS` prima della creazione |
| `source_row_key` = `batch:riga`, diversa dalla chiave del contratto API | `varco|codice|istante UTC`, con `#n` per ripetizioni identiche nello stesso file |
| Righe con codice vuoto, ora o scansioni non numeriche: sparivano senza traccia | in quarantena |
| GAT-007 scriveva una riga per lettura (46.824) | una sola voce per batch |
| GAT-002 usata anche per «lettura non interpretabile» | nuova regola GAT-008 |

### Test

| Script | Cosa verifica | Esito |
|---|---|---|
| `database/tests/ingest_smoke.sql` | biglietti validi, duplicati e tipo sconosciuto | superato |
| `database/tests/ingest_functions_smoke.sql` | conversioni di date, orari, numeri e istanti, anche con `DateStyle` diversi | superato |
| `database/tests/ingest_gates_visits_smoke.sql` | tornelli 2024 e 2025, visite, quarantena, rilancio senza duplicati | superato |

### Limiti ancora aperti

- Le **visite stand** sono verificate solo con dati sintetici: sui file reali finirebbero in quarantena, perché stand e contratti non sono ancora caricati (manca il caricamento del file Excel commerciale).
- Il caricamento di 35.000 righe di biglietteria richiede circa un minuto: le prestazioni vanno misurate e, se serve, migliorate.
- Il controllo VIS-001 (valori anomali delle visite) usa media + 3 deviazioni standard: potrebbe segnalare valori legittimi.
- Non sono implementati TKT-007 (prezzo sotto listino), GAT-004 (letture ripetute ravvicinate) e COM-*.
- I contatti degli stand restano esclusi (decisione privacy Q-10).
- Non è stato eseguito con Flyway; la prova è fatta da `psql`.

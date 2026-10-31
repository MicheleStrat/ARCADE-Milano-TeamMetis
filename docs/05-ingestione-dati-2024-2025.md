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

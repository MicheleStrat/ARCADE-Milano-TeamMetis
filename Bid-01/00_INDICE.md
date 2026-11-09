# BID-01 — Analisi e profilazione dei dati sorgente · Indice

Una consegna per ciascuna attività del punto BID-01. Il documento completo (con tutti i dettagli e il registro esteso) è `BID-01_report_profilazione.md`.

| # | Attività | Documento | Stato |
|---|---|---|---|
| 1 | Esaminare i file di biglietteria, letture ai tornelli e visite agli stand | `01_esame_file_sorgente.md` | ✔ completata |
| 2 | Verificare colonne, formati, identificativi e relazioni tra file | `02_colonne_formati_identificativi_relazioni.md` | ✔ completata |
| 3 | Individuare duplicati, valori nulli, date incoerenti e riferimenti mancanti | `03_duplicati_nulli_date_riferimenti.md` | ✔ completata |
| 4 | Documentare le anomalie e proporre le regole di correzione | `04_anomalie_e_regole_di_pulizia.md` + `script/applica_regole_dry_run.py` | ✔ completata (regole **proposte**) |
| 5 | Concordare con il team BAD le anomalie sui dati commerciali | `05_punti_da_concordare_con_BAD.md` + `allegati/` | ◐ **preparata, non concordata** |

## Criteri di completamento

| Criterio | Stato | Dove |
|---|---|---|
| Disponibile un report di profilazione dei dati | ✔ | `BID-01_report_profilazione.md`, docs 01–03 |
| Anomalie documentate e classificate | ✔ 38 voci (V / C / Q / D) | doc. 04 |
| Regole di pulizia e assunzioni riproducibili | ✔ regole + 10 assunzioni, `script/applica_regole_dry_run.py` eseguito | doc. 04 |
| Chiaro quali dati si possono caricare e quali richiedono gestione speciale | ✔ | tabella sotto |

## Che cosa si può caricare

| Dati | Caricabili | Gestione speciale |
|---|---|---|
| Biglietteria 2024/2025 | ✔ tutti, 0 record in quarantena | normalizzazione R-B01…B05; minorenni protetti (R-B06) |
| Tornelli 2024/2025 | ✔ tutti | respinte conservate (R-T02/T03); doppioni e acquisto posteriore **flaggati**, definizione di "presenze" da concordare (R-T04/T05); uscite assenti |
| Visite stand 2025 | ✔ tranne **1 riga** (912 scansioni alle 08:00) in quarantena | slot mancanti non imputati; nessun 2024 |
| Contatti stand 2025 | ✔ tutti | 9 consensi vuoti = NO; 14 minorenni: mai esposti |
| Commerciale (espositori, planimetria, righe) | ✔ | P.IVA come testo |
| Contratti 2025 | ✔ | pagamenti da verificare (vedi sotto) |
| Contratti 2024 | ✔ con ID espositore **derivato** (88/88) | da confermare con il BAD |
| Pagamenti dei contratti 2024/2025 | ✔ NULL conservati | 19 contratti con pagamenti mancanti o date incoerenti (`allegati/contratti_pagamenti_da_verificare.csv`) |

## Decisioni ancora aperte (cliente / BAD)
Regola dei doppioni e definizione di "presenze" · orario di acquisto alla Cassa · uscite ai varchi · 912 scansioni · pagamenti vuoti · base del ricavo per m² · stati del flusso 2026 · consenso dei minori. Dettaglio nei documenti 04 e 05.

## Limiti
- Il repository `ARCADE-Milano-TeamMetis` non era disponibile: nessuna verifica di branch, codice o convenzioni esistenti.
- L'analisi riguarda solo i file ricevuti; nessun test su file malformati o flussi in tempo reale.
- Nessun accordo con il BAD o con il cliente è stato ricevuto: tutte le regole sono proposte.

## Come riprodurre
`python3 -I script/<nome>.py <cartella file sorgente>` (Python 3, `pandas`, `openpyxl`). `profile_*.py` = analisi; `verify_*.py` = controllo indipendente; `applica_regole_dry_run.py` = regole in prova → `script/risultati_dry_run.csv`; `genera_allegati_bad.py` → `allegati/`. Alcuni script hanno il percorso dei sorgenti scritto nel codice e vanno adattati.

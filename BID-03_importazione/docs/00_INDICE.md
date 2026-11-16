# BID-03 — Acquisizione e qualità dei dati · Indice

> Stato: pipeline **implementata e verificata** su dati reali e con 86 test; regole di pulizia ancora **proposte** (da approvare con cliente/BAD).

| Elemento | File |
|---|---|
| Come usarla, prerequisiti, configurazione | `../README.md` |
| Processo di importazione, idempotenza, conteggi, limiti | `01_processo_di_importazione.md` |
| Registro delle regole di qualità e delle anomalie | `02_registro_regole.md` |
| Test ed esiti (86 test + collaudo sui file reali) | `03_test_ed_esiti.md` |
| Codice | `../arcade_import/` (`core.py`, `sources.py`, `sources_commerciale.py`, `rules.py`, `lettura.py`, `__main__.py`) |
| Test | `../tests/` |

## Criteri di completamento (da istruzioni di progetto §7)
| Criterio | Stato |
|---|---|
| Verifica formato e campi obbligatori | ✔ |
| Validazione di identificativi, date, relazioni | ✔ |
| Normalizza solo con regole definite (e le conserva reversibili) | ✔ |
| Record non validi non fermano il processo | ✔ (e il file non interpretabile non carica nulla) |
| Conteggio lette / accettate / scartate / corrette (+ segnalate, quarantena) | ✔ |
| Informazioni per individuare e correggere gli errori | ✔ riga, regola, record originale |
| Riesecuzione senza duplicati | ✔ stesso file → `gia_importato`; file sovrapposto → solo righe nuove |
| Aggiornamento dei dati | ◐ **non previsto**: i valori diversi vengono segnalati, non applicati (C13) |
| Test: file validi, malformati, record incompleti, relazioni mancanti, ricarichi | ✔ |
| Formato degli scanner coordinato col BAD | ✗ **da fare** (SHARED-02) |

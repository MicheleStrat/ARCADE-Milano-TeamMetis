# BID-03 · Test ed esiti

Ambiente: Python 3.13, pandas 3.0, psycopg 3.3, PostgreSQL 16 **temporaneo** (non il database del team). Nessuna verifica con il BAD.

## 1. Test automatici — 86 test, tutti superati
`PYTHONPATH=. python -m pytest tests -q` → **86 passed** (≈ 20-30 s). Ogni test usa un database nuovo clonato da un modello con le migrazioni V001–V007.

| File | Test | Cosa verifica |
|---|---|---|
| `test_biglietteria.py` | 27 | file valido con correzioni (R-B02/B03/B06), ora locale→UTC, **ricarico dello stesso file**, ricarico con righe nuove e già presenti, **conflitto senza sovrascrittura**, 15 casi di record non validi (ognuno: gli altri record vengono caricati, l'anomalia è tracciata con riga e record originale), ID ripetuto, ordine incoerente, riga con campi errati, **file vuoto / colonne mancanti / non UTF-8 / edizione inesistente** (nulla caricato, importazione `fallita`, poi un file corretto si importa) |
| `test_tornelli.py` | 14 | formati 2024 e 2025, conversione di fuso, respinte e codici sconosciuti conservati, 6 casi di letture non valide, **doppia lettura ravvicinata NON scartata**, riga identica nel file, **ricarico con sovrapposizione senza duplicati**, dipendenza dalla biglietteria, intestazione non riconosciuta |
| `test_stand.py` | 24 | visite: 0 scansioni valido, 8 casi non validi, quarantena che conserva le 912 scansioni, slot mancanti non imputati, ricarico e conflitto; contatti: minorenni non esposti nella vista portale, consenso vuoto, 7 casi in quarantena (riferimento mancante, e-mail, fascia…), e-mail ripetuta su stand diversi mantenuta, contatti senza dati commerciali |
| `test_commerciale.py` | 17 | file valido (ID derivato, codici canonici, pagamenti NULL), ricarico identico e con aggiunte, P.IVA con zero perso, 9 casi di record non validi con effetto a cascata (espositore → contratto → righe), riga incoerente, maggiorazione non applicabile, struttura del file errata, file non Excel |
| `test_nucleo.py` | 4 | **atomicità** (errore a metà: nessun dato resta, importazione `fallita`, nuovo tentativo possibile), registro dell'importazione, interfaccia a riga di comando |
In ogni test sui conteggi vale `lette = accettate + corrette + quarantena + scartate`.
Durante la scrittura i test hanno individuato **tre difetti reali**, corretti: maschere dei doppioni calcolate prima del filtro; colonne interne nel record grezzo delle anomalie dei tornelli; zero-padding della P.IVA applicato a qualunque numero corto invece che solo a 10 cifre.

## 2. Collaudo con i file reali — `tests/collaudo_dati_reali.py`
| Importazione | Lette | Accettate | Corrette | Segnalate | Quarantena | Scartate | Tempo |
|---|---|---|---|---|---|---|---|
| commerciale | 1.433 | 1.073 | 360 | 20 | 0 | 0 | 0,7 s |
| biglietteria 2024 | 35.719 | 18.832 | 16.887 | 15.779 | 0 | 0 | 3,6 s |
| biglietteria 2025 | 42.556 | 22.214 | 20.342 | 18.587 | 0 | 0 | 4,2 s |
| tornelli 2024 | 46.824 | 46.824 | 0 | 230 | 0 | 0 | 3,2 s |
| tornelli 2025 | 55.992 | 55.992 | 0 | 256 | 0 | 0 | 3,4 s |
| visite stand 2025 | 2.451 | 2.450 | 0 | 0 | **1** (912 scansioni alle 08:00) | 0 | 0,1 s |
| contatti stand 2025 | 1.707 | 1.698 | 9 | 14 | 0 | 0 | 0,2 s |
- **52 su 52** i numeri coincidono con la profilazione BID-01 (biglietti, ordini, persone, letture, ingressi, minorenni, presenze candidate, mq venduti, imponibili, contratti coerenti…). Una sola query di riscontro è stata adattata alla nuova forma del record in quarantena (`dettaglio->'record'->>'scansioni'`): il valore atteso (912) non è cambiato.
- Registro anomalie: 22 righe aggregate/puntuali; i conteggi per regola coincidono con la tabella di BID-01 (es. R-B03 13.383, R-T03 195, R-C01 88, R-C03 16, R-C04 3).
- **Ripetendo tutte e 7 le importazioni** → tutte `gia_importato`; i volumi di ogni tabella restano identici (ordine 47.000, biglietto 78.275, lettura_tornello 102.816, visita_stand_oraria 2.450, contatto_stand 1.707, contratto 198, contratto_riga 950).

## 3. Cosa NON è stato verificato
- Nessuna prova su un database condiviso, con carichi concorrenti o con file molto più grandi (circa 15 s per tutti i file attuali).
- Nessuna prova con il flusso reale del BAD (Power Automate / app di scansione): il formato degli eventi è ancora da concordare.
- Il caricamento dei dati commerciali è provato sul file Excel del cliente e su file sintetici, non su una esportazione reale dal back-office del BAD.
- La parte Java/Spring Boot non esiste ancora (BID-04); la pipeline è in Python.
- Le regole restano proposte: i test provano che la pipeline le applica, non che siano giuste per il cliente.

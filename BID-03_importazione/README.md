# ARCADE Milano · Pipeline di importazione (BID-03)

Importa nel database condiviso PostgreSQL (schema `arcade`, vedi BID-02) i file di biglietteria, tornelli, visite agli stand,
contatti e dati commerciali. Ogni caricamento è tracciato, ripetibile e non perde nessun record in silenzio.

> Stato: **proposta del team BID**. Le regole di pulizia (BID-01) non sono ancora approvate dal cliente o dal BAD.

## Prerequisiti
Python 3.11+, PostgreSQL 16 con le migrazioni V001–V007 applicate (`db/applica.sh`), `psql` (solo per i test), pacchetti in `requirements.txt`.

## Configurazione (nessuna credenziale nel codice)
Variabili d'ambiente PostgreSQL standard: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`.
Facoltativa: `ARCADE_DSN` (stringa libpq completa, ha la precedenza). Per i test: `ARCADE_MIGRAZIONI` = cartella delle migrazioni.

## Uso
```bash
python -m arcade_import commerciale    ARCADE_Commerciale.xlsx
python -m arcade_import biglietteria   biglietteria_2025.csv   --edizione 2025
python -m arcade_import tornelli       tornelli_2025.csv       --edizione 2025
python -m arcade_import visite_stand   visite_stand_2025.csv   --edizione 2025
python -m arcade_import contatti_stand contatti_stand_2025.csv --edizione 2025
```
**Ordine obbligatorio per edizione:** `commerciale` → `biglietteria` → `tornelli`; `commerciale` → `visite_stand` / `contatti_stand`
(i tornelli verificano i biglietti, visite e contatti verificano stand e contratti: senza i dati di riferimento i record vanno in quarantena).
Esito: JSON con conteggi; codice di uscita 0 = completata o già importata, 2 = fallita.

## Test
```bash
export PGHOST=... PGUSER=...                    # un PostgreSQL su cui creare/eliminare database di prova
PYTHONPATH=. python -m pytest tests -q          # 86 test, ogni test usa un database nuovo
python tests/collaudo_dati_reali.py <cartella file del cliente>   # collaudo con i file reali (non inclusi nel repository)
```
Documentazione: `docs/00_INDICE.md`.

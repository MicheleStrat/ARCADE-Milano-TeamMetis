-- Test delle funzioni di conversione della V5 (dq.clean_text, try_date, try_time, try_numeric, try_timestamptz, add_anomaly).
-- Eseguire su un database con V1..V5. Non scrive dati: ogni ASSERT fallito interrompe lo script.
-- Casi tratti dai file reali: date gg/mm/aaaa (2024 e 2025), prezzi con virgola, ora hh:mm, timestamp UTC con Z.
\set ON_ERROR_STOP on

DO $$
BEGIN
  -- testo
  ASSERT dq.clean_text('  Monza   e  Brianza ') = 'Monza e Brianza', 'clean_text comprime gli spazi';
  ASSERT dq.clean_text('   ') IS NULL, 'clean_text: solo spazi = NULL';
  ASSERT dq.norm_text(' milano ') = 'MILANO', 'norm_text';

  -- date
  ASSERT dq.try_date('21/12/2024') = DATE '2024-12-21', 'gg/mm/aaaa';
  ASSERT dq.try_date('05/12/2025') = DATE '2025-12-05', 'gg/mm/aaaa ambiguo: deve essere 5 dicembre';
  ASSERT dq.try_date('2025-12-19') = DATE '2025-12-19', 'ISO';
  ASSERT dq.try_date('45558') = DATE '2024-09-23', 'seriale Excel (epoca 1899-12-30)';
  ASSERT dq.try_date('45558.0') = DATE '2024-09-23', 'seriale Excel con decimali nulli';
  ASSERT dq.try_date('31/02/2025') IS NULL, 'data inesistente';
  ASSERT dq.try_date('3 giorni') IS NULL, 'testo non e'' una data';
  ASSERT dq.try_date('2024') IS NULL, 'un anno non e'' un seriale Excel';

  -- orari
  ASSERT dq.try_time('09:00:02') = TIME '09:00:02', 'hh:mm:ss';
  ASSERT dq.try_time('09:00') = TIME '09:00', 'hh:mm';
  ASSERT dq.try_time('25:00') IS NULL, 'ora inesistente';
  ASSERT dq.try_time('abc') IS NULL, 'testo';

  -- numeri
  ASSERT dq.try_numeric('55,00') = 55.00, 'virgola decimale';
  ASSERT dq.try_numeric('1.234,56') = 1234.56, 'migliaia con punto e virgola decimale';
  ASSERT dq.try_numeric('22') = 22, 'intero';
  ASSERT dq.try_numeric('20.00') = 20.00, 'punto decimale';
  ASSERT dq.try_numeric('-3') = -3, 'negativo';
  ASSERT dq.try_numeric('abc') IS NULL, 'testo';
  ASSERT dq.try_numeric('09:00') IS NULL, 'un orario non e'' un numero';

  -- istanti: ora locale della sorgente (Europe/Rome = UTC+1 a dicembre) oppure assoluti
  ASSERT dq.try_timestamptz('21/12/2024 12:14', 'Europe/Rome') = timestamptz '2024-12-21 11:14:00+00', 'gg/mm/aaaa hh:mm locale';
  ASSERT dq.try_timestamptz('05/12/2025 12:33', 'Europe/Rome') = timestamptz '2025-12-05 11:33:00+00', '5 dicembre, non 12 maggio';
  ASSERT dq.try_timestamptz('20/12/2024 09:00:02', 'Europe/Rome') = timestamptz '2024-12-20 08:00:02+00', 'con secondi';
  ASSERT dq.try_timestamptz('2025-12-19T08:00:05Z', 'Europe/Rome') = timestamptz '2025-12-19 08:00:05+00', 'UTC con Z ignora il fuso della sorgente';
  ASSERT dq.try_timestamptz('2025-12-01 10:00:00', 'Europe/Rome') = timestamptz '2025-12-01 09:00:00+00', 'ISO senza fuso = ora locale';
  ASSERT dq.try_timestamptz('32/12/2025 10:00', 'Europe/Rome') IS NULL, 'giorno inesistente';
  ASSERT dq.try_timestamptz('not-a-date', 'Europe/Rome') IS NULL, 'testo';
END $$;

-- Il risultato NON deve dipendere da DateStyle (con 'ISO, MDY' un gg/mm ambiguo verrebbe letto al contrario).
SET datestyle = 'ISO, MDY';
DO $$ BEGIN
  ASSERT dq.try_timestamptz('05/12/2025 12:33', 'Europe/Rome') = timestamptz '2025-12-05 11:33:00+00', 'DateStyle MDY';
  ASSERT dq.try_date('05/12/2025') = DATE '2025-12-05', 'DateStyle MDY (date)';
END $$;
SET datestyle = 'ISO, DMY';
DO $$ BEGIN
  ASSERT dq.try_timestamptz('05/12/2025 12:33', 'Europe/Rome') = timestamptz '2025-12-05 11:33:00+00', 'DateStyle DMY';
END $$;
RESET datestyle;

-- add_anomaly: regola o batch inesistenti sono errori, non silenzio.
DO $$
DECLARE ok boolean := false;
BEGIN
  BEGIN
    PERFORM dq.add_anomaly(-1, 'REGOLA-INESISTENTE', 1, 'x');
  EXCEPTION WHEN others THEN ok := true;
  END;
  ASSERT ok, 'add_anomaly deve fallire per regola/batch inesistenti';
END $$;

\echo 'ingest_functions_smoke: tutti i controlli superati'

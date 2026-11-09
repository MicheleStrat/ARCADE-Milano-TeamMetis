# BID-01 · Task 2 — Colonne, formati, identificativi e relazioni tra file

> Task: *Verificare colonne, formati, identificativi e relazioni tra file.*
> Metodo: ogni campo di ogni file è stato letto come testo e verificato contro il formato atteso; le relazioni sono state controllate chiave per chiave. Numeri ricalcolati con un secondo script indipendente.

## 1. Dizionario delle colonne

### Biglietteria (identica nelle due edizioni)

| Colonna | Formato | Valori / note | Vuoti |
|---|---|---|---|
| `ID ordine` | `O{aa}NNNNNN` | un ordine contiene 1+ biglietti | 0 |
| `ID biglietto` | `T{aa}NNNNNN` | **chiave**, univoca | 0 |
| `Data acquisto` | `gg/mm/aaaa hh:mm` (ora locale, senza secondi) | | 0 |
| `Canale` | testo | Online, Cassa, Rivenditore partner | 0 |
| `Tipo biglietto` | testo | 8 valori, **nomi diversi tra 2024 e 2025** | 0 |
| `Giorno valido` | `gg/mm/aaaa` **oppure** "3 giorni" | "3 giorni" = abbonamento | 0 |
| `Prezzo` | decimale con **virgola** | 0,00 per gratuiti | 0 |
| `Persone` | intero | 1, oppure 4 (Family) | 0 |
| `Fascia eta titolare` | testo | 0-7, 8-13, 14-17, 18-24, 25-34, 35-44, 45+, `famiglia` | 1.382 / 1.719 |
| `Provincia` | testo libero | sigla, nome esteso, maiuscolo/minuscolo (64 varianti) | 2.158 / 2.525 |
| `Codice sconto` | testo | EARLY10, SCUOLA, STUDENTI | 26.411 / 31.286 (atteso) |

### Tornelli

| Concetto | 2024 | 2025 |
|---|---|---|
| Data-ora | `data` `gg/mm/aaaa` + `ora` `hh:mm:ss` (separate, **fuso non dichiarato**) | `timestamp_utc` ISO 8601 `…Z` (UTC) |
| Biglietto | `codice` | `ticket_code` |
| Varco | `varco`: `P1 Nord`, `P1 Sud`, `P2 Ovest`, `P3 Est` | `gate_id`: `P1-Nord`, `P1-Sud`, `P2-Ovest`, `P3-Est` |
| Esito | `esito`: `1` / `0` | `result`: `OK` / `KO` |
| Separatore | `;`, CRLF | `,` |

### Visite e contatti (2025)

| File | Colonna | Formato / valori |
|---|---|---|
| Visite | `codice_stand` | `P{1-3}-{A-C}{nn}` |
| | `data`, `ora` | `aaaa-mm-gg`, `hh:mm` (ora piena, locale presunta) |
| | `scansioni` | intero ≥ 0 |
| Contatti | `id_contatto` | `L25NNNNN`, univoco |
| | `codice_stand`, `id_espositore` | come planimetria e anagrafica |
| | `timestamp` | `aaaa-mm-gg hh:mm` (locale presunta, senza fuso) |
| | `email` | indirizzo (dato personale) |
| | `fascia_eta` | 14-17, 18-24, 25-34, 35-44, 45+ |
| | `provincia` | sigla (21 valori, **uniforme**, a differenza della biglietteria) |
| | `consenso_marketing` | SI; **9 vuoti** |
| | `interesse` | beta test, newsletter, evento, prodotto, lavoro/stage |

### Commerciale (`ARCADE_Commerciale.xlsx`)

| Foglio | Righe | Colonne |
|---|---|---|
| `Espositori` | 135 | `id_espositore`, `ragione_sociale`, `partita_iva`, `settore`, `citta`, `referente`, `email_referente` |
| `Planimetria` | 130 | `codice_stand`, `padiglione`, `nome_padiglione`, `mq`, `posizione` (linea / angolo / penisola / isola), `attivo_dal` |
| `Listino_2026` | 20 | `codice`, `voce`, `unita`, `prezzo_unitario_eur`, `disponibilita`, `note` |
| `Contratti` | 198 | `id_contratto`, `edizione`, `id_espositore`, `ragione_sociale`, `partita_iva`, `codice_stand`, `data_firma`, `imponibile_listino_eur`, `sconto_pct`, `imponibile_eur`, `acconto_scadenza`, `acconto_pagato_il`, `saldo_scadenza`, `saldo_pagato_il`, `rinnovo` |
| `Righe_contratto` | 950 | `id_contratto`, `riga`, `codice_voce`, `descrizione`, `quantita`, `prezzo_unitario_eur`, `importo_eur` |

Colonne mancanti o non coerenti con i requisiti del progetto: nessun identificativo di **uscita** ai varchi; nessun legame **visitatore↔stand**; nessun **stato/preventivo/2026** nei contratti; nessun **flag stand riservato/non vendibile** in planimetria; nessun **importo** di acconto/saldo.

## 2. Formati: confronto tra file

| Elemento | Formati presenti nei file |
|---|---|
| Data-ora | `gg/mm/aaaa hh:mm` (biglietteria) · `gg/mm/aaaa` + `hh:mm:ss` (tornelli 2024) · ISO UTC (tornelli 2025) · `aaaa-mm-gg` + `hh:mm` (visite) · `aaaa-mm-gg hh:mm` (contatti) · data Excel (contratti) |
| Decimali | virgola (biglietteria) · punto (Excel) |
| Percentuali | frazione (`0,15`, Excel) |
| Provincia | mista (biglietteria) · sigla (contatti) |
| Esito lettura | `1/0` · `OK/KO` |
| Fuso | non dichiarato (tutti tranne tornelli 2025) |

Tutti i file devono essere ricondotti a un unico formato canonico (documento 04, §3–4; convenzioni proposte nel report, §12).

## 3. Identificativi

| Identificativo | Formato | Univoco | Usato in |
|---|---|---|---|
| Biglietto | `T{aa}######` (il prefisso a 2 cifre = edizione) | ✔ 35.719 / 42.556, nessun formato anomalo | biglietteria, tornelli |
| Ordine | `O{aa}######` | ✔ (21.500 / 25.500 ordini) | biglietteria |
| Stand | `P{1-3}-{A-C}{nn}` | ✔ 130 in planimetria | planimetria, contratti, visite, contatti |
| Espositore | `ESP###` | ✔ 135 | anagrafica, contratti 2025, contatti |
| Contratto | `C{aaaa}-{nnnn}` (anno = edizione) | ✔ 198 | contratti, righe |
| Contatto | `L25NNNNN` | ✔ 1.707 | contatti |
| Edizione | intero (2024, 2025) | — | contratti; **nei biglietti è implicita nel prefisso** |
| Partita IVA | 11 cifre | ✔ 135 (letta come numero perde lo zero iniziale) | anagrafica, contratti |
| Lettura tornello | **nessun identificativo** | ✘ | tornelli |
| Riga visita | (stand, data, ora) | ✔ | visite |

Lacune: le letture ai tornelli non hanno ID proprio (la deduplicazione si basa su biglietto + varco + istante); l'edizione non è un campo nei file di biglietteria e tornelli.

## 4. Relazioni tra file

| Relazione | Chiave | Esito |
|---|---|---|
| Tornelli → biglietteria | codice biglietto | letture OK 100% riconciliate; 35 codici/anno inesistenti, tutti KO |
| Tornelli ↔ validità biglietto | codice + data | 0 eccezioni sui giornalieri; abbonamenti usati 1–3 giorni |
| Tornelli ↔ acquisto | `Data acquisto` ≤ lettura | **13% violato**, ~94% Cassa |
| Visite → planimetria | `codice_stand` | 100% |
| Visite → contratti 2025 | `codice_stand` | 0 visite su stand senza contratto; **84 su 110** stand contrattualizzati hanno visite |
| Contatti → stand → espositore | `codice_stand`, `id_espositore` | 100% coerenti con il contratto 2025 |
| Contratti 2025 → anagrafica | `id_espositore` | 100%; nome e P.IVA identici |
| Contratti 2024 → anagrafica | nome | **88/88 senza ID**; derivabili (79 identici + 9 con regola) |
| Contratti → planimetria | `codice_stand` | 100%; nessuno stand non attivo nell'edizione |
| Righe → contratti | `id_contratto` | 100%; somma righe = imponibile listino in 198/198 |
| `SPAZIO` ↔ planimetria | quantità = m² | 198/198 |
| Flag `rinnovo` 2025 ↔ contratto 2024 | espositore | coerente in 110/110 (70 rinnovi, 69 con lo stesso stand) |
| Espositori 2024 non rinnovati | — | **18** |
| Biglietteria ↔ stand | — | **nessuna relazione** nei dati |
| Contatti ↔ biglietto / scansione | — | **nessuna relazione** nei dati |

**Collegamenti assenti:** visitatore↔stand, contatto↔biglietto, uscite dai varchi, contratto 2026.

## 5. Esito

- Le colonne e i formati sono tutti leggibili; l'unica non conformità strutturale è la P.IVA (zeri) e i formati eterogenei tra file.
- Gli identificativi sono univoci e ben formati; manca l'ID del 2024 negli espositori dei contratti e l'ID delle letture ai tornelli.
- Le relazioni sono integre, con le eccezioni elencate: sono le anomalie del documento **03** e del registro nel documento **04**.

# BID-01 · Task 3 — Duplicati, valori nulli, date incoerenti, riferimenti mancanti

> Task: *Individuare duplicati, valori nulli, date incoerenti e riferimenti mancanti.*
> Metodo: sola lettura dei file originali; ogni numero è stato ricalcolato da due script indipendenti (pandas e libreria standard / openpyxl). Nessun record è stato modificato o eliminato.
> Il trattamento proposto per ogni anomalia e le domande al cliente sono nel documento **04** (registro e regole), non qui.

---

## 1. Duplicati

| Fonte | Controllo | 2024 | 2025 | Esito |
|---|---|---|---|---|
| Biglietteria | `ID biglietto` ripetuto | 0 | 0 | ✔ |
| Biglietteria | righe completamente identiche | 0 | 0 | ✔ |
| Biglietteria | `ID ordine` su più biglietti | 21.500 ordini / 35.719 righe | 25.500 / 42.556 | normale (un ordine ha più biglietti) |
| Tornelli | righe completamente identiche | 0 | 0 | ✔ |
| Tornelli | stesso biglietto, stesso varco, ≤60 s, biglietto **singolo** (`Persone` = 1) | **732** | **900** | possibile doppia lettura |
| Tornelli | stesso biglietto, stesso varco, ≤60 s, **Family** | 209 | 244 | probabilmente legittimo (4 persone) |
| Tornelli | (biglietto, giorno) con più letture OK | 3.057 | 3.692 | di cui singoli 732 / 900; il resto sono Family |
| Visite stand | (stand, data, ora) ripetuto | 0 | 0 | ✔ (solo 2025) |
| Contatti stand | `id_contatto` ripetuto | — | 0 | ✔ |
| Contatti stand | e-mail ripetuta | — | 38 righe / 19 indirizzi | tutte su **stand diversi**: stesso visitatore, non errore |
| Commerciale | `id_espositore`, P.IVA, e-mail, ragione sociale duplicate | 0 | 0 | ✔ |
| Commerciale | `codice_stand` duplicato in Planimetria | 0 | 0 | ✔ |
| Commerciale | `id_contratto` duplicato; stand venduto due volte nella stessa edizione | 0 | 0 | ✔ |
| Commerciale | (`id_contratto`, `riga`) duplicato | 0 | 0 | ✔ |

**Lettura:** gli unici duplicati reali sono nei tornelli e vanno trattati con una regola di deduplicazione concordata, non cancellati (A-T03). Una doppia lettura "ravvicinata" non è per forza un errore: nei Family un biglietto vale quattro ingressi.

---

## 2. Valori nulli

| Fonte | Campo | 2024 | 2025 | Nota |
|---|---|---|---|---|
| Biglietteria | `Fascia eta titolare` | 1.382 (3,9%) | 1.719 (4,0%) | in tutti i tipi di biglietto |
| Biglietteria | `Provincia` | 2.158 (6,0%) | 2.525 (5,9%) | |
| Biglietteria | `Codice sconto` | 26.411 (73,9%) | 31.286 (73,5%) | **atteso**: nessuno sconto |
| Biglietteria | `Giorno valido` = "3 giorni" | 5.602 | 6.815 | non nullo ma non una data: abbonamenti |
| Biglietteria | tutte le altre colonne | 0 | 0 | ✔ |
| Tornelli | tutte le colonne | 0 | 0 | ✔ |
| Visite stand | tutte le colonne | — | 0 | ✔ |
| Contatti stand | `consenso_marketing` | — | **9** | e-mail presente |
| Contatti stand | tutte le altre colonne | — | 0 | ✔ |
| Espositori / Planimetria / Righe | tutte le colonne | 0 | 0 | ✔ |
| Contratti | `id_espositore` | **88 (tutti)** | 0 | solo il 2024 |
| Contratti | `partita_iva` | **88 (tutti)** | 0 | solo il 2024 |
| Contratti | `acconto_pagato_il` | 1 | 7 | pagato o non registrato? |
| Contratti | `saldo_pagato_il` | 3 | 5 | pagato o non registrato? |

**Lettura:** i nulli "strutturali" (codice sconto, 2024 senza ID) sono attesi o riparabili con una regola; i nulli di dominio (pagamenti, consenso) richiedono una decisione perché il significato del vuoto non è documentato. Province e fasce d'età vuote **non** vanno imputate (nessuna regola affidabile).

---

## 3. Date e orari incoerenti

### Biglietteria e tornelli
| Controllo | 2024 | 2025 | Esito |
|---|---|---|---|
| Date di acquisto non leggibili | 0 | 0 | ✔ (03/07–22/12/2024; 02/07–21/12/2025) |
| Acquisto successivo al giorno di validità | 0 | 0 | ✔ |
| Timestamp tornelli non leggibili | 0 | 0 | ✔ |
| Letture fuori dai 3 giorni di edizione | 0 | 0 | ✔ (2024: 20–22/12; 2025: 19–21/12) |
| Lettura OK su biglietto giornaliero in un giorno diverso da `Giorno valido` | 0 | 0 | ✔ |
| Buchi >90 s tra letture durante l'apertura | 0 | 0 | ✔ |
| **Lettura OK precedente all'orario di acquisto** | **6.042 (13,0%)** | **7.488 (13,4%)** | **anomalia** |
| …di cui acquisto in Cassa | 5.670 | 6.988 | ~94% |
| …acquisto e lettura nello stesso giorno | 88,7% | 88,6% | anticipo mediano 2,9 h, massimo ~54 h |

Il fuso del file 2024 non è dichiarato (assunto: ora locale). Per il 2025 il timestamp è UTC e viene convertito in Europe/Rome (UTC+1 a dicembre); date e ore locali risultano coerenti con l'orario di apertura (09:00–17:30).

### Stand
| Controllo | Esito |
|---|---|
| Date visite nei 3 giorni di edizione 2025 | ✔ |
| Ore delle visite 09:00–18:00 | **1 riga a 08:00** (P1-A02, 19/12, 912 scansioni) |
| Timestamp contatti 19–21/12/2025, 09:31–18:49 | ✔ |
| Contatti in uno slot senza riga di visita / con 0 scansioni | 38 / 42 |

### Commerciale
| Controllo | Esito |
|---|---|
| Firma contratto successiva all'edizione | 0 |
| Acconto pagato prima della firma | 0 |
| `acconto_scadenza` = firma + 15 giorni | 198/198 (regola uniforme) |
| `saldo_scadenza` fissa per edizione (20/11/2024, 19/11/2025 = 30 giorni prima dell'apertura) | ✔ |
| **Saldo pagato prima dell'acconto** | **2** (C2024-0078, C2025-0116) |
| **`saldo_scadenza` precedente a `acconto_scadenza`** | **1** (C2025-0120, firmato il 06/11/2025) |
| Saldo pagato dopo l'apertura della fiera | 11 (2024), 14 (2025) — informativo |

---

## 4. Riferimenti mancanti

| Riferimento | Esito | Note |
|---|---|---|
| Tornelli → biglietto (codice) | **35 codici/anno inesistenti** | tutti con esito KO; codici `T24 9xxxxx` / `T25 9xxxxx`, fuori dall'intervallo venduto |
| Biglietti mai passati ai tornelli | 1.272 (3,6%) / 1.515 (3,6%) | no-show, non un errore |
| Visite stand → planimetria | 0 mancanti | ✔ |
| Visite stand → stand non attivo nel 2025 | 0 | ✔ |
| Contatti → stand / espositore / contratto 2025 | 0 mancanti, 0 incoerenti su 1.707 | ✔ |
| Contratti 2025 → anagrafica espositori | 0 mancanti; nome e P.IVA identici | ✔ |
| **Contratti 2024 → anagrafica espositori** | **88/88 senza ID**; derivabili per nome (79 identici + 9 con regola) | A-C02 |
| Contratti → planimetria | 0 mancanti; nessuno stand non attivo | ✔ |
| Righe → contratti / contratti senza righe | 0 / 0 | ✔ |
| Stand con contratto 2025 **senza alcuna visita** | **26 su 110** | scanner non presente o dato mancante? |
| Visite dell'edizione 2024 | **file assente** | confronto 2024/2025 non possibile |
| Contratti / preventivi 2026 | **assenti** | arrivano dal BAD |
| Uscite dai varchi | **assenti** | presenza contemporanea non calcolabile |

---

## 5. Sintesi per gravità

| Gravità | Problema | Perché conta |
|---|---|---|
| Alta | Letture prima dell'acquisto (13%) | falsa l'analisi oraria degli acquisti e il legame biglietto→ingresso |
| Alta | Doppie letture (732/900 singoli) | cambia il numero di "presenze" di circa 1,6% |
| Alta | Nessuna uscita ai varchi | il picco di presenza non è calcolabile |
| Alta | Contratti 2024 senza ID espositore | il confronto per espositore tra edizioni non è possibile senza la derivazione |
| Alta | 912 scansioni fuori orario | falsa il totale visite (+2,5%) di un solo stand |
| Media | Pagamenti vuoti (16 contratti) e date incoerenti (3) | rende incerti gli "incassi effettivi" |
| Media | 9 consensi vuoti, 14 minori con e-mail | rischio privacy, vincolo di legge |
| Media | 26 stand senza visite, nessun 2024 per le visite | limita il costo per contatto e i confronti |
| Bassa | Province/fasce d'età vuote o scritte in modo diverso | normalizzazione deterministica |
| Bassa | Etichette dei tipi biglietto diverse tra edizioni | tabella di decodifica |

*Script di riferimento:* `script/profile_*.py` (analisi), `script/verify_*.py` (controllo indipendente).

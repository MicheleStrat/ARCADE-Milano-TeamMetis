# BID-01 · Task 4 — Documentare le anomalie e proporre le regole di correzione

> Task: *Documentare le anomalie e proporre le regole di correzione.*
> Stato: **proposta** — nessuna regola è stata approvata dal cliente o dal BAD. Le regole sono riproducibili con `script/applica_regole_dry_run.py` (esecuzione in prova, nessun file modificato).
> Dettaglio e motivazione di ogni anomalia: `BID-01_report_profilazione.md` (§6 e §10).

## 1. Principi applicati

1. **Nessun record viene eliminato in silenzio.** Ogni record riceve un esito: `OK` (valido), `CORRETTO` (regola deterministica, valore originale conservato), `SEGNALATO` (accettato con flag, decisione al cliente), `QUARANTENA` (escluso dai conteggi finché non confermato, ma conservato).
2. **Si normalizza solo quando la regola è deterministica.** Province e fasce d'età vuote restano NULL: nessuna imputazione.
3. **Biglietti venduti ≠ ingressi ≠ persone presenti.** Tre misure distinte, mai sostituite una con l'altra.
4. **I dati dei minori sono protetti** per costruzione (solo aggregati verso espositori e portali).
5. Le decisioni che spettano al cliente restano **aperte** (classe D) e non vengono presentate come approvate.

## 2. Registro delle anomalie (38 voci)

Classe: **V** valido · **C** correggibile in modo deterministico · **Q** quarantena/segnalazione · **D** decisione necessaria.

### Biglietteria

| ID | Sintesi | Volume 2024 / 2025 | Classe | Regola |
|---|---|---|---|---|
| A-B01 | Etichette del tipo biglietto diverse tra edizioni | 100% delle righe | C | R-B01 |
| A-B02 | `Giorno valido` = "3 giorni" invece di una data | 5.602 / 6.815 | C | R-B02 |
| A-B03 | Province scritte in modo diverso; vuote | 13.383 / 16.133 da normalizzare; 2.158 / 2.525 vuote | C | R-B03 |
| A-B04 | Fascia d'età vuota | 1.382 / 1.719 | C / D | R-B04 |
| A-B05 | Vuoti non imputabili dal primo biglietto dell'ordine | — | D | nessuna (non imputare) |
| A-B06 | Codici SCUOLA/STUDENTI senza effetto sul prezzo | 6.184 / 7.562 | D | nessuna (importare com'è) |
| A-B07 | `Persone` = 4 solo per i Family | 2.420 / 2.901 | V | — |

### Tornelli

| ID | Sintesi | Volume | Classe | Regola |
|---|---|---|---|---|
| A-T01 | Formati diversi 2024 / 2025 | 100% | C | R-T01 |
| A-T02 | Codici non presenti in biglietteria (tutti KO) | 35 / 35 | Q | R-T02 |
| A-T03 | Doppie letture ≤60 s stesso varco | 732 / 900 singoli; 209 / 244 Family | D | R-T04 |
| A-T04 | Family con 1–6 letture al giorno | — | D | nessuna (conservare) |
| A-T05 | Lettura OK prima dell'acquisto | 6.042 / 7.488 | D | R-T05 |
| A-T06 | KO su biglietti noti, motivo assente | 195 / 221 | D | R-T03 |
| A-T07 | Nessun evento di uscita | — | D | nessuna (documentare il limite) |
| A-T08 | Ingressi su più padiglioni nello stesso giorno | 1.676 / 2.029 | D | nessuna (distinguere ingressi da accessi) |

### Stand

| ID | Sintesi | Volume | Classe | Regola |
|---|---|---|---|---|
| A-S01 | 912 scansioni alle 08:00 (P1-A02) | 1 riga | Q | R-S01 |
| A-S02 | Slot orari mancanti | 70 su 2.520 | Q | R-S02 |
| A-S03 | Scansioni = 0 | 159 | V | R-S03 |
| A-S04 | Stand con contratto 2025 senza visite | 26 su 110 | D | nessuna |
| A-S05 | Nessun file visite 2024 | — | D | nessuna |
| A-S06 | Scansioni aggregate per ora, senza visitatore | — | D | nessuna |
| A-S07 | E-mail ripetute su stand diversi | 38 righe / 19 indirizzi | V / D | R-S06 |
| A-S08 | Consenso marketing vuoto | 9 | Q | R-S04 |
| A-S09 | Contatti 14-17 anni con e-mail e consenso SI | 14 | Q | R-S05 |

### Relazioni e commerciale

| ID | Sintesi | Volume | Classe | Regola |
|---|---|---|---|---|
| A-R01 | → vedi A-C02 | — | C / D | R-C01 |
| A-R02 | Planimetria: 115 stand dal 2024, 15 dal 2025 | 130 | V | usare `attivo_dal` |
| A-C01 | P.IVA letta come numero perde lo zero iniziale | 135 | C | R-C02 |
| A-C02 | Contratti 2024 senza `id_espositore` e P.IVA; nomi con varianti | 88 (79 identici + 9 con plurale errato) | C / D | R-C01 |
| A-C03 | Pagamenti non registrati (acconto o saldo) | 16 su 198 | D | R-C03 |
| A-C04 | Date di pagamento/scadenza in ordine incoerente | 3 | Q | R-C04 |
| A-C05 | Percentuali e importi di acconto/saldo non memorizzati | 198 | D | nessuna |
| A-C06 | Saldo pagato dopo l'apertura della fiera | 11 / 14 | V | — |
| A-C07 | Codici voce non allineati (`MAGG` vs `MAGG-ANGOLO/-PENISOLA/-ISOLA`; unità miste nel listino) | — | C | R-C05 |
| A-C08 | Prezzi storici 2024/2025 solo nelle righe contratto | — | D | nessuna |
| A-C09 | Sconto applicato anche a sponsor ed extra | 198 | D | nessuna |
| A-C10 | Sponsorizzazioni non legate a una superficie | 15 / 17 righe | D | nessuna |
| A-C11 | Nessun contratto/preventivo 2026 nel file | — | D (BAD) | nessuna |
| A-C12 | Superfici costanti tra le edizioni | — | D | nessuna |

## 3. Regole di pulizia proposte

| Regola | Si applica a | Trasformazione | Anomalia | Reversibile |
|---|---|---|---|---|
| **R-B01** | Biglietteria | `Tipo biglietto` → codice canonico (tabella §4.1); etichetta originale conservata | A-B01 | sì |
| **R-B02** | Biglietteria | `Giorno valido` = "3 giorni" → `giorno_valido` NULL + flag `abbonamento` | A-B02 | sì |
| **R-B03** | Biglietteria | `Provincia`: maiuscole + nome esteso → sigla (tabella §4.2); vuota → NULL; non riconosciuta → quarantena | A-B03 | sì |
| **R-B04** | Biglietteria | `Fascia eta`: vuota → NULL; ammessi 0-7, 8-13, 14-17, 18-24, 25-34, 35-44, 45+, famiglia; altro → quarantena | A-B04 | sì |
| **R-B05** | Biglietteria | `Prezzo`: virgola → decimale; non numerico o negativo → quarantena | — (formato) | sì |
| **R-B06** | Biglietteria | Fascia 0-7, 8-13, 14-17 → flag `minorenne`; mai esposti dati individuali | — (protezione) | — |
| **R-T01** | Tornelli | Armonizza: timestamp locale Europe/Rome (2025: UTC → locale), varco `P1-Nord` / `P1-Sud` / `P2-Ovest` / `P3-Est`, esito booleano | A-T01 | sì |
| **R-T02** | Tornelli | Codice assente in biglietteria → lettura conservata come **respinta**, mai conteggiata come ingresso | A-T02 | sì |
| **R-T03** | Tornelli | KO su biglietto noto → conservato come KO, non conteggiato | A-T06 | sì |
| **R-T04** | Tornelli | Stessa chiave (biglietto + varco) entro 60 s: flag `sospetto_doppione` **solo** per biglietti singoli. I Family non vengono flaggati. Nessuna riga scartata | A-T03 | sì |
| **R-T05** | Tornelli | Lettura OK con orario < acquisto → flag `acquisto_posteriore_a_ingresso`; la lettura resta valida | A-T05 | sì |
| **R-S01** | Visite | Ora fuori da 09:00–18:00 → quarantena (esclusa dai totali) | A-S01 | sì |
| **R-S02** | Visite | Slot mancante → **non imputato**; distinguere "0 scansioni" da "dato assente" | A-S02 | — |
| **R-S03** | Visite | Scansioni = 0 → valido | A-S03 | — |
| **R-S04** | Contatti | `consenso_marketing` vuoto → trattato come **NO** | A-S08 | sì |
| **R-S05** | Contatti | Fascia 14-17 → e-mail e dettaglio non esposti; solo conteggi aggregati | A-S09 | — |
| **R-S06** | Contatti | E-mail ripetuta su stand diversi → mantenere; contatti unici = e-mail distinte | A-S07 | — |
| **R-C01** | Contratti 2024 | `id_espositore` derivato dal nome: (1) nome identico dopo normalizzazione (minuscole, senza forma legale e punteggiatura); (2) altrimenti regola "s" finale, solo se la corrispondenza è unica. Origine registrata (`derivato`), nome originale conservato | A-C02 | sì |
| **R-C02** | Espositori | P.IVA sempre testo di 11 cifre | A-C01 | — |
| **R-C03** | Contratti | Date di pagamento vuote conservate NULL; nessuno stato di pagamento dedotto | A-C03 | — |
| **R-C04** | Contratti | Saldo pagato prima dell'acconto o scadenze invertite → segnalato | A-C04 | — |
| **R-C05** | Contratti / Listino | Voce `MAGG` → `MAGG-ANGOLO/-PENISOLA/-ISOLA` in base alla posizione dello stand (verificato: 10% / 15% / 25% su area) | A-C07 | sì — *da implementare in BID-03* |

### Regole che dipendono da una decisione (non applicate finché non confermate)
- **R-T04**: la soglia di 60 s e il trattamento dei Family (vedi §5).
- **R-T05** e **R-S01**: se i record vanno definitivamente accettati o corretti.
- **R-S04**: se un consenso vuoto equivale davvero a "NO".

## 4. Tabelle di decodifica

### 4.1 Tipo biglietto (R-B01)

| Codice canonico | Etichetta 2024 | Etichetta 2025 |
|---|---|---|
| INTERO | Intero | Giornaliero intero |
| RIDOTTO | Ridotto | Giornaliero ridotto 8-14 anni |
| FAMILY | Family | Family 2 adulti + 2 ragazzi |
| GRATUITO_U8 | Omaggio U8 | Gratuito under 8 |
| ABB_3GG | Abb. 3gg | Abbonamento 3 giorni |
| BUSINESS | Business | Business Day (venerdì mattina) |
| VIP | VIP | VIP Experience |
| STAMPA | Stampa | Accredito stampa |

*Assunzione da confermare:* la corrispondenza è 1:1. I prezzi cambiano tra edizioni (es. Intero 20 € → 22 €), perciò il codice canonico non implica lo stesso listino.

### 4.2 Province (R-B03)
BERGAMO→BG · BOLOGNA→BO · BRESCIA→BS · COMO→CO · CREMONA→CR · FIRENZE→FI · GENOVA→GE · LECCO→LC · LODI→LO · MILANO→MI · MONZA E BRIANZA→MB · NAPOLI→NA · NOVARA→NO · PADOVA→PD · PARMA→PR · PAVIA→PV · PIACENZA→PC · ROMA→RM · TORINO→TO · VARESE→VA · VERONA→VR (21 nomi; 21 sigle già presenti nei dati).

### 4.3 Varchi ed esito (R-T01)
`P1 Nord` / `P1-Nord` → **P1-Nord** · `P1 Sud` → **P1-Sud** · `P2 Ovest` → **P2-Ovest** · `P3 Est` → **P3-Est**. Esito: `1` / `OK` → accettata; `0` / `KO` → respinta.

## 5. Assunzioni (tutte da confermare)

| ID | Assunzione | Chi conferma |
|---|---|---|
| AS-1 | Gli orari dei tornelli 2024 sono ora locale (fuso non dichiarato) | cliente |
| AS-2 | I timestamp 2025 sono UTC e vanno letti in Europe/Rome (UTC+1 a dicembre) | cliente |
| AS-3 | Il padiglione di un ingresso è il prefisso del varco (P1, P2, P3) | cliente |
| AS-4 | Un valore vuoto significa informazione assente, non "non applicabile" | cliente |
| AS-5 | Consenso marketing vuoto = NO (scelta prudenziale) | cliente / legale |
| AS-6 | Un biglietto Family (Persone = 4) dà diritto a quattro ingressi | cliente |
| AS-7 | Il prezzo è per biglietto, non per persona | cliente |
| AS-8 | Una lettura KO non corrisponde a un ingresso | cliente |
| AS-9 | La superficie degli stand è costante tra le edizioni (`attivo_dal` unico dato storico) | BAD |
| AS-10 | Il nome dell'espositore nei contratti 2024 identifica una sola azienda dell'anagrafica | BAD |

## 6. Verifica: esecuzione in prova delle regole

`python3 -I script/applica_regole_dry_run.py <cartella file sorgente>` — scrive `script/risultati_dry_run.csv`. Risultato su tutti i dati forniti (2024 / 2025):

| Fonte | Esito | Regola | Descrizione | 2024 | 2025 |
|---|---|---|---|---|---|
| Biglietteria | CORRETTO | R-B01 | tipo decodificato | 35.719 (100%) | 42.556 (100%) |
| Biglietteria | CORRETTO | R-B02 | "3 giorni" → NULL | 5.602 | 6.815 |
| Biglietteria | OK | R-B03 | provincia già valida | 20.178 | 23.898 |
| Biglietteria | CORRETTO | R-B03 | provincia normalizzata | 13.383 | 16.133 |
| Biglietteria | SEGNALATO | R-B03 / R-B04 | provincia / fascia vuote | 2.158 / 1.382 | 2.525 / 1.719 |
| Biglietteria | SEGNALATO | R-B06 | minorenni | 13.115 | 15.384 |
| Biglietteria | QUARANTENA | tutte | tipo, data, provincia, fascia, prezzo non validi | **0** | **0** |
| Tornelli | SEGNALATO | R-T02 | codice sconosciuto (respinte) | 35 | 35 |
| Tornelli | SEGNALATO | R-T03 | KO su biglietto noto | 195 | 221 |
| Tornelli | SEGNALATO | R-T04 | doppie letture, biglietti singoli | 732 | 900 |
| Tornelli | SEGNALATO | R-T05 | lettura prima dell'acquisto | 6.042 | 7.488 |
| Tornelli | QUARANTENA | R-T01 / R-T02 | timestamp illeggibile, OK su codice sconosciuto | **0** | **0** |
| Visite stand | QUARANTENA | R-S01 | riga a 08:00 (912 scansioni) | — | 1 |
| Visite stand | SEGNALATO | R-S02 | slot mancanti | — | 70 su 2.520 |
| Contatti | CORRETTO | R-S04 | consenso vuoto → NO | — | 9 |
| Contatti | SEGNALATO | R-S05 | minori 14-17 | — | 14 |
| Contratti 2024 | CORRETTO | R-C01 | ID derivato: 79 identici + 9 con regola "s" | 88 su 88 | — |
| Contratti | SEGNALATO | R-C03 / R-C04 | pagamenti mancanti / date incoerenti | 16 / 3 su 198 | |

**Cosa mostra la verifica:** nessun record resta non classificabile; l'unica quarantena è la riga delle 912 scansioni. Le regole non eliminano nulla.

### Effetto sulle "presenze" (decisione aperta)

| Lettura OK (accettate) | 2024 | 2025 | Brief |
|---|---|---|---|
| Tutte le letture OK | 46.594 | 55.736 | |
| Esclusi i soli doppioni su biglietti singoli | 45.862 | 54.836 | 45.700 / 54.600 → **non coincide** |
| Esclusi **tutti** i doppioni ≤60 s (Family inclusi) | 45.653 | 54.592 | 45.700 / 54.600 → **coincide al centinaio** |

Il brief indica 45.700 e 54.600 presenze. Il numero torna solo se si scartano anche le letture ravvicinate dei Family; potrebbe essere la regola usata dal cliente, ma anche una coincidenza: da confermare prima di fissarla (punto 3 del documento 05).

## 7. Limiti di questa proposta

- Le regole sono verificate **sui dati forniti**, non su un flusso reale: l'importazione definitiva (BID-03) dovrà gestire anche file malformati e colonne mancanti, che qui non compaiono.
- R-C05 non è ancora implementata nello script di prova.
- La soglia di 60 s per i doppioni è un'ipotesi, non una definizione del cliente.

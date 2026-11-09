# BID-01 — Report di profilazione dati sorgente (biglietteria, tornelli, visite stand, commerciale, relazioni)

> Struttura: §1–9 = task 1 (biglietteria, tornelli, visite/contatti stand). §10–12 = task 2 (file commerciale, matrice delle relazioni tra file, convenzioni proposte).

Scope: BID + SHARED · Edizioni 2024 e 2025 · Stato: **bozza per revisione** — le regole sono *proposte*, non approvate dal cliente né dal team BAD.
Metodo: sola lettura dei file originali; nessun record modificato o eliminato. Gli script in `script/` sono rieseguibili. I numeri chiave sono stati ricalcolati con un secondo script indipendente (solo libreria standard) e coincidono.

> Nota: il repository `ARCADE-Milano-TeamMetis` non è presente in questo workspace; l'analisi è stata fatta direttamente sui file caricati nel progetto. Non ho verificato branch, struttura o codice esistente.

---

## 1. Sintesi

| Fonte | 2024 | 2025 | Riferimento brief |
|---|---|---|---|
| Righe biglietteria | 35.719 (21.500 ordini) | 42.556 (25.500 ordini) | 35.700 / 42.600 biglietti; ~78.000 righe totali ✔ |
| Persone (somma colonna `Persone`) | 42.979 | 51.259 | — |
| Letture tornelli (tutte) | 46.824 | 55.992 | ~103.000 righe totali ✔ |
| Letture OK / KO | 46.594 / 230 | 55.736 / 256 | — |
| Letture OK dopo eliminazione doppie ≤60 s | 45.653 | 54.592 | **45.700 / 54.600 "presenze"** (≈ coincide) |
| Visite stand | non fornite | 2.451 righe, 84 stand, 36.213 scansioni | — |
| Contatti stand | non forniti | 1.707 (1.688 e-mail uniche) | — |

**Esito generale:** nessun errore strutturale bloccante (nessun ID biglietto duplicato, nessuna data illeggibile, nessun riferimento a stand inesistente). Le criticità sono di **eterogeneità tra edizioni**, **qualità dei valori** e **definizioni da concordare**. Tutti i dati sono caricabili in una prima importazione controllata, con i trattamenti indicati in §6.

**Osservazione chiave:** il numero "presenze" del brief (45.700 / 54.600) coincide con le letture OK dei tornelli *dopo aver scartato le doppie letture entro 60 secondi allo stesso varco* (45.653 / 54.592, scarto ≤0,1%). È un'ipotesi plausibile ma **da confermare con il cliente**: la regola scarta anche letture legittime dei Family (4 persone con un solo biglietto), vedi A-T03. Deduplicando solo i biglietti singoli si ottiene invece 45.862 / 54.836, che **non** coincide con il brief; l'allineamento richiede di scartare anche le ravvicinate dei Family (209 / 244).

---

## 2. Biglietteria (`biglietteria_2024.csv`, `biglietteria_2025.csv`)

**Formato:** CSV `;`, decimale con virgola, date `gg/mm/aaaa hh:mm`, 11 colonne identiche tra le edizioni. 2024 ASCII, 2025 UTF-8 (presenza di caratteri accentati).

**Controlli superati (entrambi gli anni):**
- `ID biglietto` univoco e nel formato `T{aa}NNNNNN`; `ID ordine` formato `O{aa}NNNNNN`; nessuno spazio spurio; nessuna riga identica.
- Date acquisto tutte valide (2024: 03/07–22/12; 2025: 02/07–21/12); acquisto mai successivo al giorno di validità.
- Un ordine ha sempre una sola data acquisto e un solo canale.
- Prezzi numerici, mai negativi; coerenti con il tipo (es. 2024 Intero 20,00 / 2025 Giornaliero intero 22,00); `EARLY10` = −10% esatto.
- Canali: Online, Cassa, Rivenditore partner.

**Anomalie e punti aperti:** vedi registro §6 (A-B01…A-B06).

Dato rilevante per i minori: biglietti con fascia 0-7 / 8-13 / 14-17 = **13.115 (36,7%) nel 2024, 15.384 (36,1%) nel 2025**.

---

## 3. Tornelli (`tornelli_2024.csv`, `tornelli_2025.csv`)

**I due file hanno formati diversi** (da armonizzare in un unico modello):

| Campo | 2024 | 2025 |
|---|---|---|
| Separatore / fine riga | `;` / CRLF | `,` / LF |
| Data-ora | `data` `gg/mm/aaaa` + `ora` `hh:mm:ss` (separate, senza fuso) | `timestamp_utc` ISO 8601 UTC |
| Codice biglietto | `codice` | `ticket_code` |
| Varco | `P1 Nord`, `P1 Sud`, `P2 Ovest`, `P3 Est` | `P1-Nord`, `P1-Sud`, `P2-Ovest`, `P3-Est` |
| Esito | `1` / `0` | `OK` / `KO` |

Il fuso orario del 2024 non è dichiarato: le letture vanno dalle 09:00 alle 17:30, quindi assumo ora locale. Per il 2025 la conversione UTC → Europe/Rome dà lo stesso intervallo orario e le stesse date.

**Controlli superati:** formato codice sempre valido; nessun timestamp illeggibile; nessuna riga duplicata identica; nessun buco >90 s durante l'apertura; ogni lettura OK su biglietto giornaliero cade nel giorno di validità (0 eccezioni).

**Il tornello registra solo ingressi, non uscite.** Il varco identifica il padiglione di accesso (P1, P2, P3). Conseguenza: **la presenza contemporanea e il picco di presenza non sono calcolabili con certezza** dai dati forniti (vedi §7).

Altri dati utili: biglietti venduti mai passati ai tornelli 1.272 (3,6%) nel 2024 e 1.515 (3,6%) nel 2025; abbonamenti 3 giorni usati in 1/2/3 giorni (2024: 1.734/2.371/1.310; 2025: 2.052/2.949/1.554).

---

## 4. Visite e contatti stand 2025

**Visite (`visite_stand_2025.csv`):** granularità oraria (stand, data, ora) con conteggio `scansioni`. Nessun duplicato di chiave, nessun codice stand fuori planimetria, nessun stand non attivo nel 2025. 84 stand hanno visite; tutti hanno un contratto 2025.
**Non esiste un file visite 2024**: il confronto 2024/2025 sulle visite agli stand non è possibile.

**Contatti (`contatti_stand_2025.csv`):** 1.707 contatti, tutti con `codice_stand` in planimetria, `id_espositore` in anagrafica e **coerente al 100% con l'espositore del contratto 2025 sullo stand**.

---

## 5. Relazioni tra file

| Relazione | Esito |
|---|---|
| Tornelli → biglietteria (per codice) | 35 codici/anno non presenti in biglietteria, **tutti con esito KO** (codici `T24 9xxxxx` / `T25 9xxxxx`, fuori dall'intervallo venduto) → tentativi con biglietti non validi/falsi |
| Visite stand → planimetria / contratti 2025 | 100% riconciliabili |
| Contatti → stand → espositore | 100% coerenti |
| Stand con contratto 2025 senza alcuna visita | **26 su 110** (es. P1-A04, P1-A06, P2-A09, P3-B02…) |
| Contratti 2024 → anagrafica espositori | `id_espositore` e `partita_iva` **nulli in tutti gli 88 contratti 2024**; riconciliabili 88/88 per ragione sociale (79 esatti, 9 con regola sul plurale errato — vedi A-C02). Stand 2024 tutti in planimetria, nessun duplicato |
| Contratti 2025 | 110 contratti, `id_espositore` e `partita_iva` sempre valorizzati |

---

## 6. Registro anomalie

Classi: **V** = valido; **C** = correggibile in modo deterministico; **Q** = quarantena/segnalazione; **D** = decisione del cliente necessaria. Trattamenti e regole sono **proposte**.

### Biglietteria

| ID | Problema (evidenza) | Regola di validazione | Trattamento proposto | Classe | Da chiarire |
|---|---|---|---|---|---|
| A-B01 | `Tipo biglietto` con etichette diverse tra edizioni (Intero → Giornaliero intero, Abb. 3gg → Abbonamento 3 giorni, Ridotto → Giornaliero ridotto 8-14 anni, Family → Family 2 adulti + 2 ragazzi, Omaggio U8 → Gratuito under 8, Business → Business Day, VIP → VIP Experience, Stampa → Accredito stampa) | Valore ∈ tabella di mappatura | Tabella di decodifica `tipo_biglietto` con codice canonico; conservare l'etichetta originale | C | Conferma della mappatura 1:1 |
| A-B02 | `Giorno valido` contiene "3 giorni" per gli abbonamenti (5.602 / 6.815) invece di una data | Data valida **oppure** "3 giorni" | Campo `giorno_valido` NULL + flag abbonamento (validità = tutti i giorni dell'edizione) | C | — |
| A-B03 | `Provincia`: 64 valori grezzi → 43 distinti dopo maiuscole (sigle, nomi estesi, maiuscole/minuscole miste: MI/MILANO/Milano, MB/Monza e Brianza…); vuota in 6,0% (2.158) e 5,9% (2.525) | Sigla ∈ elenco sigle province | Maiuscole + mappa nome→sigla (21 nomi, deterministica); vuoto → NULL (non "sconosciuta") | C | — |
| A-B04 | `Fascia eta titolare` vuota: 3,9% (1.382) / 4,0% (1.719); valore "famiglia" per i Family; vuoti distribuiti in tutti i tipi | Valore ∈ {0-7, 8-13, 14-17, 18-24, 25-34, 35-44, 45+, famiglia} oppure NULL | Vuoto → NULL; "famiglia" mantenuto come categoria a sé (non è un'età) | C / D | La fascia vuota è informazione assente o non rilevata? |
| A-B05 | Province e fasce età compaiono più spesso vuote nei biglietti successivi al primo dell'ordine (es. 2024: primo biglietto 6,1% vuoto, successivi 6,0%) — nessun pattern evidente | — | Nessuna imputazione dal primo biglietto dell'ordine | D | Se il titolare dell'ordine vale per tutti i biglietti |
| A-B06 | Codice sconto `SCUOLA` e `STUDENTI`: prezzo **invariato** rispetto al listino; solo `EARLY10` applica −10% | — | Importare il codice così com'è; non ricalcolare prezzi | D | Gli sconti SCUOLA/STUDENTI sono tracciati ma senza effetto sul prezzo? |
| A-B07 | `Persone` = 4 solo per i Family (2.420 / 2.901), altrimenti 1; il prezzo è per biglietto, non per persona | `Persone` ∈ {1, 4} | Mantenere; usare `Persone` solo per i conteggi di persone, mai per i ricavi | V | Conferma che Family = 4 ingressi |

### Tornelli

| ID | Problema (evidenza) | Regola di validazione | Trattamento proposto | Classe | Da chiarire |
|---|---|---|---|---|---|
| A-T01 | Formati diversi 2024/2025 (separatore, data, fuso, nome varco, codifica esito) | — | Parser per sorgente → modello unico: `timestamp` con fuso Europe/Rome, `varco` canonico (`P1-Nord`), `esito` booleano | C | Conferma che il 2024 è in ora locale |
| A-T02 | 35 codici/anno non in biglietteria, tutti KO | Codice ∈ biglietti dell'edizione | Registrare come lettura **respinta** (non scartare); non conteggiare come ingresso | Q | Sono tentativi di accesso con biglietti non validi? |
| A-T03 | Doppie letture: 732 (2024) / 900 (2025) biglietti singoli letti due volte **entro 60 s allo stesso varco** (0 su padiglioni diversi). Totale letture ≤60 s stesso codice+varco: 941 / 1.144, di cui il resto sono Family | Stesso codice + varco + ≤60 s | **Non eliminare**; marcare `sospetto_doppione`. Regola candidata: per biglietti con `Persone` = 1 il doppione è scartabile dai conteggi; per Family no | D | Soglia di 60 s e trattamento dei Family; conferma che "presenze" del brief = letture OK deduplicate |
| A-T04 | Family: letture per giorno tra 1 e 6 (4 nel 67–68% dei casi, 1–3 nel resto, 5–6 in 136+6 / 157+1 casi) | — | Conservare tutte; non dedurre persone dal numero di letture | D | Il Family è tracciato con una lettura per persona? Letture >4? |
| A-T05 | **Lettura OK precedente all'acquisto**: 6.042 (13,0%) nel 2024 e 7.488 (13,4%) nel 2025, per il 94% con canale **Cassa**; anticipo mediano ~2,9 h, max ~54 h | `data acquisto` ≤ `lettura` | Non scartare; flag `acquisto_posteriore_a_ingresso`; non usare `Data acquisto` Cassa per l'analisi oraria | D | Il timestamp di acquisto della Cassa è l'orario di registrazione/chiusura cassa? |
| A-T06 | Letture KO su biglietti noti e validi: 195 / 221 (di cui 42 / 52 abbonamenti); quasi mai seguite da OK entro 5 min (0/60 e 1/60 nel campione) | — | Conservare come KO con codice noto | D | Motivo dei rifiuti (non indicato; il file ha solo esito) |
| A-T07 | Nessun evento di uscita; il varco identifica solo l'ingresso al padiglione | — | Documentare il limite (vedi §7) | D | Esistono dati di uscita o conteggi di sala? |
| A-T08 | Ingressi su più padiglioni nello stesso giorno: 1.676 (code,giorno) nel 2024 e 2.029 nel 2025 (2+ padiglioni) | — | Mantenere 1 ingresso per varco; distinguere "ingressi alla fiera" da "accessi ai padiglioni" | D | Un passaggio a P2/P3 è un ingresso alla fiera o un accesso tra padiglioni? |

### Visite e contatti stand 2025

| ID | Problema (evidenza) | Regola di validazione | Trattamento proposto | Classe | Da chiarire |
|---|---|---|---|---|---|
| A-S01 | Riga **P1-A02, 19/12/2025 08:00 con 912 scansioni**: fuori orario (le altre righe sono 09:00–18:00), 5× il massimo orario altrimenti osservato (177). È l'ultima riga del file, in coda rispetto all'ordine | Ora ∈ [09:00, 18:00]; scansioni ≤ soglia statistica | **Quarantena**; escluso dai totali (36.213 → 35.301) finché non confermato | Q | È un test/pre-apertura, un cumulato o un errore? |
| A-S02 | 70 slot orari mancanti su 2.520 attesi (84 stand × 3 giorni × 10 ore) in 44 stand | Un record per (stand, data, ora) | Non imputare; distinguere "0 scansioni" da "dato assente" | Q | Slot assenti = zero scansioni o guasto scanner? |
| A-S03 | 159 righe con scansioni = 0 (140 alle 18:00, 18 alle 17:00) | — | Valide | V | — |
| A-S04 | 26 stand con contratto 2025 senza nessuna visita; altri 20 stand senza contratto 2025 (130 attivi − 110) non hanno dati, com'è atteso | — | Segnalare; nessun dato inventato | D | Scanner non installato o stand non attivato? |
| A-S05 | **Nessun dato visite per il 2024** | — | Confronto visite 2024/2025 non disponibile | D | Esistono dati 2024 oppure il confronto va limitato ai biglietti/ingressi? |
| A-S06 | `scansioni` sono conteggi orari aggregati, non eventi individuali: nessun identificativo visitatore | — | Non calcolare visitatori unici per stand | D | Definizione di "visita" e legame con i contatti |
| A-S07 | Contatti: 38 e-mail duplicate (19 indirizzi su stand diversi, mai sullo stesso stand → stesso visitatore, non errore); 38 contatti senza riga di visita nello slot e 42 in slot con scansioni = 0 | `id_contatto` univoco; e-mail valida | Mantenere tutti; contatti unici = 1.688 | V / D | Un contatto implica una scansione? |
| A-S08 | **9 contatti con `consenso_marketing` vuoto** e e-mail presente | Consenso ∈ {SI, NO} | Trattare come **NO**; non esporre l'e-mail agli espositori | Q | Il valore vuoto significa consenso non registrato? |
| A-S09 | **14 contatti con fascia 14-17**, e-mail presente e consenso "SI" (13 espositori) | — | **Dato di minori**: nessuna esposizione di e-mail/dettagli nel portale; solo conteggi aggregati | Q | Verifica legale sulla validità del consenso marketing dei minorenni (14-17) |

### Relazioni con il commerciale

| ID | Problema | Trattamento proposto | Classe |
|---|---|---|---|
| A-R01 | Contratti 2024: `id_espositore` e `partita_iva` nulli (88/88) | Vedi **A-C02** (§10): riconciliazione 88/88 per nome | C / D (con il team BAD) |
| A-R02 | Planimetria: 130 stand (115 attivi dal 2024, 15 dal 2025), 4.677 m² totali; 2025: 110 contratti | Usare `attivo_dal` per escludere dal 2024 gli stand non ancora esistenti | V |

---

## 7. Cosa i dati NON permettono di calcolare con certezza

1. **Presenza contemporanea e picco di presenza** — mancano le uscite. Si possono calcolare solo ingressi cumulati per ora/varco/padiglione. Proposta: presentare "ingressi per fascia oraria", etichettando la presenza stimata come tale (per esempio ingressi − uscite stimate da una permanenza media concordata) oppure non mostrarla.
2. **Visitatori unici** — esistono tre misure distinte: biglietti venduti (35.719 / 42.556 righe), persone vendute (somma `Persone`: 42.979 / 51.259), biglietti distinti entrati (34.447 / 41.041), ingressi (biglietto, giorno) unici (39.438 / 47.098) e persone-giorno (46.425 / 55.498). Il cliente usa "biglietti" e "presenze": vanno definite per iscritto prima dei KPI.
3. **Conversione biglietti → ingressi** — calcolabile (≈96,4% dei biglietti ha almeno una lettura OK), ma dipende dalla definizione di ingresso.
4. **Costo per contatto** — i contatti esistono solo per il 2025 e non è fornito alcun costo; serve la definizione di contatto e i costi da includere.
5. **Visite stand 2024** — assenti.

---

## 8. Prossimi passi

1. Condividere con il BAD le anomalie **A-R01** (identificativi espositore 2024), il formato eventi scanner e la definizione di contatto.
2. Portare al cliente le domande **D** più impattanti: A-T03 (regola delle doppie letture / "presenze"), A-T05 (orario acquisto Cassa), A-T07 (uscite), A-S01 (912 scansioni), A-S09 (consenso minori).
3. Con le regole approvate, procedere alla BID-02 (modello dati) e BID-03 (importazione): le tabelle di decodifica (tipi biglietto, varchi, province) e la tabella `anomalie_importazione` discendono direttamente da questo registro.

**File commerciale:** profilato nella seconda task (§10); relazioni complete in §11.

## 9. Riproducibilità

Script in `script/` (Python 3, `pandas`, `openpyxl`; eseguire con `python3 -I`). I percorsi dei file sono quelli del workspace e vanno adattati. `verify_independent.py` ricalcola i numeri chiave con la sola libreria standard.

---

# Parte 2 — File commerciale, relazioni tra file, convenzioni

## 10. File commerciale (`ARCADE_Commerciale.xlsx`)

Sei fogli: `LEGGIMI`, `Espositori` (135), `Planimetria` (130 stand), `Listino_2026` (20 voci), `Contratti` (198: 88 nel 2024, 110 nel 2025), `Righe_contratto` (950).

**Controlli superati**
- Espositori: `id_espositore` univoco (`ESP###`), P.IVA di 11 cifre univoca, e-mail valide e univoche, nessuna ragione sociale duplicata.
- Planimetria: `codice_stand` univoco, il prefisso coincide sempre con il padiglione, `mq` interi tra 4 e 144; 4.677 m² totali (P1 2.378, P2 1.860, P3 439); 115 stand esistono dal 2024 e 15 dal 2025.
- Contratti: `id_contratto` univoco e coerente con l'edizione; nessun contratto su stand non attivo nell'edizione; nessuno stand venduto due volte nella stessa edizione; `imponibile_eur = imponibile_listino × (1 − sconto)` in 198/198 contratti.
- Righe: chiave (`id_contratto`, `riga`) univoca; nessun contratto senza righe e nessuna riga orfana; `importo = quantità × prezzo` sempre; **la somma delle righe coincide con `imponibile_listino_eur` in 198/198 contratti**; la riga `SPAZIO` ha sempre quantità = m² della planimetria; le maggiorazioni (10% angolo, 15% penisola, 25% isola) sono presenti su tutti gli stand contrattualizzati di quel tipo.
- Totali: imponibile 2024 = **706.310,35 €**, 2025 = **821.730,60 €**, in linea con "706k / 822k da espositori e sponsor" del brief. Ricalcolati con una lettura indipendente (openpyxl).

**Dati di profilazione utili ai KPI (non sono KPI approvati):** superficie contrattualizzata / disponibile 2024 = 3.028 / 4.580 m² (66,1%), 2025 = 3.313 / 4.677 m² (70,8%); stand venduti 88/115 e 110/130.

### Registro anomalie — commerciale

| ID | Problema (evidenza) | Regola di validazione | Trattamento proposto | Classe | Da chiarire |
|---|---|---|---|---|---|
| A-C01 | `partita_iva` letta come numero perde lo zero iniziale (es. ESP003: `01965569816` → `1965569816`) | P.IVA = stringa di 11 cifre | Importare sempre come testo; verificare lunghezza 11. I controlli di checksum non sono applicabili (solo 16/135 valide: dati fittizi) | C | — |
| A-C02 | **Contratti 2024 senza `id_espositore` e `partita_iva` (88/88)**; il nome compare con varianti: 25 in maiuscolo, forme legali diverse dall'anagrafica (es. "Prisma Collectibles" vs "… S.r.l."), 9 con punto finale e plurale errato (es. "Bussola Gears." vs "Bussola Gear S.r.l.s.") | Nome normalizzato (minuscolo, senza forma legale e punteggiatura) = nome in anagrafica | Derivare `id_espositore`: 79 esatti + 9 con regola "s" finale (corrispondenza sempre unica, nessuna collisione; es. "Tundra Distribuziones." → ESP055, confermato dallo stesso stand P1-C14 nel rinnovo 2025). Tabella completa in `allegati/mapping_espositori_2024.csv`. Registrare l'origine `derivato` e conservare il nome originale | C / D | Conferma del BAD; il 2025 ha già gli ID |
| A-C03 | Pagamenti: 16 contratti hanno **un solo pagamento registrato**. 8 senza acconto ma con saldo pagato (1 nel 2024, 7 nel 2025) e 8 senza saldo (3 e 5) | Date pagamento nulle = "non registrato" ≠ "non dovuto" | Conservare i NULL; non dedurre stato di pagamento | D | Nullo = non pagato o non registrato? Rilevante per "incassi effettivi" (saldi mancanti: 23.544 € nel 2024, 31.007 € nel 2025) |
| A-C04 | Ordine delle date incoerente: 2 contratti con saldo pagato **prima** dell'acconto (C2024-0078, C2025-0116); 1 con `saldo_scadenza` (19/11/2025) precedente a `acconto_scadenza` (21/11/2025) (C2025-0120, firmato il 06/11) | acconto ≤ saldo (date pagamento e scadenze) | Segnalare e conservare | Q | Errore di registrazione o saldo versato in anticipo? |
| A-C05 | Scadenze: acconto sempre = firma + 15 giorni (198/198); saldo fisso per edizione, 30 giorni prima dell'apertura (20/11/2024, 19/11/2025). Il Listino 2026 prevede "acconto 30% alla firma" ma **non esistono importi di acconto/saldo**, solo date | — | Non derivare gli importi dovuti dalle percentuali | D | Regola acconto in vigore nel 2024/2025 e se la % va memorizzata |
| A-C06 | Il saldo risulta pagato dopo l'apertura fiera in 11 (2024) e 14 (2025) contratti; il ritardo mediano su acconto è 5 giorni e su saldo 3 | — | Valido, informativo | V | — |
| A-C07 | Codifica voci non allineata: i contratti usano un unico `MAGG` (descrizione "Maggiorazione angolo/penisola/isola"), il listino ha `MAGG-ANGOLO/-PENISOLA/-ISOLA`; `Listino_2026` mescola in un foglio unità diverse (€/m², % come frazione 0,10, pacchetti, "cad.", condizioni `COND-*`) e `disponibilita` con testo ("da planimetria") e numeri | — | Tabella di decodifica voci; il tipo di maggiorazione si ricava dalla posizione dello stand (verificato) | C | — |
| A-C08 | **Nel file esistono prezzi solo per il 2026**; i prezzi 2024/2025 si leggono dalle righe contratto (spazio P1/P2/P3: 165/150/110 nel 2024, 180/160/120 nel 2025, 190/170/125 nel 2026; sponsor 2024 = 90% del 2025; sponsor 2025 = listino 2026) | — | Salvare il listino per edizione dai dati delle righe | D | Conferma dei listini storici |
| A-C09 | Lo sconto (0–20%, passi del 5%) è applicato all'**intero** imponibile, sponsor ed extra inclusi; nessun motivo registrato | — | Importare sconto e imponibile così come sono | D | Definire la base del KPI ricavo/m² (area, area + extra, includendo sponsor?) |
| A-C10 | Le sponsorizzazioni (15 righe nel 2024, 17 nel 2025; 121.500 € e 141.000 € a listino) sono righe di contratti di stand, **non collegate a una superficie** | — | Tenerle come componente di ricavo distinta | D | Se includerle nel ricavo per m² |
| A-C11 | Il file contiene solo contratti 2024 e 2025: **nessun contratto 2026, nessun preventivo, nessuno stato** | — | Il flusso 2026 arriva dal BAD (SAL 2) | D (BAD) | Stati e identificativi del preventivo |
| A-C12 | Planimetria con `mq` fissi e solo `attivo_dal`: non risulta alcuna modifica di superficie tra edizioni | — | Assumere superficie costante per edizione | D | Conferma |

## 11. Matrice delle relazioni tra file

| Relazione | Chiave | Esito |
|---|---|---|
| Tornelli → biglietteria | codice biglietto | 100% dei passaggi OK riconciliati; 35 codici/anno sconosciuti, tutti KO (A-T02) |
| Tornelli → biglietto: giorno di validità | codice + data | 0 eccezioni sui giornalieri; abbonamenti usati 1–3 giorni |
| Tornelli → biglietto: tempo | `Data acquisto` ≤ lettura | **13% violato**, quasi solo Cassa (A-T05) |
| Visite stand → planimetria | `codice_stand` | 100% |
| Visite stand → contratti 2025 | `codice_stand` | 0 visite su stand senza contratto; 84 stand su 110 hanno visite (A-S04) |
| Contatti → stand → espositore | `codice_stand`, `id_espositore` | 100% coerenti con il contratto 2025 |
| Contratti 2025 → anagrafica | `id_espositore` | 100%; nome e P.IVA identici |
| Contratti 2024 → anagrafica | nome | derivabile 88/88 (A-C02) |
| Contratti → planimetria | `codice_stand` | 100%; nessuno stand non attivo |
| Righe → contratti | `id_contratto` | 100%; somma righe = imponibile listino 198/198 |
| Flag `rinnovo` 2025 ↔ contratto 2024 | espositore | **Coerente 110/110** (70 rinnovi con contratto 2024, 40 nuovi senza); 69 su 70 rinnovano lo stesso stand (ESP067: da P3-A10 a P3-A08) |
| Turnover stand | stand 2024 ∩ 2025 | 87 dei 88 stand 2024 venduti anche nel 2025; 18 hanno cambiato espositore |
| Espositori anagrafica ↔ contratti | `id_espositore` | 135 in anagrafica: 110 con contratto 2025; dei 25 rimanenti, 18 erano espositori 2024 **non rinnovati** e 7 non hanno mai avuto contratto (in trattativa) |
| Biglietteria 2024/2025 ↔ stand/contratti | — | Nessuna relazione diretta (i biglietti non indicano lo stand): le visite agli stand non sono collegabili ai singoli visitatori |

**Collegamenti che non esistono nei dati:** visitatore ↔ stand (le scansioni sono conteggi orari), biglietto ↔ contatto (nessun identificativo comune: solo e-mail nel contatto), uscite dai varchi.

## 12. Convenzioni proposte (SHARED) — da concordare con il BAD

Proposte, non approvate. Nei file attuali i formati divergono; questa tabella indica il formato canonico da adottare nel modello condiviso.

| Elemento | Formato proposto | Origine |
|---|---|---|
| Edizione | intero (anno): 2024, 2025, 2026 | `edizione` nei contratti |
| Espositore | `ESP###` (testo) | anagrafica |
| Stand | `P{1-3}-{A-C}{nn}` (testo) | planimetria; coincide in visite, contatti, contratti |
| Contratto | `C{aaaa}-{nnnn}` | contratti |
| Biglietto / ordine | `T{aa}######` / `O{aa}######` | biglietteria; il prefisso a 2 cifre codifica l'edizione |
| Date e ore | ISO 8601; timestamp con fuso Europe/Rome (UTC memorizzato) | oggi 4 formati diversi |
| Importi | decimale con punto, EUR; percentuali come frazione (0,15) | biglietteria usa la virgola, Excel la frazione |
| Varco | `P{n}-{Nord|Sud|Ovest|Est}` | tornelli 2025 |
| Esito lettura | booleano `accettata` | `1/0` e `OK/KO` |
| P.IVA | testo, 11 cifre | Excel |

## 13. Riepilogo task 2 e punti da decidere

- **Il file commerciale è strutturalmente solido**: chiavi univoche, relazioni integre e importi riconciliati al centesimo con le righe. Le criticità sono di identificazione (2024), di pagamenti e di definizioni.
- **Prima di BID-02:** concordare con il BAD (a) la derivazione di `id_espositore` 2024 (A-C02), (b) il significato dei pagamenti nulli (A-C03), (c) la base di ricavo per i KPI (A-C09/A-C10) e (d) stati e identificativi del preventivo/contratto 2026 (A-C11).
- **Ancora da fare in BID-01:** nessuna verifica su dati reali del flusso 2026 (non esiste ancora) e nessuna verifica dei file BAD dello scanner (formato eventi da concordare).

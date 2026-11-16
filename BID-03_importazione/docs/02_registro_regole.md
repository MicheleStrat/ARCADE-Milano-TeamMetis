# BID-03 · Registro delle regole di qualità implementate

> Stato: **proposte BID**. "Implementata" = presente nella pipeline e coperta da test; **non** significa approvata dal cliente o dal BAD.
> Esiti: **CORRETTO** (caricato dopo correzione deterministica) · **SEGNALATO** (caricato, informativo) · **QUARANTENA** (non caricato, in attesa di decisione) · **SCARTATO** (non interpretabile, record grezzo conservato).
> I codici R-B/R-T/R-S/R-C1–5 sono quelli di BID-01 (doc. 04); gli altri sono introdotti in BID-03.

## 1. Regole di BID-01 implementate
| Regola | Fonte | Trattamento | Esito | Sul dato reale |
|---|---|---|---|---|
| R-B01 | biglietteria | Etichetta tipo → codice canonico (per edizione); etichetta sconosciuta | CORRETTO / QUARANTENA | tutte decodificate |
| R-B02 | biglietteria | "3 giorni" → `giorno_valido` NULL (abbonamento) | CORRETTO | 5.602 / 6.815 |
| R-B03 | biglietteria, contatti | Provincia estesa → sigla; vuota → NULL; non riconosciuta | CORRETTO / SEGNALATO / QUARANTENA | 13.383 / 16.133 corrette; 2.158 / 2.525 vuote |
| R-B04 | biglietteria | Fascia vuota → NULL; fuori elenco | SEGNALATO / QUARANTENA | 1.382 / 1.719 vuote |
| R-B05 | biglietteria | Prezzo con virgola → decimale; non numerico o negativo | QUARANTENA | 0 |
| R-B06 | biglietteria | Fasce 0-17: minorenne, mai esposto (solo conteggio) | SEGNALATO | 13.115 / 15.384 |
| R-T01 | tornelli | Orario locale/UTC → UTC; varco canonico; varco sconosciuto | QUARANTENA | 0 |
| R-T02 | tornelli | Codice assente in biglietteria: se KO conservato come respinto; se OK non caricato | SEGNALATO / QUARANTENA | 35 / 35 respinte; 0 OK |
| R-T03 | tornelli | KO su biglietto noto conservato, non conteggiato | SEGNALATO | 195 / 221 |
| R-S01 | visite | Ora fuori da 09:00–18:00 | QUARANTENA | 1 riga (912 scansioni, 08:00) |
| R-S02 | visite | Slot mancante: **non imputato** | — (assenza di riga) | 70 slot |
| R-S04 | contatti | Consenso vuoto → NO + `consenso_non_registrato` | CORRETTO | 9 |
| R-S05 | contatti | Minorenni: e-mail mai esposta | SEGNALATO | 14 |
| R-C01 | commerciale | ID espositore 2024 derivato dal nome (identico normalizzato, poi regola della 's' finale se univoca); altrimenti | CORRETTO / QUARANTENA | 88 derivati, 0 irrisolti |
| R-C02 | commerciale | P.IVA testo 11 cifre; con **10 cifre** si ripristina lo zero iniziale; altre lunghezze | CORRETTO / QUARANTENA | 0 (già testo) |
| R-C03 | commerciale | Date di pagamento vuote → NULL, nessuno stato dedotto | SEGNALATO | 16 contratti |
| R-C04 | commerciale | Scadenze/pagamenti in ordine incoerente: caricato e segnalato | SEGNALATO | 3 contratti |
| R-C05 | commerciale | `SPAZIO`/`MAGG` → codice canonico per padiglione/posizione (originale in `codice_voce_origine`); prezzo listino non numerico → NULL | CORRETTO / SEGNALATO | 272 righe; 1 voce di listino |
Non calcolate qui ma nella vista `v_lettura_valutata` (BID-02): **R-T04** (doppie letture ≤ 60 s) e **R-T05** (lettura prima dell'acquisto), perché la loro definizione non è approvata.

## 2. Controlli introdotti in BID-03 (non presenti in BID-01)
| Regola | Controllo | Esito |
|---|---|---|
| R-F01 | Identificativo con formato errato o di un'altra edizione (es. `T25…` in un file 2024); codice biglietto malformato | SCARTATO |
| R-F02 | Data/ora non interpretabile (es. 31/02, ora 99) | SCARTATO |
| R-F03 | Numero non valido (persone ≤ 0, scansioni negative o testuali, importo non numerico) | SCARTATO (QUARANTENA per `rinnovo`) |
| R-F04 | ID ripetuto nel file: riga identica → SCARTATO (tracciata); stesso ID con valori diversi → QUARANTENA | SCARTATO / QUARANTENA |
| R-F05 | Riga con numero di campi errato (record grezzo conservato) | SCARTATO |
| R-F06 | Esito del tornello non interpretabile | SCARTATO |
| R-B08 | Incoerenza tipo / giorno valido / giorni dell'edizione (abbonamento con giorno, giornaliero senza giorno, giorno fuori edizione) | QUARANTENA |
| R-B09 | Biglietti dello stesso ordine con data o canale diversi | QUARANTENA |
| R-B10 | Canale di vendita non previsto | QUARANTENA |
| R-T06 | Stessa chiave `(varco, codice, istante)` ripetuta nel file | SCARTATO se identica / QUARANTENA se esito diverso |
| R-T07 | Lettura fuori dai giorni dell'edizione | QUARANTENA |
| R-S07 / R-S08 / R-S09 | Stand inesistente / data fuori edizione / stesso slot con valori diversi | QUARANTENA (R-S09 identica: SCARTATO) |
| R-S10 | Contatto senza contratto dell'espositore su quello stand nell'edizione | QUARANTENA |
| R-S11 / R-S12 | E-mail non valida / fascia non ammessa (inclusa "famiglia") | QUARANTENA |
| R-C06 / R-C08 | ID espositore inesistente / P.IVA già usata da un altro espositore | QUARANTENA |
| R-C07 | Voce non a catalogo o maggiorazione non applicabile alla posizione dello stand | QUARANTENA |
| R-C09 | Stand, padiglione, superficie, posizione o edizione non validi; stand non ancora esistente | QUARANTENA |
| R-C11 | P.IVA del contratto diversa da quella dell'anagrafica | SEGNALATO |
| R-C12 / R-C13 | Imponibile ≠ listino × (1 − sconto) / scadenza acconto precedente alla firma | QUARANTENA |
| R-C15 / R-C16 / R-C17 | Stand già venduto nell'edizione / riga di contratto non caricato / importo ≠ quantità × prezzo | QUARANTENA |
| R-X02 | Chiave già presente con valori diversi: **non** aggiornata | SEGNALATO |
Tutti i controlli R-B08…R-C17 sono stati **verificati sui dati reali: nessun record li ha attivati** (0 quarantene tranne R-S01) e si attivano nei test con dati costruiti apposta.

## 3. Differenza rispetto alla profilazione BID-01
- **Contatti di minorenni (A-S09)**: BID-01 li classificava come quarantena; il modello BID-02 e questa pipeline li **caricano** marcati `minorenne` e non esposti (SEGNALATO R-S05). Da confermare.
- Il record in quarantena di `importazione_anomalia` ha ora la forma `{"motivo": …, "record": {…}}` (prima: campi piatti).

## 4. Punti da concordare (nuovi)
| # | Domanda | Proposta BID |
|---|---|---|
| C13 | Come si aggiornano dati già caricati (es. prezzo corretto dal BAD)? | Oggi: mai sovrascrivere, solo segnalare (R-X02). Da concordare un campo `versione`/data di modifica o un upsert esplicito per le entità commerciali |
| C14 | Un contatto di un minorenne deve entrare nel database? | Sì, solo come dato non esposto (R-S05); alternativa: quarantena |
| C15 | Orario di apertura per le visite agli stand | 09:00–18:00 (parametro in `rules.py`); il cliente deve confermarlo |
| C16 | Decodifica delle etichette del tipo biglietto per edizioni future (2026) | Aggiungere la tabella in `rules.ETICHETTE_TIPO` e `tipo_biglietto_etichetta` al momento del rilascio delle etichette |
| C17 | Formato degli eventi degli scanner (BAD) | Da definire in SHARED-02; proposta: stessi campi di `visite_stand` con id evento |

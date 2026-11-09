# BID-01 · Task 5 — Anomalie sui dati commerciali da concordare con il team BAD

> Task: *Concordare con il team BAD le anomalie che riguardano i dati commerciali.*
> **Stato: nessun accordo ancora preso.** Questo documento prepara il confronto: elenca i punti, la proposta del BID e la decisione che serve. Le risposte del BAD vanno registrate nella colonna "Decisione" quando arrivano; fino ad allora le proposte non vanno trattate come approvate.
> Allegati: `allegati/mapping_espositori_2024.csv` · `allegati/contratti_pagamenti_da_verificare.csv`
> Scadenza utile: **SAL 1, 30 ottobre 2026** (schema dati e contratto d'integrazione congelati).

## 1. Che cosa serve concordare (in ordine di urgenza)

| # | Tema | Perché è bloccante | Chi decide |
|---|---|---|---|
| 1 | Identificativo espositore nei contratti 2024 | senza ID non si confrontano le edizioni per espositore | BAD (+ BID) |
| 2 | Pagamenti non registrati e date incoerenti | "incassi effettivi" e ricavo reale | BAD / cliente |
| 3 | Base di calcolo del ricavo e della saturazione | KPI C e B non calcolabili senza | BAD + BID + cliente |
| 4 | Entità e stati del flusso commerciale 2026 | serve per il contratto API e per SAL 2 | BAD + BID |
| 5 | Convenzioni di identificativi e formati | modello dati condiviso | BAD + BID |
| 6 | Listino storico e codici voce | prezzi 2024/2025 presenti solo nelle righe | BAD |
| 7 | Formato degli eventi dell'app di scansione | acquisizione visite e contatti | BAD + BID |
| 8 | Protezione dei minori nei dati condivisi | vincolo obbligatorio del brief | BAD + BID |

---

## 2. Dettaglio dei punti

### 2.1 Identificativo espositore nei contratti 2024 (A-C02)
- **Evidenza:** `id_espositore` e `partita_iva` sono nulli in tutti gli 88 contratti 2024; nel 2025 sono sempre valorizzati. Il nome è scritto con varianti (25 in maiuscolo; 9 con punto finale e plurale errato, es. "Bussola Gears." per "Bussola Gear S.r.l.s.").
- **Proposta del BID:** derivare l'ID dal nome con una regola riproducibile (nome identico dopo normalizzazione; altrimenti regola "s" finale con corrispondenza unica). Risultato: **88/88 riconciliati, nessun duplicato** (79 identici + 9 con regola). Il flag `rinnovo` 2025 è coerente con questa derivazione in 110/110 contratti, e il rinnovo dello stesso stand la conferma (es. "Tundra Distribuziones." → ESP055, stesso stand P1-C14).
- **Da confermare dal BAD:** le 9 righe con `da_confermare = True` nell'allegato; chi corregge la fonte (idealmente il BAD valorizza `id_espositore` 2024 nel back-office, così la derivazione non serve).
- **Decisione:** ☐ accettata ☐ modificata ☐ rifiutata — *…*

### 2.2 Pagamenti non registrati e date incoerenti (A-C03, A-C04, A-C05)
- **Evidenza:** 16 contratti hanno un solo pagamento registrato (8 senza acconto, 8 senza saldo); 3 hanno date in ordine incoerente. Elenco completo (19 contratti) nell'allegato. I saldi mancanti valgono 23.544 € (2024) e 31.007 € (2025) di imponibile. Non sono memorizzati gli importi di acconto e saldo, solo le date; il listino 2026 prevede acconto 30% alla firma, mentre nei dati l'acconto scade sempre 15 giorni dopo la firma.
- **Domande:**
  1. Una data di pagamento vuota significa "non pagato" o "non registrato"?
  2. Le 3 incoerenze sono errori di registrazione?
  3. Gli importi di acconto e saldo vanno memorizzati nel modello condiviso (e con quale regola)?
- **Proposta del BID:** conservare i NULL senza dedurre uno stato; creare `stato_pagamento` solo dopo la risposta del BAD.
- **Decisione:** ☐ … — *…*

### 2.3 Base di calcolo di ricavo e saturazione (A-C09, A-C10, A-C12 e KPI B/C)
- **Evidenza:** lo sconto (0–20%) si applica all'intero imponibile, sponsor ed extra inclusi. Le sponsorizzazioni (15 righe nel 2024, 17 nel 2025; 121.500 € e 141.000 € a listino) sono dentro i contratti di stand ma non legate a una superficie. Superfici: 4.580 m² disponibili nel 2024, 4.677 nel 2025; contrattualizzati 3.028 e 3.313 m² (66,1% e 70,8%). La planimetria non indica stand riservati o non vendibili.
- **Opzioni per il ricavo per m² (da scegliere):**

| Opzione | Numeratore | Denominatore | Pro | Contro |
|---|---|---|---|---|
| A | solo area + maggiorazioni (al netto sconto) | m² venduti | misura la resa dello spazio | ignora extra e sponsor |
| B | imponibile del contratto **senza sponsor** | m² venduti | include gli extra legati allo stand | ricavo non puramente "area" |
| C | imponibile totale, sponsor inclusi | m² venduti | coincide con 706k / 822k del brief | sponsor non legati a una superficie gonfiano il rapporto |

  Il BID propone la **B** come indicatore principale e la C come riferimento al totale del brief, ma è una proposta. Va deciso se usare importi contrattualizzati o incassi effettivi (dipende da 2.2).
- **Domande:** esistono stand non vendibili o riservati? La superficie è costante tra le edizioni?
- **Decisione:** ☐ … — *…*

### 2.4 Entità e stati del flusso commerciale 2026 (A-C11)
- **Evidenza:** il file contiene solo contratti 2024/2025: non ci sono preventivi, stati né contratti 2026. Per SAL 2 (13 novembre) serve un contratto 2026 venduto.
- **Proposta minima del BID (da discutere, non imposta):** il BAD fornisce per ogni contratto `id_contratto`, `edizione`, `id_espositore`, `codice_stand`, `data_firma`, `imponibile_listino_eur`, `sconto_pct`, `imponibile_eur`, scadenze e pagamenti, righe contratto; il BID espone un endpoint (o un file) con aggiornamento idempotente per `id_contratto`. Preventivo e stato (bozza/firmato/annullato) sono domande aperte: **il BID non li ha trovati nei dati e non li inventa**.
- **Domande:** come sono identificati preventivo e contratto? Quali stati esistono? Come si aggiorna la disponibilità dello stand?
- **Decisione:** ☐ … — *…*

### 2.5 Convenzioni di identificativi e formati (SHARED)
- **Proposta:** edizione = anno intero; `ESP###`; stand `P{1-3}-{A-C}{nn}`; contratto `C{aaaa}-{nnnn}`; biglietto `T{aa}######`; date ISO 8601, timestamp con fuso Europe/Rome; importi con punto decimale in EUR; percentuali come frazione; P.IVA testo di 11 cifre. Dettaglio nel report (§12).
- **Decisione:** ☐ … — *…*

### 2.6 Listino storico e codici voce (A-C07, A-C08)
- **Evidenza:** il listino contiene solo il 2026. I prezzi 2024/2025 si leggono dalle righe contratto: area P1/P2/P3 = 165/150/110 € (2024), 180/160/120 € (2025), 190/170/125 € (2026); sponsor 2024 = 90% del 2025; sponsor 2025 = listino 2026. Il contratto usa `MAGG`; il listino ha `MAGG-ANGOLO/-PENISOLA/-ISOLA`.
- **Proposta:** salvare il listino per edizione ricavandolo dalle righe; mappare `MAGG` in base alla posizione dello stand (verificato: 10% / 15% / 25%).
- **Domande:** i prezzi ricavati sono i listini ufficiali? Le maggiorazioni sono sempre calcolate sulla sola area?
- **Decisione:** ☐ … — *…*

### 2.7 Formato degli eventi dell'app di scansione
- **Evidenza:** i dati 2025 sono già aggregati per ora (stand, ora, scansioni) e i contatti hanno `id_contatto`, `timestamp`, e-mail, età, provincia, consenso e interesse. Non esiste legame tra una scansione e un visitatore o un contatto. 26 stand con contratto non hanno alcuna visita.
- **Proposta del BID:** per l'app BAD, un evento per scansione con `id_evento` univoco (per rendere idempotente l'importazione), `codice_stand`, `timestamp` con fuso e, se concordato, un riferimento al biglietto. Va deciso cosa è un "contatto valido" e se un visitatore unico si identifica dal biglietto.
- **Domande:** quali stand avevano lo scanner? Una scansione genera sempre un contatto?
- **Decisione:** ☐ … — *…*

### 2.8 Protezione dei minori nei dati condivisi (A-S09, A-B06)
- **Evidenza:** 14 contatti 14-17 anni hanno e-mail e consenso "SI"; circa il 36% dei biglietti è di fasce 0-17.
- **Proposta:** nessuna e-mail né dato individuale di minori esposti nel portale espositori né nei report Power BI; solo aggregati. Il consenso vuoto vale NO. Da verificare con il legale la validità del consenso dei 14-17.
- **Decisione:** ☐ … — *…*

---

## 3. Questioni solo del cliente (non del BAD)

Da portare al cliente, perché non dipendono dal commerciale: regola delle doppie letture e definizione di "presenze" (il numero del brief torna scartando anche le letture ravvicinate dei Family: vedi documento 04, §6), orario di acquisto alla Cassa, esistenza di dati di uscita, le 912 scansioni delle 08:00, visite 2024, motivo dei KO ai tornelli.

## 4. Come registrare l'esito

Per ogni punto: data, persone coinvolte, decisione e impatto sul modello dati. Le decisioni prese prima di SAL 1 vanno riportate nel contratto d'integrazione; quelle successive al congelamento richiedono la motivazione e il coordinamento dei due team.

| # | Data | Presenti | Decisione | Impatto |
|---|---|---|---|---|
| | | | | |

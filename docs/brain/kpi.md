# KPI — definizioni e regole di calcolo (SHARED-01)

> Collegamenti: [[00-indice]] · [[contesto-BAD]] · [[contesto-BID]] · [[decisioni-condivise]] · [[anomalie-dati]] · [[modello-dati]]

Aggiornato: 11 novembre 2026. Proposta BAD del 4/11 (issue #41–#45, SHARED-01-01 … 01-05), allineata alle decisioni BAD fino a B-38.
**Stato: posizioni del BAD, ancora da approvare col BID (A-10)** e poi col cliente (D10: chi approva le formule). Una definizione diventa ufficiale solo quando è registrata in [[decisioni-condivise]] con l'ok di BAD e BID.

Le formule esistono già nelle viste `analytics` del BID (V4): qui sono scritte in italiano, con quello che va deciso e quello che resta un'assunzione. Power BI non ricalcola niente: le misure DAX aggregano le colonne delle viste.

Legenda: **[DA DECIDERE]** = scelta del team · **[CLIENTE]** = serve la risposta del cliente.

---

## SHARED-01-01 — Visitatori e picco di presenza (#41)

Nei dati non c'è un identificativo di persona e i tornelli registrano solo ingressi. "Visitatori" può quindi voler dire numeri diversi, che **non si sommano** tra loro.

| Misura | Cosa conta | Colonna (`kpi_visitors_edition`) | Certezza |
|---|---|---|---|
| Biglietti venduti | righe di biglietteria (un Family = 1) | `tickets_sold` | certo |
| Persone vendute | somma del campo Persone (un Family = 4) | `persons_sold` | certo |
| Biglietti validati | biglietti distinti con almeno un passaggio OK | `tickets_validated` | certo |
| Ingressi-giorno | biglietti distinti entrati, per giorno (un abbonamento 3 giorni vale fino a 3) | `unique_daily_entries` | certo |
| Passaggi ai varchi | tutte le letture (rientri, più padiglioni, KO, orfani) | `passes_total` | certo, ma non sono persone |
| Visitatori unici (persone) | — | — | **non calcolabile** |

Conversione biglietti → ingressi = `tickets_validated / tickets_sold` (`validation_rate_pct`). Risponde a "quanti biglietti venduti diventano ingressi?".

**Proposta (B-12)**: il numero mostrato come "Visitatori" è **biglietti validati**, con sotto le **persone vendute** come contesto e la nota "biglietti, non persone: un Family copre 4 persone". Nessuna colonna nuova nelle viste.

**Picco di presenza (B-13)**
- Metodo `presence_estimate()`: un biglietto è "presente" in un padiglione se ha una lettura OK a un varco di quel padiglione negli ultimi **90 minuti**; calcolo ogni **15 minuti**; il picco è il massimo del giorno (`kpi_presence_peak`).
- Per padiglione e per l'evento intero (riga senza padiglione = biglietti distinti su tutto l'evento). **I padiglioni non si sommano**.
- Conta biglietti, non persone. È sempre una **STIMA** (`is_estimate = true`) e va etichettata così ovunque.
- **[CLIENTE]** D1/Q-02: varchi = ingressi ai padiglioni? Esistono uscite? Permanenza media? Finché non risponde, 90′ e 15′ restano ipotesi dichiarate.

---

## SHARED-01-02 — Saturazione e ricavo per m² (#42)

**Saturazione = m² venduti / m² commercializzabili × 100** (`kpi_saturation.saturation_pct`), per edizione e per padiglione.
- *Venduto*: stand assegnato a un contratto **firmato** (SIGNED) e attivo.
- *Commercializzabile*: tutti gli stand tranne `NOT_SELLABLE`.
- **Riservati** (RESERVED): non venduti, mostrati a parte (`sqm_reserved`).
- **Gratuiti** (FREE): fuori dalla saturazione, dentro l'**occupazione** (`occupancy_pct` = venduti + gratuiti).
- Si misura in m², non in numero di stand.
- **[CLIENTE]** D13: come trattare riservati e gratuiti. Proposta: come sopra.

**Ricavo/m² = (spazio + maggiorazioni) netto sconto, IVA esclusa / m² venduti** (`revenue_per_sqm`; per padiglione `kpi_space_revenue_pavilion`).
- Maggiorazioni incluse (sono prezzo dello spazio); extra e sponsorizzazioni **esclusi** e mostrati a parte.
- Sconto ripartito pro-quota sulle righe: la somma torna esatta.
- **Contrattualizzato ≠ incassato** (`contracted_net`, `cash_collected`): due misure separate.
- Nei totali il ricavo/m² **non si somma e non si fa la media** tra padiglioni: si ricalcola sui totali (DAX: `DIVIDE(SUM(numeratore), SUM(m²))`).
- **[CLIENTE]** D4–D6 (Q-04…Q-06): importi pagati, IVA, listini storici. Finché non rispondono: IVA esclusa, incassato = dovuto marcato "assunto".

Risponde a "quali padiglioni rendono di più?".

---

## SHARED-01-03 — Costo per contatto (#43)

- **Visita** = scansione allo stand (file 2025 aggregato per stand × giorno × ora): non identifica la persona.
- **Contatto** = una riga dei contatti stand 2025 (1.707): è un lead, non una visita. **Visite ≠ contatti**, non si sommano.
- Contatti caricati il 8/11 (B-34): email solo come hash; **consenso vuoto = nessun consenso**; i **14 contatti di 14-17 anni** sono nel DB con `PRIVACY_REVIEW` e restano **fuori da KPI e portale** (le viste usano solo `review_status = 'OK'`).

**Definizioni proposte**
- *Contatto raccolto*: riga valida, collegata a uno stand e a un espositore.
- *Contatto qualificato* (da far approvare al cliente, AS-12): consenso = SI **e** interesse indicato, esclusi i contatti in revisione privacy e i doppioni della stessa email sullo stesso stand. Oggi `is_qualified` è sempre `false`.
- *Costo per contatto qualificato* = costo attribuibile / contatti qualificati.

**Il nodo è il costo**: nei dati non esiste.

| Opzione | Costo usato | Pro | Contro |
|---|---|---|---|
| A — non calcolabile (oggi nelle viste) | nessuno | onesto | KPI vuoto, si mostra solo `contract_value_per_visit` |
| B — dal punto di vista dell'espositore | valore netto del suo contratto | calcolabile subito per il 2025, utile nel portale | non è il costo per la fiera |

**Proposta (B-15)**: la scelta si chiede al cliente insieme a D9. Fino alla risposta vale **A**. Contatti e visite esistono solo per il 2025: niente confronto col 2024.

---

## SHARED-01-04 — Regole di conteggio (#44)

**Tempo**
| Regola | Valore |
|---|---|
| Fuso dei report | `Europe/Rome`: giorno e ora in ora locale |
| Tornelli 2024 | ora locale senza fuso → convertita in UTC al caricamento |
| Tornelli 2025 | già UTC (suffisso Z) |
| Salvataggio | tutto in `timestamptz` |
| Presenze | finestre di 15′, permanenza 90′ (ipotesi) |
| Visite stand | 1 ora (granularità del file) |
| Giorni dell'evento | quelli dei dati (dicembre) finché il cliente non risponde (D8/Q-01) |

**Tornelli**
- Chiave di una lettura: **varco + codice biglietto + istante UTC**; doppioni identici nello stesso file diventano `#2`, `#3`…; ricaricare lo stesso file non duplica nulla.
- **Ingresso unico** = primo passaggio **OK** del biglietto nel giorno (o nel giorno e padiglione).
- Esiti **KO**: contati nei passaggi, **esclusi** da ingressi, validati e presenze.
- Codici **orfani** (35 + 35, GAT-001): contano nei passaggi e nelle presenze stimate, **non** negli ingressi unici né nei validati.
- Letture fuori orario o prima dell'acquisto (GAT-006): caricate e segnalate, mai cancellate.

**Biglietteria**
- Codice duplicato: respinto e segnalato.
- Biglietto mai passato ai varchi (1.272 nel 2024, 1.515 nel 2025): non è un errore, è la differenza tra venduti e validati.

**Visite agli stand**
- Una cella = **stand × giorno × ora**. Se arrivano eventi singoli, per quella cella vincono gli eventi (una sola sorgente per cella).
- Stand senza visite (26 nel 2025): valore vuoto, non zero.
- Dal 2026 il conteggio delle visite passa dalle **telecamere simulate** (B-25, A-12): solo numeri aggregati, nessuna immagine.
- **Outlier da 912 scansioni** (P1-A02, 19/12/2025, ore 08:00; il massimo altrove è 177, VIS-001). **Proposta (B-14, modificata da B-30)**: escluso dai KPI finché il cliente non risponde (Q-12); resta nel DB ed è spiegato in [[anomalie-dati]] (il report Power BI non ha una pagina qualità dati). Serve che il BID filtri la riga VIS-001 nelle viste delle visite.

**Contatti**
- Email solo come hash, mai in chiaro nel DB.
- Stessa email sullo stesso stand = un contatto solo (LED-001). Verifica dell'8/11: le 19 email ripetute stanno ciascuna su **due stand diversi**, quindi LED-001 vale 0.

---

## SHARED-01-05 — Registro delle assunzioni (#45)

Quando i dati non permettono un calcolo preciso, l'ipotesi si scrive qui, si marca nei dati e si mostra nel report. Un'assunzione chiusa **non si cancella**: si segna come confermata o superata, con la data.

| ID | Assunzione | Perché serve | KPI coinvolti | Come si vede | Si chiude con | Stato |
|---|---|---|---|---|---|---|
| AS-01 | Permanenza media 90′ in un padiglione | i tornelli non registrano uscite | picco di presenza | etichetta "stima" | D1/Q-02 | aperta |
| AS-02 | Ogni varco è solo un ingresso a un padiglione | nomi dei varchi | presenze, ingressi | nota | D1/Q-02 | aperta |
| AS-03 | Tornelli 2024, visite e contatti 2025 in ora di Milano; tornelli 2025 in UTC | formati diversi | tutti quelli orari | nessuna | conferma cliente | aperta |
| AS-04 | Acconto 30 % alla firma, saldo 70 % 30 giorni prima; incassato = dovuto | il file dà solo le date | incassato, % acconti | importi "assunti" | D4/Q-05 | aperta (chiesto al cliente l'11/11, A-18) |
| AS-05 | Importi IVA esclusa | i file parlano di "imponibile" | ricavi, €/m² | "IVA esclusa" | D5/Q-06 | aperta |
| AS-06 | Listini 2024/2025 ricostruiti dalle righe contratto (P3 < P2 < P1) | c'è solo il listino 2026 | ricavi per padiglione | "listino ricostruito" | D6/Q-04 | aperta; verifica 8/11: un solo prezzo per voce e padiglione, nessuna ambiguità |
| AS-07 | `rinnovo = 1` = rinnovo dall'edizione precedente | significato non documentato | tasso di rinnovo | nota | D3/Q-03 | aperta; 70 rinnovi su 70 hanno un contratto 2024 dopo la mappa dei nomi |
| AS-08 | ~~I 9 espositori 2024 non riconciliati restano fuori dai KPI per espositore~~ | — | — | — | — | **superata l'8/11 (B-33)**: 9 nomi confermati, tutti i 198 contratti nei KPI |
| AS-09 | Un biglietto = un visitatore nelle presenze (un Family conta 1) | il tornello legge il biglietto | presenze, validati | "biglietti, non persone" | limite dei dati | definitiva |
| AS-10 | Una scansione allo stand = una visita, non un contatto | file aggregato per ora | visite stand | nota | D11 | aperta |
| AS-11 | Date dell'evento = quelle dei dati (dicembre) | il brief dice "fine novembre" | tutti quelli giornalieri | nessuna | D8/Q-01 | aperta |
| AS-12 | Contatto qualificato = consenso + interesse, esclusi minori e doppioni | il cliente non l'ha definito | costo per contatto | nota | D9/Q-11 | aperta |

---

## KPI aggiuntivo proposto dal BAD — Resa per stand (€/m²)

**Resa dello stand = (spazio + maggiorazioni) netto sconto, IVA esclusa / m² dello stand**, per edizione: la formula di `revenue_per_sqm`, calcolata per singolo stand.
- Dati: `analytics.fact_contract_line` (righe `SPACE` e `SURCHARGE`, `net_amount_allocated`) + `analytics.dim_stand` (`sqm`, padiglione, posizione). Nessuna modifica alle viste.
- In Power BI i m² si prendono **una volta per stand**, non per riga di contratto.
- Dentro lo stesso padiglione il prezzo al m² è unico: la classifica dipende solo da maggiorazioni e sconti. Si legge come "quanto abbiamo ottenuto rispetto al listino".
- Edizioni 2024 e 2025, tutti i contratti (B-33). Il 2024 usa il listino ricostruito (AS-06).
- **[DA DECIDERE con il BID]** misura DAX nel report o vista `kpi_stand_revenue` nel DB.

---

## Da approvare col BID (A-10)

| # | Tema | Posizione BAD | Cosa serve dal BID |
|---|---|---|---|
| 1 | "Visitatori" in testata | biglietti validati, persone vendute come contesto (B-12) | niente: la colonna esiste |
| 2 | Picco di presenza | 90′, ogni 15′, etichetta "stima" (B-13) | niente: sono i default |
| 3 | Costo per contatto | si chiede al cliente; intanto "non calcolabile" (B-15) | niente per ora |
| 4 | Outlier 912 scansioni | escluso dai KPI, spiegato in [[anomalie-dati]] (B-14, B-30) | filtro VIS-001 nelle viste delle visite |
| 5 | Contatti dei minori | `PRIVACY_REVIEW`, fuori da KPI e portale (B-34) | conferma, la loro regola LED-002 diceva quarantena |
| 6 | Referenti SHARED-01 | da nominare | un referente BID |
| 7 | Resa per stand | KPI aggiuntivo | approvazione; DAX o vista |

Quando il BID approva, le righe vanno in [[decisioni-condivise]] e le issue #41–#45 si chiudono (la #43 resta aperta solo per il costo, in attesa di D9).

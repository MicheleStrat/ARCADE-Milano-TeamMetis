# Domande per il cliente (Factory Studios) — kickoff

Versione: 23 ottobre 2026 · da portare al cliente dal team BID + BAD

Come usare questo documento:
- Le domande sono **ordinate per priorità**. Se il tempo è poco, ferma la riunione dopo la fascia P1.
- Per ogni domanda trovi: **cosa chiediamo**, **perché** (con il dato reale che l'ha generata), **cosa faremo se non risponde** (assunzione di lavoro) e **cosa blocca**.
- Lo spazio “Risposta” serve a compilare l'esito in riunione. Le risposte vanno poi riportate nel registro delle decisioni e nello schema.
- Le assunzioni di lavoro sono **nostre ipotesi**, non requisiti del cliente.

## Quadro d'insieme

| Fascia | Quando serve la risposta | Domande | Cosa sblocca |
|---|---|---|---|
| **P1 — bloccanti** | entro il **30/10** (SAL 1: schema e API congelati) | D1–D10 | Struttura del database, contratto API, definizione dei KPI |
| **P2 — necessarie per la demo** | entro il **13/11** (SAL 2) | D11–D18 | Caricamento dati 2024/2025, vendita 2026, dashboard |
| **P3 — da chiudere prima della consegna** | entro il **27/11** | D19–D23 | Rifiniture, privacy finale, demo |
| **Interne al team** (non per il cliente) | subito | T1–T4 | Strumenti Microsoft e hosting |

Corrispondenza con il documento tecnico: D1 = Q-02, D2 = Q-10, D3 = Q-03, D4 = Q-05, D5 = Q-06, D6 = Q-04, D7 = Q-07, D8 = Q-01, D9 = Q-11, D12 = Q-08, D14 = Q-13, D15 = Q-09, D16 = Q-12, D17 = Q-14. Le altre sono nuove.

---

## P1 — Bloccanti (entro il 30 ottobre)

### D1. Tornelli: ingressi, uscite e permanenza (Q-02)
**Cosa chiediamo**
1. Un varco come “P1 Nord” è l'**ingresso a quel padiglione** oppure l'ingresso all'evento? Un visitatore passa un varco ogni volta che cambia padiglione?
2. Esistono **letture di uscita**, anche in un altro sistema?
3. Quanto tempo si ferma, in media, un visitatore in un padiglione?

**Perché**: nei file i varchi sono 4 (P1 Nord, P1 Sud, P2 Ovest, P3 Est), non c'è direzione, e circa un biglietto passato su cinque ha più passaggi (6.709 codici nel 2024, 8.124 nel 2025, fino a 7 passaggi).
**Se non risponde**: ogni varco = ingresso a un padiglione; nessuna uscita; presenze **stimate** con permanenza 90′, sempre etichettate “stima”.
**Blocca**: KPI visitatori e picco di presenza; dashboard operativa.
**Risposta**: ______________________

### D2. Contatti raccolti agli stand: consenso, minori, email (Q-10)
**Cosa chiediamo**
1. Chi ha raccolto il **consenso marketing** (l'espositore o Factory Studios), con quale informativa e per chi vale?
2. Come trattare i **14 contatti di 14-17 anni** con consenso registrato?
3. Il campo consenso è **sempre “SI”** (1.707 su 1.707): è un'impostazione del sistema di raccolta o un dato reale?
4. Per quanto tempo possiamo conservare le email in chiaro nella fase di caricamento? Chi è il **referente privacy**?

**Perché**: il file `contatti_stand_2025.csv` contiene email e consenso. Una visita non è un contatto qualificato, e i dati dei minori richiedono attenzione.
**Se non risponde**: l'email non entra nel database vero (solo un hash); i 14 contatti di minori restano in **revisione privacy** e non compaiono nel portale; nessuna base giuridica è presunta.
**Blocca**: caricamento dei contatti, portale espositori, parte privacy della consegna.
**Risposta**: ______________________

### D3. Significato del campo “rinnovo” (Q-03)
**Cosa chiediamo**: nel foglio Contratti, `rinnovo = 1` significa “contratto rinnovato rispetto all'edizione precedente”? O “intenzione di rinnovare per il 2026”?

**Perché**: nel 2024 è sempre 0; nel 2025 vale 1 in 70 contratti su 110. Per 64 di questi 70 abbiamo trovato un contratto 2024 con lo stesso nome; per **6** no.
**Se non risponde**: lo trattiamo come “rinnovo dell'edizione precedente” e segnaliamo i 6 casi come anomalia.
**Blocca**: tasso di rinnovo, decisioni di prelazione.
**Risposta**: ______________________

### D4. Pagamenti: importi e regola dell'acconto (Q-05)
**Cosa chiediamo**
1. Nei contratti abbiamo solo **scadenze e date di pagamento**, non gli importi. Gli importi effettivamente versati sono disponibili?
2. L'acconto del **30 %** si calcola sull'imponibile **netto sconto**? Il saldo è il resto?
3. Come si trattano pagamenti parziali, ritardi e rimborsi?

**Perché**: 8 acconti e 8 saldi risultano non pagati; 121 acconti e 119 saldi sono pagati dopo la scadenza. Senza importi non possiamo distinguere un acconto dal ricavo e non possiamo calcolare l'“incassato”.
**Se non risponde**: importo dovuto = regola 30/70 sul netto, e il pagato = dovuto, **marcato come assunto** nei dati.
**Blocca**: KPI incassato, flussi di promemoria scadenze.
**Risposta**: ______________________

### D5. IVA e definizione di ricavo (Q-06)
**Cosa chiediamo**
1. Gli importi dei contratti (“imponibile”) sono **IVA esclusa**? Qual è l'aliquota?
2. Per la direzione, il “ricavo” è il **contrattualizzato** o l'**incassato**? (Noi li teniamo separati.)
3. Come si trattano sconti, cancellazioni e rimborsi nel ricavo?

**Perché**: il KPI ricavo per m² dipende da questa scelta. Acconti e valore del contratto non devono essere sommati come se fossero ricavi diversi.
**Se non risponde**: ricavo = contrattualizzato netto sconto, IVA esclusa; incassato come misura a parte.
**Blocca**: KPI economici e Power BI.
**Risposta**: ______________________

### D6. Listini 2024 e 2025 (Q-04)
**Cosa chiediamo**
1. Ci confermate i **listini 2024 e 2025**? Abbiamo solo quello 2026.
2. I prezzi al m² che ricaviamo dai contratti sono corretti per padiglione?

| Edizione | Prezzo €/m² (dai contratti) | Ipotesi di abbinamento |
|---|---|---|
| 2024 | 110 / 150 / 165 | P3 / P2 / P1 |
| 2025 | 120 / 160 / 180 | P3 / P2 / P1 |
| 2026 (listino fornito) | 125 / 170 / 190 | P3 / P2 / P1 |

**Perché**: senza listino storico non si può verificare se un prezzo di riga è “fuori listino”. Gli extra risultano costanti (elettrico 250/420, fibra 600, arredo 25, pass 20, parcheggio 60); le sponsorizzazioni 2024 sono il 90 % di quelle 2025-2026.
**Se non risponde**: ricostruiamo i listini dalle righe contratto e li marchiamo “da validare”.
**Blocca**: caricamento contratti, controllo prezzi.
**Risposta**: ______________________

### D7. Un contratto per espositore e edizione? (Q-07)
**Cosa chiediamo**: un espositore può avere **più contratti** nella stessa edizione (per esempio per due stand)? Un contratto può includere più stand?

**Perché**: nei dati 2025 ogni espositore ha esattamente un contratto (110 su 110), ma non sappiamo se è una regola.
**Se non risponde**: lo schema ammette più stand per contratto e più contratti per espositore; non imponiamo il vincolo.
**Blocca**: vincoli del database (da congelare il 30/10), flusso preventivo→contratto.
**Risposta**: ______________________

### D8. Date reali dell'evento (Q-01)
**Cosa chiediamo**: quali sono le date di **2024, 2025 e 2026**? Il brief dice “fine novembre”, ma biglietti e tornelli indicano **20-22 dicembre 2024** e **19-21 dicembre 2025** (apertura 09:00, chiusura circa 17:30).

**Perché**: giorni validi dei biglietti, calendario e scadenza del saldo (30 giorni prima dell'apertura).
**Se non risponde**: usiamo le date dei dati; per il 2026 nessuna data finché non ci viene data.
**Blocca**: calendario edizioni, scadenze dei promemoria.
**Risposta**: ______________________

### D9. Contatto qualificato e costi attribuibili (Q-11)
**Cosa chiediamo**
1. Cosa rende un contatto **“qualificato”**? (esempio: consenso + interesse indicato?)
2. Esistono **costi attribuibili** a stand o campagne (anche solo il costo dello stand)?

**Perché**: il costo per contatto = costo attribuibile / contatti qualificati. Oggi non abbiamo né costi né una definizione.
**Se non risponde**: il KPI è dichiarato **non calcolabile**; mostriamo un indicatore sostitutivo con nome esplicito (“valore del contratto per visita”).
**Blocca**: KPI 5 e pagina “Performance espositori”.
**Risposta**: ______________________

### D10. Chi approva le definizioni dei KPI
**Cosa chiediamo**: chi, in Factory Studios, **approva le formule** dei KPI? Possiamo concordare un'unica data di approvazione?

**Perché**: lo stesso KPI deve avere la stessa definizione in API, portale e Power BI, e dopo il 30/10 ogni modifica incompatibile va concordata.
**Se non risponde**: le nostre definizioni restano “proposte” e lo scriviamo ovunque.
**Blocca**: congelamento del 30/10.
**Risposta**: ______________________

---

## P2 — Necessarie per la demo (entro il 13 novembre)

### D11. Formato dei dati dal vivo
**Cosa chiediamo**: durante l'evento, come arrivano **biglietti, tornelli e scansioni**? File, API, database? Con quale frequenza? Le scansioni degli stand identificano un biglietto/badge o solo lo stand?

**Perché**: oggi abbiamo solo file chiusi. Il “tempo reale” della fase B dipende da come arrivano i dati; nel 2025 le visite sono **aggregate per ora**, non eventi singoli.
**Se non risponde**: simuliamo eventi con un generatore controllato, **chiaramente marcato demo**.
**Blocca**: dashboard operativa e app di scansione.
**Risposta**: ______________________

### D12. I 9 espositori 2024 non riconosciuti (Q-08)
**Cosa chiediamo**: a quale espositore dell'anagrafica corrispondono questi nomi presenti nei contratti 2024?

> Ardesia Markets · Bussola Gears · Delta Workshops · Dora Techs · Idra Entertainments · Isola Snacks · Pietra Entertainments · Pixelia Pixels · Tundra Distribuzioni

**Perché**: i contratti 2024 non hanno id né P.IVA. 79 nomi su 88 sono stati riconosciuti dopo la normalizzazione; questi 9 no.
**Se non risponde**: restano in **quarantena**, esclusi dai KPI per espositore.
**Blocca**: confronto 2024/2025 per espositore, rinnovi.
**Risposta**: ______________________

### D13. Stati degli stand
**Cosa chiediamo**: come si trattano gli stand **riservati, gratuiti, non commercializzabili**? Contano nella saturazione? Come si gestisce una riserva (durata)?

**Perché**: la saturazione = m² occupati / m² commercializzabili. Oggi calcoliamo “venduto” solo da contratto firmato.
**Se non risponde**: venduto = contratto firmato; gratuiti conteggiati a parte; non commercializzabili esclusi dal denominatore.
**Blocca**: KPI saturazione.
**Risposta**: ______________________

### D14. Prelazione (Q-13)
**Cosa chiediamo**: la prelazione (“fino al 31 marzo 2026 sullo stesso stand”) vale per **tutti** i contratti 2025 o solo per quelli rinnovati? Cosa succede alla scadenza? Chi può esercitarla e come?

**Perché**: serve per la fase C e per il flusso commerciale 2026.
**Se non risponde**: il diritto nasce da ogni contratto 2025 firmato, per lo stesso stand, scade il 31/03/2026.
**Blocca**: gestione prelazioni in Power Apps e promemoria.
**Risposta**: ______________________

### D15. Sconti sui biglietti (Q-09)
**Cosa chiediamo**: percentuale e regole di **SCUOLA, STUDENTI, EARLY10**.

**Perché**: nei prezzi vediamo una seconda tariffa pari a −10 %, ma non sappiamo a quale codice corrisponda.
**Se non risponde**: usiamo −10 % osservato solo come informazione, non come regola.
**Blocca**: analisi prezzi biglietti (non bloccante per la demo).
**Risposta**: ______________________

### D16. La riga da 912 scansioni (Q-12)
**Cosa chiediamo**: lo stand **P1-A02 il 19/12/2025 alle 08:00** ha 912 scansioni. Il massimo di tutti gli altri valori è 177, e l'apertura è alle 09:00. È un errore?

**Perché**: falsa il totale visite dello stand.
**Se non risponde**: lo teniamo e lo segnaliamo come anomalia **aperta**.
**Blocca**: visite per stand dell'espositore interessato.
**Risposta**: ______________________

### D17. Metri quadrati degli stand nel tempo (Q-14)
**Cosa chiediamo**: la superficie di uno stand può cambiare da un'edizione all'altra? Nei dati c'è un solo valore per stand.

**Perché**: il ricavo per m² storico dipende da questo.
**Se non risponde**: superficie unica per stand.
**Blocca**: confronto €/m² tra edizioni.
**Risposta**: ______________________

### D18. Espositori mai contrattualizzati nel 2025
**Cosa chiediamo**: 25 espositori in anagrafica non hanno contratti 2025. Sono **prospect**, espositori solo del 2024, o altro?

**Perché**: nei contratti 2024 gli id mancano, quindi non possiamo distinguere. Serve a classificare chi è “cliente” e chi “in trattativa”.
**Se non risponde**: stato derivato dai contratti (nessuno stato salvato).
**Blocca**: elenco prospect e rinnovi.
**Risposta**: ______________________

---

## P3 — Da chiudere prima della consegna (entro il 27 novembre)

### D19. Cancellazioni, rimborsi e storni
**Cosa chiediamo**: come si gestiscono contratti cancellati, penali e rimborsi? Esistono casi nei dati storici?
**Se non risponde**: contratto `CANCELLED` esclude i KPI; rimborsi come pagamenti negativi.

### D20. Capienze e soglie operative
**Cosa chiediamo**: capienza massima per padiglione e soglie di allerta (es. 80 %) per la dashboard dello staff.
**Se non risponde**: nessuna soglia; la dashboard mostra solo i valori.

### D21. Sponsorizzazioni
**Cosa chiediamo**: la disponibilità del listino (es. 1 Main Stage, 3 tornei, 10 social) è vincolante per la vendita? Come si seguono consegna e stato?
**Se non risponde**: la disponibilità è un limite massimo controllato in vendita.

### D22. Utenti e ruoli
**Cosa chiediamo**: quali profili esistono (commerciale, operativo, direzione, espositore, scansione)? Come si assegnano gli accessi degli espositori?
**Se non risponde**: ruoli come da proposta (ADMIN, COMMERCIAL, OPS, EXHIBITOR, SCANNER, BI_READER).

### D23. Persone dietro i biglietti
**Cosa chiediamo**: nei biglietti Family (4 persone), la dashboard deve contare **biglietti** o **persone**? Per le presenze stimate vale lo stesso criterio?
**Perché**: 2.420 biglietti Family nel 2024 e 2.901 nel 2025 valgono 4 persone ciascuno.
**Se non risponde**: mostriamo entrambe le misure, separate.

---

## Domande interne al team (non per il cliente)

| ID | Domanda | Perché | Se non c'è risposta |
|---|---|---|---|
| T1 | Abbiamo un **tenant Microsoft** con Power Apps, Power Automate, Power BI? Che licenze? | I custom connector richiedono licenza premium | Piano B: sviluppo contro Swagger/Postman e Power BI Desktop su viste/CSV, dichiarando “da configurare” |
| T2 | Dove gira il backend per la demo (tunnel temporaneo o cloud)? | Il cloud Microsoft non vede `localhost` | Demo con dati simulati in Power Apps |
| T3 | Il database sarà raggiungibile da Power BI Service o serve un **gateway**? | Power BI legge direttamente dal database | Power BI Desktop in locale |
| T4 | Autenticazione: Entra ID per tutti o login semplice in locale? | Il connector usa OAuth | Login locale per sviluppo, Entra ID per Power Platform |

---

## Scaletta per la riunione (30 minuti)

1. **5′** — Obiettivo e calendario (30/10, 13/11, 4/12). Cosa stiamo congelando il 30/10.
2. **10′** — D1, D2, D3, D4 (le più rischiose per i dati).
3. **5′** — D5, D6, D7, D8.
4. **5′** — D9 e D10 (KPI e chi approva).
5. **5′** — Mostrare D12 (i 9 nomi) e concordare modalità e data delle risposte per P2/P3.

**Da portare con noi**: elenco dei 9 nomi (D12), tabella prezzi (D6), numeri di profiling (D1, D3, D4), e [data-model.md](data-model.md) per i dettagli.

## Dopo la riunione

- Aggiornare questo file con le risposte e la data.
- Per ogni risposta che cambia lo schema o il contratto API, aprire una modifica **concordata** prima del 30/10.
- Riportare in `docs/` il registro delle decisioni (cosa è stato deciso, da chi, quando).

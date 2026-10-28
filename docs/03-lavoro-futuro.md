# Lavoro futuro

Cosa resta da fare, in ordine di priorità, con scadenze del calendario di progetto. Stato di tutto: **da fare**, salvo dove indicato.

Date: **30/10** SAL 1 (schema e API congelati) · **13/11** SAL 2 (demo con dati 2024/2025 e vendita 2026) · **16/11–4/12** sviluppo e integrazione · **4/12** presentazione finale.

---

## 1. Prima del 30 ottobre (SAL 1)

| # | Attività | Chi | Perché |
|---|---|---|---|
| 1 | Portare al cliente le **domande Q-01…Q-14** ([data-model.md](data-model.md) §11), ordinate per priorità | BID + BAD | Evita di costruire su ipotesi sbagliate |
| 2 | **Congelare lo schema** (V1–V4) dopo la revisione del BAD | BID + BAD | Consente lo sviluppo parallelo |
| 3 | Scrivere il **contratto API** (OpenAPI) e congelarlo | BID (guida) + BAD | Power Apps e Power Automate dipendono da questo |
| 4 | Chiudere le definizioni dei **KPI** con il cliente | BID + BAD | Una definizione sola per API, portale, Power BI |
| 5 | Documentare il **processo commerciale** (stati: bozza → confermato → contratto → acconto → saldo) | BAD | Base per Power Apps |
| 6 | Verificare **tenant Microsoft e licenze** (Power Apps premium per custom connector, Power BI, gateway) | BAD | Sblocca tutto il lato Microsoft |
| 7 | Decidere **dove gira il backend** per la demo (tunnel, cloud) | BID | Il cloud Microsoft non raggiunge `localhost` |

### Le domande più urgenti (sintesi)
- **Q-01** Date reali dell'evento (i dati dicono 19-22 dicembre, il brief “fine novembre”).
- **Q-02** I varchi sono ingressi ai padiglioni? Esistono uscite? Quanto si ferma una persona (per le presenze stimate)?
- **Q-03** Significato di `rinnovo`.
- **Q-04** Listini 2024/2025 ufficiali.
- **Q-05/Q-06** Importi pagati e IVA.
- **Q-08** I 9 nomi espositori 2024 non riconciliati.
- **Q-10** Consenso dei contatti, minori, conservazione delle email.

---

## 2. Fino al 13 novembre (SAL 2)

| # | Attività | Chi | Output verificabile |
|---|---|---|---|
| 8 | **ETL**: caricare i 10 file in staging con hash e batch | BID | `import_batch` valorizzato, riga letta = caricata + quarantena + scartata |
| 9 | **ETL**: trasformare in `core` (conversione date Excel, fusi orari, normalizzazione province/tipi/varchi, risoluzione biglietti, hash delle email) | BID | Dati 2024 e 2025 nel core |
| 10 | **Riconciliare i nomi 2024** → `exhibitor_alias` (esatto, normalizzato, fuzzy con conferma umana) | BID + BAD | Elenco con i casi risolti e quelli in quarantena |
| 11 | Ricostruire i **listini 2024/2025** dalle righe contratto | BID | `price_list` con `origin = RECONSTRUCTED...` da far validare |
| 12 | Rilevare e registrare le **anomalie** (catalogo §7 di data-model) | BID | Conteggi per regola in `kpi_data_quality_anomaly` |
| 13 | Verificare la **riconciliazione** (REC-01…REC-08) | BID | Tutte `MATCH` o `EXPECTED_DIFF` motivate |
| 14 | **Backend Spring Boot**: scheletro, Flyway, Spring Security, endpoint commerciali (espositori, stand, preventivi, contratti, acconti) | BID | Swagger raggiungibile, test verdi |
| 15 | **Power Apps** minima: planimetria, preventivo, conversione in contratto, acconto | BAD | Un contratto 2026 venduto dal vivo |
| 16 | **Power BI** v1: ricavi, saturazione, qualità dati | BAD | Pagine che leggono le viste `analytics` |
| 17 | **Dashboard staff** (Angular) v1 con indicatore **demo/reale** | BID | Affluenza e visite da dati caricati |
| 18 | **Portale espositori** minimo + test di isolamento | BID | Un espositore non vede i dati di un altro |

---

## 3. 16 novembre – 4 dicembre (integrazione e consegna)

| # | Attività | Chi |
|---|---|---|
| 19 | API ingest tornelli/scansioni con deduplica e protezione da richieste duplicate | BID |
| 20 | **App di scansione stand** (web mobile): evento con `visit_uuid`, gestione errori di rete | BID |
| 21 | Presenze stimate: validare il tempo di permanenza con il cliente; misurare le **prestazioni** su volumi reali ed eventualmente materializzare | BID |
| 22 | Generatore **eventi demo** controllato (modalità demo ben visibile) | BID |
| 23 | **Power Automate**: promemoria scadenze acconto, prelazioni in scadenza, segnalazione anomalie (destinatari parametrici, nessuna e-mail inventata) | BAD |
| 24 | Prelazioni e sponsorizzazioni nell'app e nel portale | BAD + BID |
| 25 | Report individuale per espositore (ed export, opzionale PDF) | BID |
| 26 | Power BI complete: 5 pagine, misure DAX, drill-down, aggiornamento | BAD |
| 27 | **Test automatici**: funzionali, dati, sicurezza (anche via backend), E2E dei 12 passi | BID + BAD |
| 28 | Verifica **privacy**: registro decisioni con il referente, retention staging, conservazione, minori | BID + BAD |
| 29 | Documentazione finale: README, guida all'avvio, dizionario dati, registro assunzioni/anomalie, script della demo | BID + BAD |
| 30 | Presentazione e **demo dal vivo** delle 3 fasi (prima, durante, dopo la fiera) | Tutti |

---

## 4. Rischi da tenere d'occhio

| Rischio | Segnale | Contromisura |
|---|---|---|
| Nessuna licenza/tenant Microsoft | Risposta negativa al punto 6 | Piano B: Power BI Desktop su CSV/viste e Power Apps con dati simulati, **dichiarandolo** |
| Backend non raggiungibile da Microsoft | Connector non si collega | Tunnel di sviluppo o hosting cloud |
| Dati 2024 non riconciliabili | Molti casi in quarantena | Revisione umana, mappatura fornita dal cliente |
| KPI discordanti tra API e Power BI | Riconciliazione fallisce | Definizione solo nelle viste SQL |
| Privacy dei minori | Contatti 14-17 con consenso | Quarantena e decisione del referente prima di mostrare dati |
| Troppo lavoro per il tempo | Ritardi sul 13/11 | Fare l'MVP verticale, rimandare opzionali (PDF, rifiniture) |

---

## 5. Prossima azione consigliata

Scegliere **una** tra queste, in ordine:

1. **Lista domande per il cliente** pronta per il kickoff (sblocca quasi tutto).
2. **Loader ETL** per biglietteria e tornelli (è la parte che produce numeri reali da verificare).
3. **Contratto API** (OpenAPI) bozza da congelare il 30/10.

---

## 6. Regole che restano valide

- Non dichiarare **fatto** ciò che non è stato eseguito; distinguere sempre *implementato / testato / simulato / da configurare*.
- Non inventare dati, indirizzi e-mail, consensi o basi giuridiche del cliente.
- Dati sintetici sempre marcati come demo.
- Nessuna password, token o segreto nel repository.
- Ogni modifica incompatibile a schema o API dopo il 30/10 va concordata e documentata.

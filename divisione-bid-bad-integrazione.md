# Divisione BID / BAD, integrazione e frontend

## 1. Task divise per ruolo

### BID (codice: Java, PostgreSQL, Angular)

| Area | Task |
|---|---|
| **Database** | ER definitivo, DDL e migrazioni Flyway, seed demo 2024/2025, vincoli anti-doppia-vendita, viste `analytics` per i KPI, ruolo Postgres read-only per Power BI |
| **Backend Spring Boot** | Tutte le API del §8 (commerciali, ingest, KPI, report, anomalie), DTO, validazione, Spring Security (JWT e ruoli), isolamento per espositore, Swagger/OpenAPI, `Idempotency-Key`, gestione errori e log |
| **ETL** | Staging, validazione, normalizzazione, quarantena, `data_anomaly`, idempotenza, riepilogo import, riconciliazione |
| **Frontend Angular** | Dashboard operativa staff, portale espositori, PWA di scansione stand |
| **Test** | JUnit e Testcontainers, test di sicurezza (accesso ai dati di altri espositori), test di riconciliazione, test E2E |
| **DevOps** | `docker-compose`, README, variabili d'ambiente, hosting raggiungibile da Microsoft (vedi §2) |

### BAD (Power Platform)

| Area | Task |
|---|---|
| **Processo commerciale** | Flusso preventivo → contratto → acconto → prelazione, stati e validazioni, specifica delle regole |
| **Power Apps** | Back-office: dashboard commerciale, espositori, planimetria, listino, preventivi, contratti, acconti, sponsorizzazioni, prelazioni, storico trattative |
| **Power Automate** | Notifiche, promemoria scadenze acconti, avviso prelazioni in scadenza, segnalazione anomalie. Destinatari come parametri configurabili |
| **Power BI** | Le 5 pagine direzionali, modello a stella, misure DAX, refresh, RLS se serve |
| **Export e versionamento** | Solution esportata e versionata in `power-platform/` |

### Condiviso (da fare insieme)

Schema dati (congelato il 30/10), contratto API, definizioni dei KPI, regole di qualità dati, privacy, test di integrazione, riconciliazione, demo.

**Regola pratica**: il BAD non scrive logica di business critica in Power Apps. Le regole (doppia vendita, importi, stati) stanno nel backend e Power Apps le richiama.

---

## 2. Come collegare Power Apps al backend Java

Il collegamento si fa con un **custom connector** generato dall'OpenAPI del backend:

```
Power Apps / Power Automate  →  Custom Connector  →  REST API Spring Boot  →  PostgreSQL
```

### Passi

1. **BID**: pubblica `/v3/api-docs` (OpenAPI 3) con gli endpoint commerciali e lo schema di sicurezza OAuth2.
2. **BID**: rende il backend raggiungibile in **HTTPS pubblico**. Questo è il punto critico: il cloud Microsoft non vede `localhost`.
   - Per la demo: un *dev tunnel* o ngrok, oppure un deploy su Azure App Service o simili.
   - Alternativa: un **on-premises data gateway** installato dove gira il backend. Il gateway è supportato dai custom connector.
3. **BID/BAD**: in Microsoft Entra ID si registrano due app:
   - una per l'**API** (con scope, es. `api://arcade/commercial`);
   - una per il **connector**, con client ID e secret custodito fuori dal repo.
4. **BAD**: Power Apps → *Dati → Connettori personalizzati → Importa da OpenAPI*. Si configura l'autenticazione OAuth 2.0 (Entra ID) e si crea la connessione.
5. **BAD**: nell'app, le chiamate sono del tipo `ArcadeAPI.CreateQuote({...})`. Gli errori `409 STAND_ALREADY_SOLD` si leggono e si mostrano all'utente.
6. **Spring Boot** valida il JWT di Entra ID (`spring-security-oauth2-resource-server`) e mappa i ruoli (es. `COMMERCIAL`).

### Cose da verificare prima di promettere che funzioni

- I custom connector richiedono licenza **Power Apps Premium** (o equivalente). Va controllata nel tenant.
- Servono permessi di creare connessioni e registrare app in Entra ID (di norma un amministratore).
- Il connector non è "già collegato": finché non è configurato e testato, va dichiarato **da configurare**.

**Piano B senza tenant**: sviluppare e documentare tutto contro Swagger o Postman, e mostrare Power Apps con dati simulati, dichiarando chiaramente che l'integrazione non è realizzata.

---

## 3. Frontend Angular e Power Apps

**Non si "implementa" Angular dentro Power Apps.** Sono due frontend distinti, per utenti diversi, che condividono lo stesso backend.

| Frontend | Utenti | Tecnologia |
|---|---|---|
| Back-office commerciale | Staff commerciale | **Power Apps** (BAD) |
| Dashboard operativa, portale espositori, scansione stand | Staff operativo, espositori, staff agli stand | **Angular** (BID) |
| Dashboard direzionale | Direzione | **Power BI** (BAD) |

### Se serve far dialogare i due mondi

- **Collegamento diretto (consigliato)**: in Power Apps un pulsante con `Launch("https://portale.../esp/42")` apre il portale Angular. L'autenticazione è condivisa tramite Entra ID (SSO) oppure si ripete il login.
- **Incorporare Angular in Power Apps**: le canvas app non supportano iframe. L'unica via reale è un **PCF code component** (TypeScript) che incapsula un iframe. È complessa, richiede licenza premium e ha problemi di sicurezza e di autenticazione (X-Frame-Options, CSP, cookie di terze parti). **Sconsigliata** per un progetto formativo.
- **Incorporare Power BI in Angular**: è l'inverso e funziona, con *Power BI Embedded* o il link di embed. Richiede capacità e licenze. Per ora basta il link al report.

Se il brief richiede che i due prodotti convivano, in realtà richiede solo che i **dati siano coerenti**, e questo è garantito dall'API e dal DB condivisi. Non richiede che le UI siano fuse.

---

## 4. Backend e database in Power Apps

**Backend**: non va "messo" in Power Apps. Gira per conto suo (Docker in locale, Azure o simili in cloud) e Power Apps lo chiama via connector. Power Apps non esegue codice Java.

**Database**: Power Apps **non dovrebbe leggere o scrivere direttamente su PostgreSQL**. Esiste un connettore PostgreSQL (premium, con gateway se il DB non è pubblico), ma bypassa le regole del backend, cioè vincoli, audit e autorizzazioni. Per il brief ("le applicazioni usano API e contratti espliciti") la strada giusta è sempre l'API.

| Componente | Come accede ai dati |
|---|---|
| Power Apps | **Solo** via API (custom connector) |
| Power Automate | Via API (custom connector o azione HTTP) |
| Angular | Solo via API |
| **Power BI** | **Direttamente** sulle viste `analytics` di PostgreSQL, con ruolo read-only. Serve gateway se il DB non è pubblico |
| ETL | Direttamente su PostgreSQL (è nel backend/BID) |

Power BI è l'unico a leggere il DB, e solo da viste. Per questo le definizioni dei KPI stanno nelle viste: API e Power BI mostrano gli stessi numeri.

---

## 5. Decisioni da prendere subito

1. Dove gira il backend per la demo? (tunnel temporaneo o cloud?) Questa scelta sblocca tutto il lato Microsoft.
2. Il tenant ha licenze Premium per i custom connector?
3. Entra ID per tutti gli utenti, o login semplice in locale e Entra ID solo per il connector?

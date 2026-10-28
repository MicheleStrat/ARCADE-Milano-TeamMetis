# Guida al database ARCADE Milano

Spiegazione semplice di come è fatto il database e come avviarlo e provarlo. Per i dettagli tecnici: [data-model.md](data-model.md).

---

## 1. Come è organizzato

Il database ha cinque “stanze” (schemi):

| Schema | A cosa serve | Esempio |
|---|---|---|
| `staging` | Copia dei file del cliente **così come arrivano**, tutto testo | `stg_ticket` |
| `core` | I dati veri, ordinati e protetti da vincoli | `contract`, `ticket`, `stand` |
| `dq` | Qualità dei dati: file importati, regole, anomalie, quarantena | `anomaly`, `import_batch` |
| `analytics` | Dati pronti per i KPI e per Power BI | `kpi_saturation` |
| `portal` | Le sole viste che l'espositore può leggere | `v_my_contracts` |

### Il flusso dei dati (futuro, quando ci sarà l'ETL)

```
File del cliente → staging → controlli → core → analytics → API / Portale / Power BI
                              ↓
                       anomalie e quarantena (dq)
```

### Le tre idee più importanti

1. **Stand ≠ occupazione dello stand.** Lo stand P1-A01 esiste per sempre; ogni anno ha una riga che dice se è venduto e a chi.
2. **Espositore ≠ contratto.** L'azienda è una; i contratti sono uno per edizione.
3. **Niente si perde.** Un dato sospetto viene caricato e segnalato oppure messo in quarantena con la riga originale. Non si cancella e non si “aggiusta” senza una regola scritta.

### Domande tipiche, con la risposta

| Domanda | Risposta |
|---|---|
| Come si evita di vendere due volte lo stesso stand? | Un indice nel database ammette un solo contratto attivo per ogni stand e edizione. Funziona anche se due persone provano nello stesso istante. |
| Cosa succede se importo due volte lo stesso file? | Il file ha un’impronta (hash): il secondo import riconosce il file e non duplica nulla. |
| Perché le presenze sono “stimate”? | I tornelli registrano solo gli ingressi, mai le uscite. Si può solo stimare con un tempo di permanenza ipotetico (90 minuti). |
| Biglietti venduti, ingressi, persone e visite sono lo stesso numero? | No. Sono misure diverse e non si sommano. |
| L’espositore A può vedere i dati di B? | No: lo blocca il backend e, in più, il database (RLS). Senza l'identità dell'espositore non si vede nulla. |
| Dove sono le email dei contatti? | Non ci sono. Si salva solo un hash. |
| Il ricavo per m² include le sponsorizzazioni? | No: conta area e maggiorazioni al netto dello sconto. Extra e sponsor sono riportati a parte. |

---

## 2. Come avviarlo (locale, con Docker)

Serve **Docker Desktop**. Il database di prova è temporaneo e si cancella quando si vuole.

**1) Avviare PostgreSQL con le migrazioni montate**

```bash
docker run -d --name arcade-db -e POSTGRES_PASSWORD=test -e POSTGRES_DB=arcade -v "$(pwd)/database/migrations:/m:ro" postgres:16-alpine
```

> `test` è una password **solo per prove locali**. Mai usarla altrove né salvarla in file del progetto.
> In Git Bash su Windows, prima del comando esegui `export MSYS_NO_PATHCONV=1`, altrimenti i percorsi `/m/...` vengono alterati. In PowerShell usa `${PWD}` al posto di `$(pwd)`.

**2) Applicare le migrazioni in ordine** (attendi qualche secondo dopo l'avvio)

```bash
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V1__core_schema.sql
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V2__reference_data.sql
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V3__roles_grants_rls.sql
docker exec arcade-db psql -U postgres -d arcade -v ON_ERROR_STOP=1 -f /m/V4__analytics.sql
```

Se un comando stampa un errore, si ferma subito (è voluto).

**3) Controllare**

```bash
docker exec arcade-db psql -U postgres -d arcade -c "SELECT count(*) FROM information_schema.tables WHERE table_schema IN ('core','staging','dq');"
```

Risultato atteso: `58`.

**4) Eseguire i test**

I test creano dati di prova (non del cliente). Eseguili su un database **appena creato**: `kpi_rls_smoke.sql` inserisce dati veri e propri e non è pensato per essere rieseguito sullo stesso database.

```bash
docker exec -i arcade-db psql -U postgres -d arcade -q < database/tests/kpi_rls_smoke.sql
```

Come leggere l'output: ogni blocco ha una riga `atteso ...` con il risultato corretto. Per `constraints_smoke.sql`, le righe `ERROR:` sono **volute**: dimostrano che il database ha bloccato l'operazione vietata.

**5) Spegnere tutto**

```bash
docker rm -f arcade-db
```

---

## 3. Ruoli del database

| Ruolo | Chi lo usa | Cosa può fare |
|---|---|---|
| `arcade_app` | Backend (staff) | Leggere/scrivere `core`; l'audit solo in aggiunta |
| `arcade_portal` | Backend per un espositore | Solo lettura delle **proprie** righe |
| `arcade_etl` | Caricamento dati | Scrivere staging e core, **non cancellare** dal core |
| `arcade_bi` | Power BI | Solo lo schema `analytics` |

Sono ruoli “di gruppo”: per usarli serve creare un utente con password **per ambiente** (esempio in testa a V3). Le password non vanno nel repository.

### Come il backend userà l'isolamento (da implementare)

Per una richiesta di un espositore, il backend:
1. verifica il token di accesso (JWT) e ricava l'`exhibitor_id`;
2. apre una transazione e imposta `SET LOCAL ROLE arcade_portal`;
3. imposta `app.exhibitor_id`;
4. esegue la lettura (solo con parametri, mai testo SQL concatenato).

---

## 4. I KPI e dove sono

| KPI | Vista | Nota importante |
|---|---|---|
| Visitatori | `kpi_visitors_edition`, `kpi_visitors_daily` | Più misure, **non** sommarle |
| Presenze / picco | `kpi_presence_peak`, `presence_estimate()` | **Stima** |
| Saturazione | `kpi_saturation` | m² venduti / m² commercializzabili |
| Ricavo e ricavo/m² | `kpi_commercial_edition`, `kpi_space_revenue_pavilion` | Contrattualizzato, netto sconto, IVA esclusa |
| Per espositore | `kpi_exhibitor_edition` | Costo per contatto: non calcolabile |
| Confronto edizioni | `kpi_edition_comparison` | Variazione vuota se mancano dati |
| Rinnovo | `kpi_renewal_edition` | Vuoto se l'edizione dopo non ha contratti |
| Qualità dati | `kpi_data_quality_batch`, `kpi_data_quality_anomaly` | Per la pagina 5 di Power BI |
| Riconciliazione | `reconciliation_status` | Deve dire `MATCH` |

---

## 5. Problemi comuni

| Sintomo | Causa probabile | Rimedio |
|---|---|---|
| `psql: ... No such file or directory` su `/m/V1...` | Git Bash cambia i percorsi | `export MSYS_NO_PATHCONV=1` |
| `relation ... already exists` | Migrazioni già applicate | Cancella il container e riparti da capo |
| Il portale non vede nessuna riga | Manca `app.exhibitor_id` (voluto) | Impostalo nella transazione |
| Il test dà errori in più rispetto all'atteso | Database non vuoto | Ricrea il container |

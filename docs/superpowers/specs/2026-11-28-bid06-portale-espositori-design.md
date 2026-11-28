# BID-06 — Portale espositori: prima versione (specifica)

Data: 28 novembre 2026 · Responsabile: Mattia · Stato: **approvata il 28/11** · Ramo: `task-06`

## 1. Obiettivo

Dare agli espositori un portale web in Angular in cui vedono **solo i propri dati**. La prima versione contiene accesso di prova, contratto con stand e pagamenti, visite agli stand e confronto tra edizioni, ed è pensata per **computer**. Obiettivo di calendario (ipotesi di lavoro): una versione dimostrabile al SAL 2 del 4/12.

| Issue | Cosa copre questa versione |
|---|---|
| `#35` accesso | Accesso **di prova** e logout con revoca. Il login con l'email del referente resta da fare. |
| `#36` visite | Schermata Visite, con dati demo. |
| `#37` riepilogo e confronto | Schermata Riepilogo, con dati demo. |
| `#38` dati dalle API | **Parziale**: solo accesso, logout e profilo usano il backend. |
| `#39` separazione dei dati | **Non completata**: filtrare dati finti nel browser non protegge niente. Si completa con gli endpoint veri e i loro test. |

### Fuori da questa versione

Email e numero dei contatti, costo per contatto, costo (o valore del contratto) per visita, confronto anonimo di mercato, report, informazioni sulla prelazione, versione per telefono, login con l'email del referente o con Entra ID.

Il costo per visita resta fuori perché il contratto API ha solo `contractValuePerVisit`, mentre la regola del product owner sul costo per contatto parte da quanto è stato **pagato**. Va chiarito se vale lo stesso per le visite.

## 2. Chi fa cosa

- **Mattia:** frontend del portale e logout con revoca nel backend.
- **Alessandro:** `GET /portal/me/contracts`, `/portal/me/visits`, `/portal/me/kpi`, con l'espositore preso solo dal token e i test di isolamento. La richiesta gli è stata inviata; qui non è registrata la sua risposta.

## 3. Schermate

Menu in alto con le tre pagine, nome dell'espositore e tasto **Esci**.

### 3.0 Accesso di prova
- Un campo: ID dell'espositore di test. Il portale chiama `POST /dev/token` con il solo ruolo `EXHIBITOR`.
- La pagina dice in modo evidente che è un **accesso di prova**.
- Dopo il token il portale chiama `GET /portal/me`. Se risponde 404, esegue il logout e mostra "Espositore non trovato".

### 3.1 Riepilogo (pagina iniziale)
- Ragione sociale, codice e categoria da `/portal/me` (**dati veri**).
- "Ultima edizione" = l'`editionYear` più alto tra i risultati ricevuti.
- Quattro numeri di quell'edizione: visite, visite al m² (`visitsPerSqm`), superficie (`sqm`), importo netto (`contractedNet`).
- Tabella di confronto con una riga per edizione: anno, visite, visite al m², superficie, netto, variazione di visite (`visitsDeltaPct`) e di netto (`contractedNetDeltaPct`), con l'anno di riferimento (`prevYear`).
- Le variazioni si mostrano come arrivano dai dati: il portale non le ricalcola.

### 3.2 Visite
- Scelta dell'edizione; all'inizio è selezionata la più recente.
- Totale delle visite, grafico per giorno e ora, tabella per stand.
- Nota fissa: **una visita non è un contatto**.

### 3.3 Contratto
- Per ogni contratto: numero, edizione, stato (`DRAFT` = Bozza, `SIGNED` = Firmato, `CANCELLED` = Annullato), data di firma, stand, listino, sconto, netto. Importi in euro, **IVA esclusa**.
- Acconto e saldo, ciascuno con uno stato scritto:

| Condizione (in quest'ordine) | Testo |
|---|---|
| c'è la data di pagamento | "Pagato il …" |
| contratto annullato | "—" (contratto annullato) |
| non c'è la scadenza | "—" (scadenza non disponibile) |
| scadenza passata (prima di oggi) | "Scaduto il …" |
| altrimenti | "Da pagare entro il …" |

Il portale non calcola scadenze né importi di acconto e saldo: il contratto API non li fornisce.

### 3.4 Regole comuni
- Dato mancante: **"—" con una breve spiegazione**, mai zero. Uno zero ricevuto dai dati resta "0".
- Parti con dati finti: etichetta **"dati demo"**. Il profilo è vero e il resto no, quindi i numeri non sono quelli reali dell'espositore, e la pagina lo dice.
- Ogni pagina ha gli stati di caricamento, errore (con "Riprova") e nessun dato.
- Gli stati si capiscono dal testo, non solo dal colore.

### 3.5 Stile
Stile del mockup "Glassy Dashboard V4": pannelli semitrasparenti, angoli arrotondati, numeri grandi, giallo e nero come accenti, menu a pillole. Rispetto al mockup: sfondo sfumato invece della foto, pannelli meno trasparenti, testi più scuri. Si prende solo lo stile: non nome, contenuti, foto né codice. Con `prefers-reduced-transparency` i pannelli diventano pieni; con `prefers-reduced-motion` le transizioni diventano dissolvenze. Da riconfermare per il portale se arrivano schermate da Framer.

## 4. Frontend

Applicazione nuova in `frontend/`, Angular (versione stabile da verificare nel piano), con il proxy di sviluppo verso il backend (`/api/v1`), senza CORS da aggiungere.

| Parte | Compito | Dipende da |
|---|---|---|
| Accesso | login, logout, token, inattività, sincronizzazione tra schede, protezione delle pagine | backend |
| Dati | interfaccia unica per profilo, contratti, visite, risultati | Accesso |
| Pagine | Riepilogo, Visite, Contratto | solo l'interfaccia Dati |
| Componenti comuni | pannelli, numeri, tabelle, etichetta demo, stati | niente |

- I tipi seguono `PortalProfile`, `PortalContract`, `PortalVisit`, `PortalKpi` di `docs/api/openapi.yaml`.
- Profilo: servizio vero. Contratti, visite, risultati: servizio con dati finti, chiaramente inventati, che includono i casi limite (valori nulli, una sola edizione, pagamento scaduto, contratto annullato, nessuna visita).
- Collegare un endpoint significa sostituire **solo** il servizio corrispondente. L'informazione "è demo" arriva dal servizio, così l'etichetta sparisce da sola.
- `PortalVisit` e `PortalKpi` identificano l'edizione con `editionYear`, mentre il parametro del contratto è `editionId`. In questa versione il portale chiede le visite senza filtro e filtra per anno.

## 5. Autenticazione e logout

### 5.1 Perché
Oggi il backend accetta qualunque token firmato e non scaduto (durata 60 minuti): cancellarlo nel browser non lo rende inutilizzabile. Il logout deve revocarlo **sul server**.

### 5.2 Sessioni sul server
- Una nuova migrazione crea la tabella delle sessioni: identificativo della sessione, utente (`sub`), creazione, ultima attività, scadenza, data di revoca. **Il token non viene salvato.**
- La tabella è usata dal backend con il ruolo `arcade_app`. Il ruolo `arcade_portal` non ha alcun permesso su di essa.
- Ogni token emesso da `JwtService` ha un identificativo (`jti`) e registra la sessione. Se la registrazione fallisce, il token non viene restituito.
- Un controllo su **tutte le richieste con token**, di qualunque ruolo, richiede che la sessione esista, non sia revocata, non sia scaduta e abbia avuto attività da meno di 15 minuti. Controllo e aggiornamento dell'ultima attività avvengono in **un'unica operazione**, così una richiesta non può riattivare una sessione appena revocata.
- Token senza `jti` o senza sessione: **401**. Se il database non permette di verificare: **503**, senza dati (mai accettare nel dubbio).
- Durata massima: 60 minuti. Inattività: 15 minuti. Entrambe configurabili.

### 5.3 Logout
- `POST /auth/logout`, per qualunque utente autenticato. Non ha parametri né corpo: l'utente è il `sub` del token.
- Revoca **tutte** le sessioni attive di quell'utente e risponde `204`.
- In `/dev/token`, quando i ruoli includono `EXHIBITOR` e c'è `exhibitorId`, il `sub` è `espositore-<id>`, qualunque nome arrivi nella richiesta. Negli altri casi resta il nome inviato.

### 5.4 Comportamento in Angular
- Il token sta **solo in memoria**: mai in `localStorage`, `sessionStorage`, cookie, URL o log. Ricaricando la pagina si rifà l'accesso.
- Il token si allega solo alle richieste verso l'API del portale.
- **Logout:** i dati spariscono subito dallo schermo e dalla memoria; il token si tiene solo per la chiamata di logout.
  - `204`: si cancella il token, si torna all'accesso e si avvisano le altre schede.
  - `401`: la sessione corrente non è più valida. Si cancella il token e si mostra "Sessione terminata", **senza** dichiarare chiuse le altre sessioni.
  - Errore di rete o del server: schermata **"Logout non confermato"** con "Riprova". Nessun dato è visibile e non si dice "sei uscito". Chiudendo la pagina, la sessione resta aperta sul server fino alla scadenza.
- **Altre schede:** ogni scheda ha il proprio token. Dopo un logout confermato, le schede dello **stesso utente** (avvisate con `BroadcastChannel`, senza trasmettere il token) cancellano token e dati. Se l'avviso non arriva, la richiesta successiva riceve comunque 401.
- **401 su qualunque richiesta:** si cancellano token e dati e si torna all'accesso con "Sessione terminata".
- **Risposte in ritardo:** al logout le richieste in corso si annullano, e una risposta di una sessione precedente non può aggiornare lo schermo.
- **Tasto Indietro:** le pagine protette richiedono una sessione e non conservano dati dopo l'uscita. Anche il ripristino dalla cache del browser non deve mostrarli.
- **Inattività:** dopo 15 minuti senza mouse, tastiera o tocco il portale esegue il logout. Con i dati demo le pagine quasi non chiamano il backend; per non far scadere un utente che sta leggendo, il portale invia `GET /me` al massimo una volta al minuto, **solo se** c'è stata attività dall'ultima chiamata.

### 5.5 Limiti dichiarati
- `/dev/token` rilascia token per qualunque espositore **senza password**. Il logout non rende sicuro questo accesso: esiste solo con il profilo `dev` e il backend non va messo online con quel profilo.
- Uno script malevolo eseguito durante la sessione (XSS) può agire al posto dell'utente.
- Con Entra ID, o con un altro fornitore di identità, il logout va riprogettato e verificato.

## 6. Errori

| Caso | Comportamento |
|---|---|
| 401 | fine sessione (5.4) |
| 404 su `/portal/me` all'accesso | logout e "Espositore non trovato" |
| rete, 5xx, 503 su una pagina | messaggio e "Riprova"; la sessione resta |
| errore durante il logout | "Logout non confermato" |

## 7. Test (scritti prima del codice)

**Backend**
1. Dopo il logout il **vecchio token** riceve 401 su `/me` e su `/portal/me`.
2. Con due sessioni dello stesso utente, il logout da una fa ricevere 401 anche all'altra.
3. Le sessioni di un altro utente continuano a funzionare.
4. Token firmato correttamente ma senza sessione, o senza `jti`: 401.
5. Sessione scaduta o inattiva oltre il limite: 401. Una richiesta valida aggiorna l'ultima attività.
6. Logout senza token: 401. Secondo logout con lo stesso token: 401.
7. Se la verifica della sessione fallisce per un errore del database: 503 e nessun dato.
8. Due accessi di prova allo stesso espositore con nomi diversi hanno lo stesso `sub`.
9. Il ruolo `arcade_portal` non può leggere né modificare la tabella delle sessioni.
10. Nella tabella non c'è il token.
11. Tutti i test esistenti continuano a passare.

**Angular**
1. Dopo l'accesso, archivi del browser e cookie non contengono il token.
2. Logout con 204: token e dati cancellati, ritorno all'accesso.
3. Logout fallito: "Logout non confermato", nessun dato, "Riprova" funziona.
4. Logout con 401: "Sessione terminata".
5. Una risposta arrivata dopo il logout non aggiorna lo schermo.
6. Pagine protette irraggiungibili senza sessione.
7. L'avviso da un'altra scheda chiude solo le sessioni dello stesso utente.
8. Inattività: logout dopo 15 minuti; la chiamata periodica parte solo dopo attività.
9. Stati dei pagamenti secondo la tabella 3.3; valori nulli come "—" e zero come "0".
10. L'etichetta "dati demo" compare dove il servizio è finto.

**Prova a mano:** accesso, navigazione, logout, tasto Indietro, due schede, e riuso del vecchio token con una richiesta diretta (deve dare 401).

## 8. Punti aperti e coordinamento

| Punto | Con chi | Blocca |
|---|---|---|
| **Numero della nuova migrazione.** Nei rami su GitHub le migrazioni arrivano a `V6` (`V900` e `V901` sono di test), ma la schermata Live del BAD cita una `V14` non trovata nei file SQL del ramo `BAD`. | Fabrizio, Lorenzo | la migrazione delle sessioni |
| Avvisare Alessandro dei file che si toccano: `SecurityConfig`, `JwtService`, `/dev/token`, `openapi.yaml`. I suoi nuovi endpoint vanno autorizzati in `SecurityConfig`. | Alessandro | l'unione dei rami |
| Cambiamento per chi usa il backend: servirà la nuova tabella e i token emessi prima smetteranno di funzionare. Aggiornare `openapi.yaml` (`POST /auth/logout`) e `docs/08-decisioni-condivise.md`. | team BID e BAD | niente |
| Costo per visita: sul valore del contratto o sul pagato? | product owner | una versione successiva |
| Email dei contatti: contratto API e database (oggi solo hash) da modificare. | team BID | una versione successiva |

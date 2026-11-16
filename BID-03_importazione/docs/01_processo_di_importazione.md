# BID-03 · Processo di importazione

> Stato: **proposta BID**, implementata e verificata (vedi `03_test_ed_esiti.md`). Le regole applicate sono quelle di BID-01, non ancora approvate dal cliente/BAD.

## 1. Flusso (uguale per ogni fonte)
1. **Riconoscimento del file** — si calcola lo SHA-256. Se esiste già un'importazione `completata` della stessa fonte con lo stesso hash, il processo termina con `gia_importato` senza toccare i dati.
2. **Registrazione** — si inserisce una riga in `importazione` (`in_corso`) e la si conferma subito: l'avvio resta tracciato anche se poi il caricamento fallisce.
3. **Validazione e normalizzazione** (senza scrivere nei fatti) — formato, campi obbligatori, identificativi, date, relazioni con i dati già in database. Ogni riga è: valida, corretta con regola deterministica, segnalata, **in quarantena** o **scartata**. Nessuna riga sparisce: quarantene e scarti sono registrati uno per uno in `importazione_anomalia` con regola, riga del file e record originale.
4. **Caricamento** — una sola transazione: i dati validi vanno in una tabella temporanea e da lì nelle tabelle dei fatti con la logica sotto; poi si scrivono anomalie e conteggi e l'importazione diventa `completata`.
5. **Errore imprevisto** (violazione di un vincolo non previsto, connessione persa…) — rollback dell'intera transazione, importazione `fallita` con il messaggio in `note`; il file non risulta importato e può essere ripetuto.
6. **File non interpretabile** (vuoto, non UTF-8, colonne obbligatorie mancanti, foglio Excel mancante, edizione inesistente) — `fallita` con la causa, nessun dato caricato.

## 2. Idempotenza e aggiornamenti
| Situazione | Comportamento |
|---|---|
| Stesso file (stesso hash) | `gia_importato`, nessuna modifica |
| File diverso con righe già presenti **identiche** | ignorate, contate in `righe_gia_presenti` |
| File con una **chiave già presente ma valori diversi** | **non** si sovrascrive: anomalia `R-X02` (SEGNALATO) con i valori del file e del database |
| Righe nuove | inserite |
| Righe ripetute dentro lo stesso file | identiche → SCARTATO (tracciato); con valori diversi → QUARANTENA |

La chiave di riconoscimento è, per fonte: `id_biglietto` / `id_ordine`; tornelli `(edizione, varco, codice_letto, istante)`; visite `(edizione, stand, data, ora)`; contatti `id_contatto`; commerciale gli ID di espositore, stand, contratto, `(contratto, riga)`, `(edizione, voce)`. **Due eventi simili non sono mai considerati doppioni**: le letture ravvicinate allo stesso varco (R-T04) restano tutte nel database e sono solo segnalate dalla vista `v_lettura_valutata`.
**Aggiornare dati esistenti** (es. correzione di un prezzo) non è previsto finché non si concorda la regola con il BAD (punto C13 in `02_registro_regole.md`).

## 3. Significato dei conteggi in `importazione`
`righe_lette` = record del file (esclusa l'intestazione; fogli sommati per `commerciale`).
`righe_lette = righe_accettate + righe_corrette + righe_quarantena + righe_scartate` (verificato nei test).
- **accettate**: valide così come sono; **corrette**: caricate dopo una correzione deterministica (valore originale conservato o riga aggregata nel registro);
- **quarantena**: non caricate, record completo in `importazione_anomalia`; **scartate**: non interpretabili (formato), record grezzo conservato;
- **segnalate**: caricate ma con segnalazione informativa (non esclusiva con le altre; include i conflitti `R-X02`);
- `note` (JSON): righe nuove e già presenti per tabella, conflitti non applicati, formato riconosciuto.
Le correzioni e segnalazioni "di massa" (es. 13.383 province normalizzate) sono **una riga di registro per regola** con conteggio ed esempi, non una per record: il valore originale resta nella tabella dei fatti (`provincia_origine`) o nell'origine della regola.

## 4. Dipendenze tra fonti
`commerciale` → `biglietteria` → `tornelli`; `commerciale` → `visite_stand`, `contatti_stand`. Le verifiche si fanno contro il database: una lettura OK su un biglietto non ancora caricato finisce in quarantena (R-T02) e va ricaricata dopo. Con un file diverso (nuovo hash) il ricarico è consentito; **con lo stesso file no**: dopo aver caricato le dipendenze mancanti occorre ricaricare un file diverso o resettare l'importazione (non c'è ancora un'opzione `--forza`).

## 5. Fonti e formati riconosciuti
| Fonte | Formato | Note |
|---|---|---|
| biglietteria | CSV `;`, date `gg/mm/aaaa hh:mm` ora locale, prezzo con virgola | decodifica etichette per edizione (2024, 2025) |
| tornelli | 2024: CSV `;` (data, ora locale, varco con spazio, esito 1/0) · 2025: CSV `,` (timestamp UTC, `OK`/`KO`) | formato riconosciuto dall'intestazione; tutto salvato in UTC |
| visite_stand | CSV `,` `codice_stand,data,ora,scansioni` | orario di apertura 09:00–18:00 |
| contatti_stand | CSV `,` | richiede i contratti già caricati |
| commerciale | Excel: `Espositori`, `Planimetria`, `Listino_<anno>`, `Contratti`, `Righe_contratto` | foglio `LEGGIMI` ignorato |
Il formato degli eventi degli scanner agli stand in arrivo dal BAD **non è ancora definito**: andrà concordato (SHARED-02) e riusa le stesse regole di validazione (`sources.prepara_visite`).

## 6. Limiti noti
- È un processo **a lotti da file**, non un ricevitore di eventi in tempo reale: l'endpoint API per scanner/dati BAD è previsto in BID-04.
- L'intero file è letto in memoria (adatto ai volumi attuali: file da pochi MB; circa 15 s per tutti i file reali).
- Due importazioni **contemporanee** degli stessi dati possono collidere: la seconda fallisce con rollback e si può ripetere.
- I flag dei doppioni (R-T04) e della lettura prima dell'acquisto (R-T05) non sono calcolati qui, ma dalla vista `v_lettura_valutata`.
- Collaudato su un PostgreSQL 16 temporaneo con i file forniti dal cliente: non su un database condiviso del team né con il BAD.

# ARCADE Milano — Contesto team BAD (Power Platform)

> **Proprietario: team BAD.** Lo aggiorna solo il BAD.
> Collegamenti: [[00-indice]] · [[contesto-BID]] · [[decisioni-condivise]] · [[anomalie-dati]] · [[calendario]]

Ultimo aggiornamento: 27 ottobre 2026
Regola: qui vanno solo decisioni prese e progressi verificati del team BAD. Le cose del BID stanno in [[contesto-BID]].

## Chi siamo e cosa facciamo
- Team BAD del Laboratorio Integrato ITS (ott–dic 2026), in coppia con il team BID ("Team Redis").
- Team BAD: 5 persone. Fabrizio (Power Apps + supporto al gruppo), Lorenzo, Stefano, Dennis, Ilaria (Ilaria ha task separate decise all'incontro, gestite fuori da questi file).
- Task operative in `task-BAD.md`.
- Perimetro BAD da PDF ufficiale: back-office Power Apps (listino, planimetria, contratti, acconti, prelazione), flussi Power Automate, report Power BI per la direzione, app di scansione allo stand, dati commerciali nel modello condiviso.
- Perimetro BAD (come da divisione proposta dal BID, da confermare): processo commerciale (preventivo → contratto → acconto → prelazione), Power Apps back-office, Power Automate (notifiche e promemoria), Power BI direzionale (5 pagine), solution esportata e versionata in `power-platform/`.

## Calendario
Vedi [[calendario]].

## Decisioni prese
| # | Decisione | Data |
|---|---|---|
| B-01 | Niente Dataverse | ott 2026 |
| B-02 | Database unico PostgreSQL condiviso BAD+BID, in container Docker su Docker Desktop in locale. Costo zero, nessuna VM né cloud a pagamento, niente di pubblico | ott 2026 |
| B-03 | Schema e dati si distribuiscono tramite repo GitHub (pull) | ott 2026 |
| B-04 | Sviluppo Power Platform in ambiente Developer (connettori premium disponibili) | ott 2026 |
| B-05 | Il sito per chi vuole uno stand lo fa il BID; nessun sito per i visitatori | ott 2026 |
| B-06 | Vault Obsidian come "cervello del progetto" | ott 2026 |
| B-07 | Power Platform raggiunge backend/DB locali tramite **on-premises data gateway** (nessuna esposizione pubblica, coerente con B-02). Chiude A-02 | 23/10/2026 |
| B-08 | Power Apps legge e scrive **direttamente su PostgreSQL** (connettore PostgreSQL via gateway), non tramite API Java. Provato con successo sul container Docker. Chiude A-01 e A-03 (Entra ID non serve più per Power Apps). Va comunicato al BID | 24/10/2026 |
| B-09 | Power BI **Service** pubblicato, aggiornato tramite lo stesso gateway, sulle viste `analytics`. Chiude A-04 | 24/10/2026 |
| B-10 | Controlli di avanzamento settimanali il **venerdì** (oltre ai SAL). Dal 16/11 coincidono con lo stato scritto settimanale al cliente. Gantt BID+BAD pubblicato come pagina web; le date BID sono stimate dal loro piano | 26/10/2026 |
| B-11 | Il vault contiene tre file a proprietario unico: `contesto-BAD` (lo modifica il BAD), `contesto-BID` (lo modifica il BID), `decisioni-condivise` (si scrive solo dopo un accordo). Fabrizio lo prova prima in locale, poi va nel repo in `docs/brain/` | 27/10/2026 |

Risorse: 71 € di crediti Azure (non ancora usati).

## Decisioni aperte (da prendere insieme al BID)
| # | Questione | Perché è aperta |
|---|---|---|
| A-05 | Confermare la divisione dei compiti proposta dal BID | Documento `divisione-bid-bad-integrazione.md` del BID |
| A-06 | Su quale PC gira il gateway (deve restare acceso durante sviluppo e demo, stesso PC/rete del DB)? | Conseguenza di B-07 |
| A-07 | App di scansione allo stand: BAD (Power Apps, come da PDF) o BID (PWA Angular, come da loro documento)? | Conflitto tra PDF ufficiale e divisione del BID |
| A-08 | Con B-08 le regole commerciali non passano dal backend: quali le garantisce già il DB (vincoli V1) e quali deve controllare Power Apps? | Conseguenza di B-08, da concordare col BID |
| A-09 | Chi collega gli 88 contratti 2024 ai codici espositore (`id_espositore`) e con che metodo? Opzioni: BAD con tabella di corrispondenza (match esatto sul nome normalizzato + casi manuali), oppure BID nel suo ETL | I contratti 2024 in `ARCADE_Commerciale.xlsx` non hanno `id_espositore` né partita IVA, solo la ragione sociale sporca. Il match esatto ne aggancia 79 su 88; i 9 restanti hanno nomi con piccole differenze. Il PDF assegna al BAD la "fornitura dei dati commerciali al modello condiviso". Serve per la domanda "quali espositori tornano e quali perdiamo". **Non deciso (26/10)** |

## Progressi
| Data | Cosa | Stato |
|---|---|---|
| 23/10 | Ricevuta progettazione BID (schema DB V1–V4, divisione compiti, domande cliente) | Letta, da revisionare prima del 30/10 |
| 23/10 | Decisa connessione tramite on-premises data gateway (B-07) | Deciso, non ancora installato |
| 24/10 | Test connessione Power Apps → PostgreSQL in Docker | Riuscito |
| 24/10 | Redatte le task BAD per Power Apps, Power Automate, Power BI (`task-BAD.md`) | Bozza |
| 26/10 | Profilati i 6 CSV grezzi (biglietteria, tornelli, contatti e visite stand) e `ARCADE_Commerciale.xlsx`. Anomalie in [[anomalie-dati]]. Il file commerciale ha totali coerenti con il brief (2025: 821.731 €, 2024: 706.310 €) | Fatto, elenco anomalie da consegnare al BID |
| 27/10 | Preparato il vault con i contesti BAD e BID (B-11) | In prova in locale |

## Note sui dati commerciali (verificate il 26/10, non sono decisioni)
- Pagamenti: nel file ci sono solo date, nessun importo. Acconto 30% e saldo 70% restano assunzioni da confermare col cliente.
- `acconto_scadenza` cade 15 giorni dopo la firma, mentre il listino dice "acconto alla firma": da chiedere al cliente.
- Nessuna doppia vendita, importi e maggiorazioni coerenti con la planimetria.
- Le altre anomalie del file commerciale sono in [[anomalie-dati]] (A-007 → A-011).

## Prossimi passi BAD (dal piano condiviso, non ancora avviati)
- Revisionare lo schema V1–V4 prima del congelamento del 30/10.
- Documentare il processo commerciale con gli stati (bozza → confermato → contratto → acconto → saldo).
- Rispondere alle domande interne T1–T4 del BID (tenant, licenze, hosting, autenticazione).

# Migrazioni del team BAD (database `arcade`)

Script SQL scritti dal team BAD ed eseguiti sul database ufficiale `metiserver2` (Azure, B-17)
**dopo** le migrazioni V1–V5 del BID. Solo funzioni, trigger, viste e schemi del BAD:
nessuna colonna o vincolo cambiato nelle tabelle del BID, salvo dove indicato (chiavi in V8/V9).

## Attenzione alla numerazione

- Questa cartella **non** è `database/migrations` del BID e **non va copiata lì**: quella cartella
  la esegue il Docker del BID in ordine alfabetico, e `V10__…`–`V15__…` verrebbero eseguite prima di `V2__…`.
- La **V6 di questa cartella** (`V6__ingest_commercial.sql`) **non è** la V6 del BID
  (`V6__commercial_idempotency_and_reservation.sql`, 16/11): stesso numero, contenuto diverso.
  La numerazione comune va concordata con il BID.

## Ordine di esecuzione (come sul server)

Prima le migrazioni del BID `V1`–`V5` (`database/migrations`), poi:

| File | Cosa fa | Richiede |
|---|---|---|
| `V6__ingest_commercial.sql` | Caricatore dell'Excel commerciale (`dq.load_commercial_batch`, `dq.norm_company`, `dq.try_bool`) | V1–V5 |
| `V7__ingest_stand_leads.sql` | Caricatore dei contatti stand: email solo come hash con il sale passato a runtime, minorenni in `PRIVACY_REVIEW` | V1–V5 |
| `V8__power_apps_identity.sql` | Chiavi compatibili con il connettore di Power Apps / Power Automate (chiave 0 → numero dalla sequenza) su 8 tabelle | V1 |
| `V9__power_apps_exhibitor.sql` | Come V8 per espositori e referenti, più calcolo di `legal_name_norm` | V6, V8 |
| `V10__flow_views.sql` | Schema `flow`: viste dei promemoria (pagamenti, prelazioni) per Power Automate | V1–V4 |
| `V11__sensor_cameras.sql` | Schema `sensor`: telecamere di conteggio simulate, una per stand | V1–V3 |
| `V12__live_views.sql` | Schema `live`: viste della schermata Live | V11 |
| `V13__live_map.sql` | Vista dei dati della Mappa3D | V11, V12 |
| `V14__live_tables.sql` | Copie delle viste Live leggibili da Power Apps, aggiornate da un trigger | V11–V13 |
| `V15__lead_inbox.sql` | Tabella di ingresso dei contatti dal modulo QR; l'hash dell'email lo calcola il DB | V8, V10 |

Prova del 28/11: V1–V5 del BID + V6–V15 eseguite in quest'ordine su un database PostgreSQL 16 vuoto, senza errori.

## Come eseguirle da Windows

```powershell
$env:PGCLIENTENCODING = "UTF8"
& "$env:LOCALAPPDATA\Programs\pgAdmin 4\runtime\psql.exe" `
  "host=metiserver2.postgres.database.azure.com dbname=arcade user=arcadeadmin sslmode=require" `
  -v ON_ERROR_STOP=1 -f V8__power_apps_identity.sql
```

Senza `PGCLIENTENCODING = "UTF8"` psql legge i file con la codifica della console e storpia le lettere accentate.

## Segreti

Nessun file contiene password o il **sale** dei contatti. V7 lo riceve a runtime;
per V15 si inserisce a parte in `flow.app_secret` (istruzioni in fondo al file). Non committarlo mai.

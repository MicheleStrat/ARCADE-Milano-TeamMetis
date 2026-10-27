# Come usare il vault del progetto

Guida rapida per BAD e BID. Leggila una volta, ci vogliono 5 minuti.

## Cos'è
`docs/brain/` (sul branch `main`) è il "cervello del progetto": una cartella di note markdown collegate tra loro. Le apriamo con **Obsidian**, un editor gratuito che mostra i link tra le note e il grafo dei collegamenti. Sotto sono normali file `.md`, quindi li legge anche Claude (o qualsiasi altro assistente) senza bisogno di copiarli a mano.

Scopo: le decisioni di **entrambi** i team stanno in un posto solo e aggiornato. Niente più file di contesto copiati e ricopiati che invecchiano.

## Chi scrive dove
| File | Proprietario | Regola |
|------|-------------|--------|
| `contesto-BAD.md` | BAD | lo modifica solo il BAD |
| `contesto-BID.md` | BID | lo modifica solo il BID |
| `decisioni-condivise.md` | entrambi | si scrive solo dopo un accordo tra i due team, durante il controllo del venerdì |

Tutti leggono tutto. Prima di proporre qualcosa, controlla che non vada contro una decisione presente in questi tre file.

Gli altri file (`kpi`, `anomalie-dati`, `glossario`, `calendario`) sono di supporto e li aggiorna chi ha l'informazione.

⚠️ **Per il BID:** la prima versione di `contesto-BID.md` l'ha ricostruita il BAD dal vostro zip del 23/10. **Rileggetela e correggetela**: da qui in avanti è vostra.

## Setup (una volta sola)

### 1. Installa Obsidian
Da obsidian.md, gratis, nessun account. Il "Sync" a pagamento non serve: sincronizziamo con Git.

### 2. Tieni `main` in una cartella separata
Il vault sta su `main`, ma ognuno lavora sul branch del proprio team. Se fai `git checkout BID`, la cartella `docs/brain` sparisce e Obsidian resta vuoto. Per evitarlo, crea una seconda cartella fissa su `main` con `git worktree`. Dalla cartella del repo:

```bash
git fetch origin
git worktree add ../arcade-brain main
```

Ora hai due cartelle: quella del repo, dove lavori sul tuo branch, e `../arcade-brain`, sempre su `main`. Così il vault c'è sempre.

### 3. Apri il vault
In Obsidian scegli "Open folder as vault" e seleziona `arcade-brain/docs/brain`. Parti da `00-indice`.

La cartella `.obsidian` (impostazioni personali) è nel `.gitignore`: ognuno ha la sua.

## Uso quotidiano

**Prima di lavorare**, aggiorna il vault:
```bash
cd ../arcade-brain
git pull
```

**Dopo una modifica**, mandala su:
```bash
cd ../arcade-brain
git add docs/brain
git commit -m "contesto-BID: <cosa hai cambiato>"
git push origin main
```

Se ti dimentichi il pull, l'altro team lavora su decisioni vecchie. È l'unica regola che conta davvero.

**Quando si decide qualcosa:** aggiungi una riga alla tabella delle decisioni nel tuo file di contesto (es. `R-09`, data, decisione). Se una decisione cambia, non cancellarla: segnala come **superata** e aggiungi la nuova.

**Al controllo del venerdì:** aprite insieme `decisioni-condivise` e scorrete la tabella "Da concordare". Una persona sola la aggiorna durante l'incontro e fa push alla fine.

## Scorciatoie utili in Obsidian
- Clic su `[[nome-nota]]` → apre la nota
- `Ctrl+E` → passa da modifica a lettura (le tabelle si vedono formattate)
- `Ctrl+G` → grafo delle note
- Scrivere `[[nuova-nota]]` e cliccarci → crea una nota già collegata

## Usarlo con Claude
Prima di chiedere qualcosa sul progetto, fai leggere a Claude `00-indice.md`, `contesto-BAD.md`, `contesto-BID.md` e `decisioni-condivise.md`. Con Claude Code aperto sulla cartella `arcade-brain` li legge direttamente dal disco. Così parte dalle stesse decisioni per tutti e due i team.

## Regole sui dati
- **Niente righe dei dataset del cliente nel vault.** I nomi sono inventati, ma il brief chiede di trattarli come dati personali. Descrivi le anomalie (tipo, quante), non copiarle.
- Il repo è **pubblico** finché non viene reso privato: non scrivere nel vault niente che non pubblicheresti.

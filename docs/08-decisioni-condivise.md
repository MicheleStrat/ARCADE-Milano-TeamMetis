# Decisioni condivise BID / BAD

Registro delle decisioni che toccano sia il BID sia il BAD. Ogni voce riporta data, decisione, motivo e cosa è stato verificato.

## B1 — Come Power Apps e Power BI accedono ai dati

**Data:** 13 novembre 2026 · **Responsabile:** Mattia Billong (team leader BID)

**Stato:** concordata con il BAD.

**Contesto.** Il BAD aveva scelto l'accesso diretto a PostgreSQL (B-08); il BID aveva deciso di passare solo dalle API (R-03).

**Decisione.**

1. **Scritture e regole di business** (preventivi, contratti, acconti, anti-doppia vendita, importi, stati): **solo tramite API**. Power Apps le richiama con un connettore personalizzato generato da `docs/api/openapi.yaml`. Nessuna scrittura diretta sul database.
2. **Letture per le dashboard BI**: il BAD può leggere **direttamente da PostgreSQL** con il ruolo `arcade_bi`, in sola lettura e **solo sullo schema `analytics`**.

**Motivo.** Il BAD mantiene l'accesso diretto che aveva scelto per le dashboard. Il BID mantiene il controllo di tutto ciò che modifica i dati, quindi vincoli, audit e autorizzazioni non vengono aggirati.

**Cosa può fare `arcade_bi`** (verificato il 13/11/2026 sul database locale, copia dei dati Azure):

- usa solo lo schema `analytics` e legge tutte le 29 viste;
- non ha nessun permesso di scrittura;
- non ha accesso a `core`, `staging`, `dq`, `portal` (prova: `SELECT` su `core.exhibitor` rifiutato).

**Dati per singola riga visibili al BAD:** letture ai tornelli con `ticket_code` (`fact_gate_reading`), biglietti (`fact_ticket`) e contatti raccolti (`fact_stand_lead`). Le viste non contengono email né hash e usano la fascia d'età, non l'età. Per email e minorenni la decisione è quella già presa: si trattano con gli hash.

**Limiti noti.**

- Le viste `analytics` girano con i diritti del proprietario e bypassano la sicurezza per riga: `arcade_bi` vede **tutti** gli espositori. Va bene per le dashboard dello staff; **non** si usa Power BI per mostrare dati a un singolo espositore (per quello c'è il portale, via API).
- Il permesso vale per le viste esistenti. Ogni vista nuova in `analytics` richiede un `GRANT SELECT` a `arcade_bi`.

**Da fare / non verificato.**

- Creare l'account di login (es. `arcade_powerbi`, `IN ROLE arcade_bi`) sul server Azure, con la password fuori dal repository. Oggi `arcade_bi` è un gruppo senza login.
- Verificare che il server Azure abbia gli stessi permessi del database locale.
- Il connettore PostgreSQL di Power Apps/Power BI richiede una licenza premium e, se il database non è pubblico, un gateway. Non sono stati verificati.
- L'importazione del contratto OpenAPI in Power Platform non è stata provata.

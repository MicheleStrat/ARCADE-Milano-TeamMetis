# ARCADE Milano — Indice della documentazione

Ultimo aggiornamento: 23 ottobre 2026

Questo progetto è formativo: Factory Studios (cliente fittizio) organizza ARCADE Milano, un festival del videogioco. La piattaforma unisce vendita degli stand, dati di biglietteria/tornelli/stand e report per espositori e direzione.

## Come leggere questi file

| File | A cosa serve | Quando leggerlo |
|---|---|---|
| [01-lavoro-svolto.md](01-lavoro-svolto.md) | Cronologia di **tutto ciò che è stato fatto**, con motivazioni e risultati reali | Per capire a che punto siamo |
| [02-guida-database.md](02-guida-database.md) | Spiegazione semplice del database, **come avviarlo e provarlo** | Per usarlo o spiegarlo |
| [03-lavoro-futuro.md](03-lavoro-futuro.md) | **Cosa resta da fare**, in ordine, con scadenze e responsabilità BID/BAD | Per pianificare |
| [04-domande-cliente.md](04-domande-cliente.md) | **Domande per il cliente** al kickoff, ordinate per priorità, con assunzioni di lavoro | Per preparare la riunione |
| [data-model.md](data-model.md) | Progettazione tecnica completa del modello dati (tabelle, KPI, sicurezza, domande al cliente) | Documento di riferimento |
| [../divisione-bid-bad-integrazione.md](../divisione-bid-bad-integrazione.md) | Chi fa cosa (BID/BAD) e come si collegano Power Apps, Java, Angular e database | Per il coordinamento tra i due team |

## Stato in una riga

Il **database PostgreSQL è progettato, scritto e provato** con dati di prova; **non è ancora stato caricato nessun dato reale del cliente** e backend, ETL, frontend, Power Apps, Power Automate e Power BI **non esistono ancora**.

## Glossario veloce

| Termine | Significato |
|---|---|
| **BID** | Chi sviluppa in codice: PostgreSQL, Java/Spring Boot, ETL, Angular |
| **BAD** | Chi sviluppa su Power Platform: Power Apps, Power Automate, Power BI |
| **ETL** | Caricamento dei file del cliente nel database (leggi, controlla, trasforma, salva) |
| **Staging** | Area dove i file vengono copiati “così come sono” prima dei controlli |
| **Anomalia** | Un dato sospetto o sbagliato: viene registrato, mai nascosto |
| **RLS** | Row Level Security: il database stesso limita le righe visibili a ogni utente |
| **KPI** | Indicatore di performance (es. ricavo per metro quadrato) |
| **SAL** | Stato avanzamento lavori: 30/10 (SAL 1) e 13/11 (SAL 2) |

## Cartelle del progetto

```
Progetto Team Redis/
├── divisione-bid-bad-integrazione.md
├── docs/                      ← questi file
└── database/
    ├── migrations/            ← V1..V4: lo schema vero e proprio
    └── tests/                 ← script di prova (SQL)
```

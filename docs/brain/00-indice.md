# ARCADE Milano – Cervello del progetto

Punto di partenza. Ogni nota importante è linkata da qui.

## Chi scrive dove
| File | Proprietario | Regola |
|------|-------------|--------|
| [[contesto-BAD]] | team BAD | lo modifica solo il BAD |
| [[contesto-BID]] | team BID | lo modifica solo il BID |
| [[decisioni-condivise]] | entrambi | si scrive solo dopo un accordo tra i due team |

Tutti leggono tutto. Prima di proporre qualcosa, controlla che non contraddica una decisione in questi tre file.

## Note di supporto
- [[kpi]] – definizioni degli indicatori da concordare col cliente
- [[anomalie-dati]] – errori trovati nei dati e come li gestiamo
- [[glossario]] – termini del progetto
- [[calendario]] – date chiave, SAL e controlli settimanali

## Contesto in breve
Factory Studios organizza ARCADE Milano (fiera videogioco e cultura pop, 3 padiglioni, 110 espositori nel 2025, ~54.600 presenze). Prossima edizione 18–20 dicembre 2026, 130 stand.
Il cliente vuole una piattaforma che faccia due cose: **vendere meglio** spazi e sponsorizzazioni, **capire i numeri** (biglietti, ingressi, visite agli stand).

- **BAD**: processo commerciale, Power Apps back-office, Power Automate, Power BI direzionale
- **BID**: PostgreSQL, backend Java Spring Boot, ETL, frontend Angular
- App di scansione allo stand: assegnazione ancora aperta (A-07 in [[contesto-BAD]])

Punto d'incontro: il database PostgreSQL condiviso.

## Requisiti trasversali (non negoziabili)
- I numeri devono tornare tra le diverse viste
- Le anomalie dei dati vanno trovate e gestite → [[anomalie-dati]]
- Gli espositori non vedono i dati dei concorrenti
- I dati dei minori vanno tutelati
- Chiunque nel team deve saper spiegare ogni riga consegnata

## Regola del vault
Niente righe dei dataset qui dentro: i nomi sono inventati ma vanno trattati come dati personali.

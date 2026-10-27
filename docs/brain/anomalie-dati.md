# Anomalie dei dati

Il cliente avvisa: i file arrivano da sistemi diversi e hanno gli errori dei dati veri. Trovarli e gestirli è un criterio di valutazione.
Il BID le registra nel database in `dq.anomaly` e i record dubbi in `dq.quarantine` (R-08): nessun dato si scarta in silenzio.

Formato: descrivi il tipo di errore, NON copiare le righe.

## Trovate dal BAD (profilazione del 26/10)
| ID | File | Tipo di anomalia | Quante | Come la gestiamo |
|----|------|------------------|--------|------------------|
| A-001 | CSV 2024 vs 2025 | formati diversi tra le due edizioni | | da concordare col BID |
| A-002 | tornelli 2025 | orari in UTC | | da concordare col BID |
| A-003 | tornelli | codici tornello orfani | 35 per anno | da concordare col BID |
| A-004 | CSV | province scritte in più forme | | da concordare col BID |
| A-005 | visite stand | outlier con 912 scansioni | 1 | da concordare col BID |
| A-006 | contatti stand | contatti minorenni | 14 | tutela minori, in revisione dal BID (R-06) |
| A-007 | commerciale | acconto non pagato | 8 contratti | da chiedere al cliente |
| A-008 | commerciale | saldo non pagato | 8 contratti | da chiedere al cliente |
| A-009 | commerciale | saldo pagato prima dell'acconto | 2 contratti | da chiedere al cliente |
| A-010 | commerciale | partita IVA 2025 diversa dall'anagrafica | 110 righe | probabile formattazione, da verificare |
| A-011 | commerciale | contratti 2024 senza `id_espositore` né partita IVA | 88 (9 non agganciabili con match esatto) | aperto, vedi A-09 in [[contesto-BAD]] |

Stato: elenco ancora da consegnare al BID.

Collegamenti: [[decisioni-condivise]], [[kpi]]

# BID-01 · Task 1 — Esame dei file di biglietteria, tornelli e visite agli stand

> Task: *Esaminare i file di biglietteria, letture ai tornelli e visite agli stand.*
> Metodo: lettura integrale dei file originali, senza modifiche. Il repository `ARCADE-Milano-TeamMetis` non è presente in questo workspace: l'esame riguarda solo i file caricati nel progetto.

## 1. Inventario dei file

| File | Righe di dati | Separatore | Codifica / fine riga | Colonne | Una riga rappresenta |
|---|---|---|---|---|---|
| `biglietteria_2024.csv` | 35.719 | `;` | ASCII | 11 | un biglietto venduto |
| `biglietteria_2025.csv` | 42.556 | `;` | UTF-8 | 11 | un biglietto venduto |
| `tornelli_2024.csv` | 46.824 | `;` | ASCII, CRLF | 5 | una lettura a un varco |
| `tornelli_2025.csv` | 55.992 | `,` | ASCII | 4 | una lettura a un varco |
| `visite_stand_2025.csv` | 2.451 | `,` | ASCII | 4 | scansioni di uno stand in un'ora |
| `contatti_stand_2025.csv` | 1.707 | `,` | ASCII | 9 | un contatto raccolto da uno stand |
| `ARCADE_Commerciale.xlsx` | 6 fogli (135 · 130 · 20 · 198 · 950 righe) | — | Excel | vedi doc. 02 | anagrafica, planimetria, listino, contratti |

**Quadratura con il brief:** biglietteria 35.719 + 42.556 = 78.275 righe (brief: "circa 78.000"); tornelli 46.824 + 55.992 = 102.816 passaggi (brief: "circa 103.000"). I volumi dichiarati e quelli ricevuti coincidono.

**Non ricevuti:** visite agli stand 2024, contatti 2024, qualsiasi dato di uscita dai varchi.

## 2. Biglietteria

| | 2024 | 2025 |
|---|---|---|
| Ordini | 21.500 | 25.500 |
| Biglietti (righe) | 35.719 | 42.556 |
| Persone (somma di `Persone`) | 42.979 | 51.259 |
| Periodo di acquisto | 03/07–22/12/2024 | 02/07–21/12/2025 |
| Giorni di validità | 20, 21, 22/12/2024 + abbonamento 3 giorni | 19, 20, 21/12/2025 + abbonamento 3 giorni |
| Canali | Online 25.136 · Cassa 6.939 · Rivenditore partner 3.644 | Online 29.776 · Cassa 8.570 · Rivenditore partner 4.210 |

**Tipi di biglietto** (otto per edizione, con nomi diversi):

| 2024 | n | 2025 | n |
|---|---|---|---|
| Intero | 17.891 | Giornaliero intero | 21.302 |
| Abb. 3gg | 5.602 | Abbonamento 3 giorni | 6.815 |
| Ridotto | 4.891 | Giornaliero ridotto 8-14 anni | 5.703 |
| Family | 2.420 | Family 2 adulti + 2 ragazzi | 2.901 |
| Omaggio U8 | 2.069 | Gratuito under 8 | 2.414 |
| Business | 1.322 | Business Day (venerdì mattina) | 1.663 |
| VIP | 1.222 | VIP Experience | 1.468 |
| Stampa | 302 | Accredito stampa | 290 |

Il Business è valido solo il primo giorno (venerdì). Codici sconto: `EARLY10` (−10% sul prezzo), `SCUOLA` e `STUDENTI` (prezzo invariato).

**Che cosa significa:** una riga di biglietteria è un **biglietto**, non una persona: i Family valgono 4 persone, e gli abbonamenti valgono tre giorni.

## 3. Tornelli

| | 2024 | 2025 |
|---|---|---|
| Letture | 46.824 | 55.992 |
| Accettate / respinte | 46.594 / 230 | 55.736 / 256 |
| Giorni | 20–22/12/2024 | 19–21/12/2025 |
| Orario delle letture | 09:00–17:30 (ora locale assunta) | 09:00–17:30 (UTC convertito in ora locale) |
| Varchi | P1 Nord, P1 Sud, P2 Ovest, P3 Est | P1-Nord, P1-Sud, P2-Ovest, P3-Est |
| Letture per varco | P1 Nord 18.737 · P1 Sud 14.048 · P2 Ovest 9.277 · P3 Est 4.762 | P1-Nord 22.300 · P1-Sud 16.765 · P2-Ovest 11.210 · P3-Est 5.717 |
| Biglietti distinti entrati | 34.447 | 41.041 |

Il giorno di punta è sabato in entrambe le edizioni: 2024 = 21/12 (18.044 letture), 2025 = 20/12 (21.823).

**Che cosa significa:** il file registra **solo ingressi**; non esistono uscite. Il varco indica il padiglione di accesso. Ci sono tre misure diverse che il brief chiama "numeri": biglietti venduti, letture ai varchi e persone: vanno definite separatamente.

## 4. Visite e contatti agli stand (solo 2025)

| | Visite | Contatti |
|---|---|---|
| Righe | 2.451 | 1.707 |
| Stand coinvolti | 84 (su 130 in planimetria, 110 con contratto) | 84 |
| Periodo | 19–21/12/2025, ore 09:00–18:00 (una riga a 08:00) | 19–21/12/2025, 09:31–18:49 |
| Totali | 36.213 scansioni (35.301 escluse le 912 delle 08:00) | 1.707 contatti, 1.688 e-mail distinte |
| Granularità | conteggio orario per stand | evento singolo con età, provincia, interesse e consenso |

Scansioni per padiglione: P1 25.010 · P2 5.092 · P3 6.111. Contatti: 14-17 anni 14; 18-24 666; 25-34 626; 35-44 236; 45+ 165. Interesse: beta test 365, newsletter 346, evento 339, prodotto 331, lavoro/stage 326.

**Che cosa significa:** le visite sono **conteggi aggregati per ora**, non visitatori identificati. I contatti sono eventi nominali (con e-mail) e non si collegano né a un biglietto né a una scansione.

## 5. Primo esito dell'esame

1. I file di biglietteria hanno la stessa struttura nei due anni; i tornelli no (formato, fuso, nomi dei varchi, esito).
2. Il 2024 non ha dati stand; il 2025 non ha le uscite: questi limiti restano per tutta l'analisi.
3. Dati personali presenti: e-mail nei contatti; fascia d'età, provincia nei biglietti; circa il 36% dei biglietti è di minori (0-17).
4. Le anomalie e le relazioni sono analizzate nei documenti **02** (struttura e relazioni) e **03** (duplicati, nulli, date, riferimenti).

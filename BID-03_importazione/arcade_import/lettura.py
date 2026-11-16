"""Lettura dei file sorgente e piccoli strumenti di validazione condivisi dagli importatori."""
import csv
import io
from pathlib import Path

import pandas as pd

from .core import FileNonValido, Raccolta


def leggi_csv(percorso: Path, sep: str, colonne_obbligatorie, rac: Raccolta, tabella: str):
    """Legge un CSV come testo. Ritorna (DataFrame con colonna 'z_riga', righe_lette, colonne_file).
    Righe con numero di campi errato -> SCARTATO R-F05 (contenuto grezzo conservato nell'anomalia)."""
    try:
        testo = Path(percorso).read_bytes().decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise FileNonValido(f"File non leggibile come UTF-8: {e}") from e
    lettore = csv.reader(io.StringIO(testo, newline=""), delimiter=sep)
    try:
        intestazione = [c.strip() for c in next(lettore)]
    except StopIteration:
        raise FileNonValido("File vuoto") from None
    mancanti = [c for c in colonne_obbligatorie if c not in intestazione]
    if mancanti:
        raise FileNonValido(f"Colonne obbligatorie mancanti: {mancanti}. Trovate: {intestazione}")
    righe, lette = [], 0
    for riga in lettore:
        if not riga:       # riga vuota: non e' un record
            continue
        lette += 1
        n = lettore.line_num
        if len(riga) != len(intestazione):
            rac.blocca("R-F05", "SCARTATO", tabella, n, None,
                       {"motivo": f"{len(riga)} campi invece di {len(intestazione)}", "riga_grezza": sep.join(riga)[:500]})
            continue
        righe.append([*riga, n])
    df = pd.DataFrame(righe, columns=[*intestazione, "z_riga"])
    return df, lette, intestazione


def _json(v):
    """Valore originale in forma serializzabile (le anomalie conservano il record cosi' come e' arrivato)."""
    if v is None or (not isinstance(v, str) and pd.isna(v)):
        return None
    if isinstance(v, pd.Timestamp):
        return v.isoformat()
    return v.item() if hasattr(v, "item") else v


def grezzo(r, colonne):
    return {c: _json(getattr(r, c)) for c in colonne}


def blocca_se(rac, df, maschera, regola, esito, tabella, chiave, motivo, colonne):
    """Registra come anomalia (per riga) i record che soddisfano `maschera` e li toglie da df."""
    maschera = pd.Series(list(maschera), index=df.index, dtype=bool)
    for r in df[maschera].itertuples():
        rac.blocca(regola, esito, tabella, int(r.z_riga), getattr(r, chiave) if chiave else None,
                   {"motivo": motivo, "record": grezzo(r, colonne)})
    return df[~maschera]


def doppioni(rac, df, chiave, confronto, regola, tabella, col_chiave, msg_identica, msg_diversa, colonne):
    """Righe con la stessa chiave: la prima resta. Le successive identiche (su `confronto`) sono SCARTATE, quelle con valori
    diversi vanno in QUARANTENA: in entrambi i casi restano tracciate nel registro delle anomalie."""
    dup = df.duplicated(chiave, keep="first")
    esatto = dup & df.duplicated(confronto, keep="first")
    diverso = dup & ~esatto
    df = blocca_se(rac, df, esatto, regola, "SCARTATO", tabella, col_chiave, msg_identica, colonne)
    return blocca_se(rac, df, diverso.loc[df.index], regola, "QUARANTENA", tabella, col_chiave, msg_diversa, colonne)

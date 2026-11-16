"""Nucleo della pipeline: registro delle importazioni, caricamento idempotente, tracciamento delle anomalie.

Flusso (ogni fonte): leggi file -> valida/normalizza (sources.py, senza scrivere nel DB) -> carica in una sola
transazione -> registra conteggi e anomalie. Un errore imprevisto annulla l'intero caricamento e segna l'importazione
'fallita'; i record non validi NON fermano il processo: finiscono in importazione_anomalia.
"""
import hashlib
import json
import os
from dataclasses import dataclass, field
from pathlib import Path

import pandas as pd
import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb

ESEMPI_MAX = 5  # esempi di chiavi nelle anomalie aggregate


class FileNonValido(Exception):
    """File non interpretabile (formato, colonne obbligatorie mancanti): nessun dato viene caricato."""


@dataclass
class Anomalia:
    regola: str
    esito: str                    # CORRETTO | SEGNALATO | QUARANTENA | SCARTATO
    tabella: str | None = None
    chiave: str | None = None
    riga: int | None = None       # riga del file sorgente (1 = intestazione)
    dettaglio: dict = field(default_factory=dict)


class Raccolta:
    """Accumula le anomalie di un'importazione. Le regole 'di massa' (correzioni deterministiche e segnalazioni
    informative) sono aggregate in una sola riga con conteggio ed esempi; quarantene e scarti sono sempre per-riga."""

    def __init__(self):
        self.anomalie: list[Anomalia] = []
        self._aggr: dict[tuple, dict] = {}
        self.righe_corrette: set[int] = set()
        self.righe_segnalate: set[int] = set()
        self.righe_quarantena: set[int] = set()
        self.righe_scartate: set[int] = set()

    def aggrega(self, regola, esito, tabella, riga, chiave, descrizione):
        a = self._aggr.setdefault((regola, esito, tabella), {"descrizione": descrizione, "righe": 0, "esempi": []})
        a["righe"] += 1
        if len(a["esempi"]) < ESEMPI_MAX:
            a["esempi"].append({"riga": riga, "chiave": chiave})
        (self.righe_corrette if esito == "CORRETTO" else self.righe_segnalate).add((tabella, riga))

    def blocca(self, regola, esito, tabella, riga, chiave, dettaglio):
        assert esito in ("QUARANTENA", "SCARTATO")
        self.anomalie.append(Anomalia(regola, esito, tabella, chiave, riga, dettaglio))
        (self.righe_quarantena if esito == "QUARANTENA" else self.righe_scartate).add((tabella, riga))

    def tutte(self):
        extra = [Anomalia(r, e, t, None, None, d) for (r, e, t), d in self._aggr.items()]
        return extra + self.anomalie


@dataclass
class Preparato:
    """Risultato della fase di validazione: tabelle pronte da caricare (in ordine di dipendenza)."""
    tabelle: dict                 # nome tabella -> DataFrame (colonne = colonne del DB, senza importazione_id)
    chiavi: dict                  # nome tabella -> lista colonne chiave naturale
    raccolta: Raccolta
    righe_lette: int
    nota: dict = field(default_factory=dict)


# ------------------------------------------------------------------ connessione e registro
def connetti():
    """Connessione da variabili d'ambiente PostgreSQL standard (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE).
    Nessuna credenziale nel codice."""
    return psycopg.connect(os.environ.get("ARCADE_DSN", ""), autocommit=False)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blocco in iter(lambda: f.read(1 << 20), b""):
            h.update(blocco)
    return h.hexdigest()


def _scrivi_serie(df: pd.DataFrame):
    return df.astype(object).where(df.notna(), None)


def carica_tabella(cur, tabella, df, chiave, importazione_id):
    """Carica df in arcade.<tabella> in modo idempotente. Ritorna (nuove, gia_presenti, conflitti[Anomalia]).

    - riga con chiave nuova -> inserita;
    - riga con chiave gia' presente e valori identici -> ignorata (conta come 'gia' presente');
    - riga con chiave gia' presente e valori DIVERSI -> NON applicata, segnalata (l'aggiornamento richiede una
      regola concordata: vedi punto da concordare C13).
    """
    if df.empty:
        return 0, 0, []
    cols = list(df.columns)
    ident = sql.Identifier
    tab = sql.SQL("arcade.") + ident(tabella)
    cur.execute(sql.SQL("CREATE TEMP TABLE _stg ON COMMIT DROP AS SELECT {c} FROM {t} WITH NO DATA")
                .format(c=sql.SQL(", ").join(map(ident, cols)), t=tab))
    with cur.copy(sql.SQL("COPY _stg ({c}) FROM STDIN").format(c=sql.SQL(", ").join(map(ident, cols)))) as cp:
        for riga in _scrivi_serie(df).itertuples(index=False, name=None):
            cp.write_row(riga)
    join = sql.SQL(" AND ").join(sql.SQL("t.{c} = s.{c}").format(c=ident(c)) for c in chiave)
    altri = [c for c in cols if c not in chiave]
    diverso = sql.SQL(" OR ").join(sql.SQL("t.{c} IS DISTINCT FROM s.{c}").format(c=ident(c)) for c in altri) \
        if altri else sql.SQL("false")
    cur.execute(sql.SQL("SELECT count(*) FROM _stg s JOIN {t} t ON {j} WHERE NOT ({d})")
                .format(t=tab, j=join, d=diverso))
    gia = cur.fetchone()[0]
    cur.execute(sql.SQL("SELECT to_jsonb(s), to_jsonb(t) FROM _stg s JOIN {t} t ON {j} WHERE {d}")
                .format(t=tab, j=join, d=diverso))
    conflitti = []
    for s, t in cur.fetchall():
        k = "|".join(str(s[c]) for c in chiave)
        diff = {c: {"file": s[c], "database": t[c]} for c in altri if s[c] != t[c]}
        conflitti.append(Anomalia("R-X02", "SEGNALATO", tabella, k, None,
                                  {"motivo": "chiave gia' presente con valori diversi: non aggiornata", "differenze": diff}))
    # La provenienza (importazione_id) e' registrata solo dalle tabelle che hanno la colonna (V004/V005); le tabelle
    # commerciali (V003) non la prevedono: la tracciabilita' resta nel registro importazione/importazione_anomalia.
    cur.execute("SELECT 1 FROM information_schema.columns WHERE table_schema='arcade' AND table_name=%s AND column_name='importazione_id'", (tabella,))
    prov = cur.fetchone() is not None
    ins_cols = sql.SQL(", ").join(map(ident, cols + (["importazione_id"] if prov else [])))
    sel_cols = sql.SQL(", ").join([sql.SQL("s.") + ident(c) for c in cols] + ([sql.Literal(importazione_id)] if prov else []))
    cur.execute(sql.SQL("INSERT INTO {t} ({i}) SELECT {s} FROM _stg s WHERE NOT EXISTS (SELECT 1 FROM {t} t WHERE {j})")
                .format(t=tab, i=ins_cols, s=sel_cols, j=join))
    nuove = cur.rowcount
    cur.execute("DROP TABLE _stg")
    return nuove, gia, conflitti


def esegui_importazione(fonte, percorso, edizione, preparatore, conn=None):
    """Esegue un'importazione completa. Ritorna un dizionario di esito (stato, id, conteggi)."""
    percorso = Path(percorso)
    chiudi = conn is None
    conn = conn or connetti()
    try:
        h = sha256_file(percorso)
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM arcade.importazione WHERE fonte=%s AND hash_file=%s AND stato='completata'", (fonte, h))
            if (r := cur.fetchone()):
                conn.commit()
                return {"stato": "gia_importato", "importazione_id": r[0],
                        "messaggio": "File identico gia' importato: nessuna modifica."}
            cur.execute("INSERT INTO arcade.importazione (fonte, edizione, nome_file, hash_file) VALUES (%s,%s,%s,%s) RETURNING id",
                        (fonte, edizione, percorso.name, h))
            imp = cur.fetchone()[0]
        conn.commit()  # l'avvio e' registrato anche se il caricamento fallisce
        try:
            return _carica(conn, fonte, percorso, edizione, preparatore, imp)
        except Exception as e:  # annulla tutto il caricamento, conserva traccia del fallimento
            conn.rollback()
            with conn.cursor() as cur:
                cur.execute("UPDATE arcade.importazione SET stato='fallita', terminata_il=now(), note=%s WHERE id=%s",
                            (json.dumps({"errore": f"{type(e).__name__}: {e}"[:2000]}, ensure_ascii=False), imp))
            conn.commit()
            if isinstance(e, FileNonValido):
                return {"stato": "fallita", "importazione_id": imp, "messaggio": str(e)}
            raise
    finally:
        if chiudi:
            conn.close()


def _carica(conn, fonte, percorso, edizione, preparatore, imp):
    with conn.cursor() as cur:
        prep: Preparato = preparatore(cur, percorso, edizione)
        nuove = {}; gia = {}; conflitti = []
        for nome, df in prep.tabelle.items():
            n, g, c = carica_tabella(cur, nome, df, prep.chiavi[nome], imp)
            nuove[nome], gia[nome] = n, g
            conflitti += c
        rac = prep.raccolta
        for c in conflitti:
            rac.anomalie.append(c)
        for a in rac.tutte():
            cur.execute("INSERT INTO arcade.importazione_anomalia (importazione_id, regola, esito, tabella, chiave_record, riga_sorgente, dettaglio)"
                        " VALUES (%s,%s,%s,%s,%s,%s,%s)", (imp, a.regola, a.esito, a.tabella, a.chiave, a.riga, Jsonb(a.dettaglio)))
        q, s = len(rac.righe_quarantena), len(rac.righe_scartate)
        corr = len(rac.righe_corrette - rac.righe_quarantena - rac.righe_scartate)
        segn = len(rac.righe_segnalate - rac.righe_quarantena - rac.righe_scartate) + len(conflitti)
        acc = prep.righe_lette - q - s - corr
        nota = {**prep.nota, "righe_nuove": nuove, "righe_gia_presenti": gia, "conflitti_non_applicati": len(conflitti)}
        cur.execute("UPDATE arcade.importazione SET stato='completata', terminata_il=now(), righe_lette=%s, righe_accettate=%s,"
                    " righe_corrette=%s, righe_segnalate=%s, righe_quarantena=%s, righe_scartate=%s, note=%s WHERE id=%s",
                    (prep.righe_lette, acc, corr, segn, q, s, json.dumps(nota, ensure_ascii=False), imp))
    conn.commit()
    return {"stato": "completata", "importazione_id": imp, "righe_lette": prep.righe_lette, "righe_accettate": acc,
            "righe_corrette": corr, "righe_segnalate": segn, "righe_quarantena": q, "righe_scartate": s,
            "righe_nuove": nuove, "righe_gia_presenti": gia, "conflitti_non_applicati": len(conflitti)}

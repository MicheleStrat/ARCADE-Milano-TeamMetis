"""Collaudo con i file REALI del cliente: crea un database nuovo, applica le migrazioni, esegue tutte le importazioni,
confronta 52 numeri con la profilazione BID-01, riesegue ogni importazione (deve risultare 'gia_importato') e verifica
che nulla cambi. I file reali non sono nel repository: passare la cartella che li contiene.

Uso: python3 collaudo_dati_reali.py <cartella_sorgenti> [<cartella_migrazioni>]   (variabili PG* per la connessione)"""
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import psycopg

RADICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RADICE)); sys.path.insert(0, str(Path(__file__).parent))
from arcade_import.core import esegui_importazione  # noqa: E402
from arcade_import.sources import prepara_biglietteria, prepara_contatti, prepara_tornelli, prepara_visite  # noqa: E402
from arcade_import.sources_commerciale import prepara_commerciale  # noqa: E402
from riscontri_bid01 import CHECKS  # noqa: E402

SRC = Path(sys.argv[1])
MIG = Path(sys.argv[2]) if len(sys.argv) > 2 else RADICE.parent / "BID-02_modello_dati" / "db" / "migrations"
DB = "arcade_collaudo"


def trova(suffisso):
    h = sorted(SRC.glob(f"*{suffisso}"))
    assert len(h) == 1, f"file {suffisso}: trovati {len(h)}"
    return h[0]


with psycopg.connect("dbname=postgres", autocommit=True) as c:
    c.execute(f'DROP DATABASE IF EXISTS "{DB}" WITH (FORCE)'); c.execute(f'CREATE DATABASE "{DB}"')
for f in sorted(MIG.glob("V*.sql")):
    r = subprocess.run(["psql", "-v", "ON_ERROR_STOP=1", "-q", "-1", "-d", DB, "-f", str(f)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
os.environ["ARCADE_DSN"] = f"dbname={DB}"

PIANO = [("commerciale", "ARCADE_Commerciale.xlsx", None, prepara_commerciale),
         ("biglietteria", "biglietteria_2024.csv", 2024, prepara_biglietteria), ("biglietteria", "biglietteria_2025.csv", 2025, prepara_biglietteria),
         ("tornelli", "tornelli_2024.csv", 2024, prepara_tornelli), ("tornelli", "tornelli_2025.csv", 2025, prepara_tornelli),
         ("visite_stand", "visite_stand_2025.csv", 2025, prepara_visite), ("contatti_stand", "contatti_stand_2025.csv", 2025, prepara_contatti)]
print("== Prima esecuzione")
for fonte, nome, ed, prep in PIANO:
    t = time.time()
    e = esegui_importazione(fonte, trova(nome), ed, prep)
    print(f"{fonte:15} {ed or '-':>5}  {e['stato']:11} lette={e.get('righe_lette')} accettate={e.get('righe_accettate')} corrette={e.get('righe_corrette')} "
          f"segnalate={e.get('righe_segnalate')} quarantena={e.get('righe_quarantena')} scartate={e.get('righe_scartate')}  ({time.time() - t:.1f}s)")
    assert e["stato"] == "completata"

TAB = ["espositore", "stand", "contratto", "contratto_riga", "ordine", "biglietto", "lettura_tornello", "visita_stand_oraria", "contatto_stand",
       "importazione", "importazione_anomalia"]
with psycopg.connect(f"dbname={DB}") as conn, conn.cursor() as cur:
    def volumi():
        return {t: cur.execute(f"SELECT count(*) FROM arcade.{t}").fetchone()[0] for t in TAB}
    prima = volumi()
    print("\n== Confronto con i numeri di BID-01")
    fail = 0
    for nome, query, atteso in CHECKS:
        got = str(cur.execute(query).fetchone()[0])
        ok = got == atteso or (re.fullmatch(r"-?\d+(\.\d+)?", got) and abs(float(got) - float(atteso)) < 0.005)
        fail += not ok
        if not ok: print(f"FAIL  {nome}: {got} (atteso {atteso})")
    print(f"{len(CHECKS)} confronti, {len(CHECKS) - fail} coincidenti, {fail} diversi")
    conn.rollback()

print("\n== Seconda esecuzione (idempotenza)")
for fonte, nome, ed, prep in PIANO:
    e = esegui_importazione(fonte, trova(nome), ed, prep)
    assert e["stato"] == "gia_importato", e
with psycopg.connect(f"dbname={DB}") as conn, conn.cursor() as cur:
    dopo = {t: cur.execute(f"SELECT count(*) FROM arcade.{t}").fetchone()[0] for t in TAB}
print("Volumi invariati:", prima == dopo)
print({t: prima[t] for t in TAB})
sys.exit(0 if (fail == 0 and prima == dopo) else 1)

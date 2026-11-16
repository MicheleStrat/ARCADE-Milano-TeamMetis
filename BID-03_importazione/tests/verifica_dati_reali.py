"""Confronta il contenuto del database (dopo le importazioni dei file reali) con i numeri della profilazione BID-01.
Uso: PGDATABASE=<db> python3 verifica_dati_reali.py"""
import re
import sys
from pathlib import Path

import psycopg

sys.path.insert(0, str(Path(__file__).parent))
from riscontri_bid01 import CHECKS  # noqa: E402

fail = 0
with psycopg.connect("") as conn, conn.cursor() as cur:
    for nome, query, atteso in CHECKS:
        cur.execute(query)
        got = str(cur.fetchone()[0])
        ok = got == atteso or (re.fullmatch(r"-?\d+(\.\d+)?", got) and abs(float(got) - float(atteso)) < 0.005)
        fail += not ok
        print(f"{'PASS' if ok else 'FAIL'}  {nome}: {got}" + ("" if ok else f"  (atteso {atteso})"))
print(f"\nRIEPILOGO: {len(CHECKS)} confronti, {len(CHECKS) - fail} coincidenti, {fail} diversi")
sys.exit(1 if fail else 0)

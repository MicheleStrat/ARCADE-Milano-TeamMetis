"""Fixture dei test: ogni test usa un database nuovo, clonato da un modello con le migrazioni gia' applicate.
Richiede un PostgreSQL raggiungibile con le variabili PG* (PGHOST, PGPORT, PGUSER, PGPASSWORD) e il comando psql."""
import os
import subprocess
import uuid
from pathlib import Path

import psycopg
import pytest

RADICE = Path(__file__).resolve().parents[1]


def _migrazioni():
    for p in (os.environ.get("ARCADE_MIGRAZIONI"), RADICE / "db" / "migrations",
              RADICE.parent / "BID-02_modello_dati" / "db" / "migrations"):
        if p and Path(p).is_dir():
            return Path(p)
    pytest.exit("Cartella delle migrazioni non trovata: imposta ARCADE_MIGRAZIONI")


def _admin():
    return psycopg.connect("dbname=postgres", autocommit=True)


@pytest.fixture(scope="session")
def modello():
    nome = f"arcade_tpl_{uuid.uuid4().hex[:8]}"
    with _admin() as c:
        c.execute(f'CREATE DATABASE "{nome}"')
    for f in sorted(_migrazioni().glob("V*.sql")):
        r = subprocess.run(["psql", "-v", "ON_ERROR_STOP=1", "-q", "-1", "-d", nome, "-f", str(f)], capture_output=True, text=True)
        assert r.returncode == 0, f"{f.name}: {r.stderr}"
    yield nome
    with _admin() as c:
        c.execute(f'DROP DATABASE IF EXISTS "{nome}" WITH (FORCE)')


@pytest.fixture
def db(modello, monkeypatch):
    nome = f"arcade_t_{uuid.uuid4().hex[:8]}"
    with _admin() as c:
        c.execute(f'CREATE DATABASE "{nome}" TEMPLATE "{modello}"')
    monkeypatch.setenv("ARCADE_DSN", f"dbname={nome}")
    conn = psycopg.connect(f"dbname={nome}", autocommit=True)
    yield conn
    conn.close()
    with _admin() as c:
        c.execute(f'DROP DATABASE IF EXISTS "{nome}" WITH (FORCE)')


@pytest.fixture
def base_commerciale(db):
    """Un espositore, uno stand e un contratto 2025 (il minimo per ricevere visite e contatti)."""
    db.execute("INSERT INTO arcade.espositore (id_espositore, ragione_sociale, partita_iva) VALUES ('ESP001','Onda S.r.l.','12345678901')")
    db.execute("INSERT INTO arcade.stand (codice_stand, padiglione, mq, posizione, attivo_dal) VALUES ('P1-A01','P1',20,'linea',2024),('P1-A02','P1',30,'angolo',2024)")
    db.execute("INSERT INTO arcade.contratto (id_contratto, edizione, id_espositore, ragione_sociale_contratto, codice_stand, data_firma,"
               " imponibile_listino_eur, sconto_pct, imponibile_eur, acconto_scadenza, saldo_scadenza, rinnovo) VALUES"
               " ('C2025-0001',2025,'ESP001','Onda S.r.l.','P1-A01','2025-05-01',1000,0,1000,'2025-05-15','2025-11-01',false)")
    return db


def conta(db, tabella, where="true"):
    return db.execute(f"SELECT count(*) FROM arcade.{tabella} WHERE {where}").fetchone()[0]

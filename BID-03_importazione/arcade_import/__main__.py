"""Uso: python -m arcade_import <fonte> <file> [--edizione ANNO]
fonte: biglietteria | tornelli | visite_stand | contatti_stand | commerciale
Connessione al database: variabili d'ambiente PostgreSQL standard (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE)."""
import argparse
import json
import sys

from .core import esegui_importazione
from .sources import prepara_biglietteria, prepara_contatti, prepara_tornelli, prepara_visite
from .sources_commerciale import prepara_commerciale

FONTI = {"biglietteria": (prepara_biglietteria, True), "tornelli": (prepara_tornelli, True), "visite_stand": (prepara_visite, True),
         "contatti_stand": (prepara_contatti, True), "commerciale": (prepara_commerciale, False)}


def main(argv=None):
    p = argparse.ArgumentParser(prog="arcade_import", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("fonte", choices=FONTI)
    p.add_argument("file")
    p.add_argument("--edizione", type=int, help="anno dell'edizione (obbligatorio tranne che per 'commerciale')")
    a = p.parse_args(argv)
    prep, serve_ed = FONTI[a.fonte]
    if serve_ed and not a.edizione:
        p.error(f"--edizione e' obbligatorio per la fonte {a.fonte}")
    esito = esegui_importazione(a.fonte, a.file, a.edizione if serve_ed else None, prep)
    print(json.dumps(esito, ensure_ascii=False, indent=2))
    return 0 if esito["stato"] in ("completata", "gia_importato") else 2


if __name__ == "__main__":
    sys.exit(main())

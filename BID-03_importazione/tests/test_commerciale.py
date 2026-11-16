import copy

import pandas as pd
import pytest

from arcade_import.core import esegui_importazione
from arcade_import.sources_commerciale import prepara_commerciale
from conftest import conta

BASE = {
    "Espositori": [{"id_espositore": "ESP001", "ragione_sociale": "Onda Collectibles S.p.A.", "partita_iva": "01965569816", "settore": "Merch", "citta": "Milano", "referente": "A", "email_referente": "a@example.org"},
                   {"id_espositore": "ESP002", "ragione_sociale": "Gelso Shop S.r.l.", "partita_iva": "30365414586", "settore": "Merch", "citta": "Roma", "referente": "B", "email_referente": "b@example.org"}],
    "Planimetria": [{"codice_stand": "P1-A01", "padiglione": "P1", "nome_padiglione": "x", "mq": 20, "posizione": "linea", "attivo_dal": 2024},
                    {"codice_stand": "P1-A02", "padiglione": "P1", "nome_padiglione": "x", "mq": 30, "posizione": "angolo", "attivo_dal": 2024},
                    {"codice_stand": "P2-B01", "padiglione": "P2", "nome_padiglione": "y", "mq": 40, "posizione": "isola", "attivo_dal": 2026}],
    "Listino_2026": [{"codice": "SPAZIO-P1", "voce": "Area", "unita": "m2", "prezzo_unitario_eur": 190, "disponibilita": "da planimetria", "note": None}],
    "Contratti": [
        {"id_contratto": "C2024-0001", "edizione": 2024, "id_espositore": None, "ragione_sociale": "Gelso Shops.", "partita_iva": None, "codice_stand": "P1-A01",
         "data_firma": pd.Timestamp("2024-05-01"), "imponibile_listino_eur": 1000, "sconto_pct": 0.1, "imponibile_eur": 900, "acconto_scadenza": pd.Timestamp("2024-05-16"),
         "acconto_pagato_il": pd.Timestamp("2024-05-10"), "saldo_scadenza": pd.Timestamp("2024-11-01"), "saldo_pagato_il": pd.NaT, "rinnovo": False},
        {"id_contratto": "C2025-0001", "edizione": 2025, "id_espositore": "ESP001", "ragione_sociale": "Onda Collectibles S.p.A.", "partita_iva": "01965569816", "codice_stand": "P1-A02",
         "data_firma": pd.Timestamp("2025-05-01"), "imponibile_listino_eur": 2000, "sconto_pct": 0, "imponibile_eur": 2000, "acconto_scadenza": pd.Timestamp("2025-05-16"),
         "acconto_pagato_il": pd.Timestamp("2025-05-10"), "saldo_scadenza": pd.Timestamp("2025-11-01"), "saldo_pagato_il": pd.Timestamp("2025-10-30"), "rinnovo": True}],
    "Righe_contratto": [
        {"id_contratto": "C2024-0001", "riga": 1, "codice_voce": "SPAZIO", "descrizione": "Area", "quantita": 20, "prezzo_unitario_eur": 50, "importo_eur": 1000},
        {"id_contratto": "C2025-0001", "riga": 1, "codice_voce": "SPAZIO", "descrizione": "Area", "quantita": 30, "prezzo_unitario_eur": 60, "importo_eur": 1800},
        {"id_contratto": "C2025-0001", "riga": 2, "codice_voce": "MAGG", "descrizione": "Angolo", "quantita": 1, "prezzo_unitario_eur": 200, "importo_eur": 200}],
}


def xlsx(tmp_path, modifica=None, nome="c.xlsx"):
    d = copy.deepcopy(BASE)
    if modifica:
        modifica(d)
    p = tmp_path / nome
    with pd.ExcelWriter(p) as w:
        for foglio, righe in d.items():
            pd.DataFrame(righe).to_excel(w, sheet_name=foglio, index=False)
    return p


def importa(p):
    return esegui_importazione("commerciale", p, None, prepara_commerciale)


def anomalie(db):
    return db.execute("SELECT regola, esito, tabella FROM arcade.importazione_anomalia WHERE esito IN ('QUARANTENA','SCARTATO') ORDER BY 1, 3").fetchall()


def test_file_valido(db, tmp_path):
    e = importa(xlsx(tmp_path))
    assert e["stato"] == "completata" and e["righe_quarantena"] == 0 and e["righe_scartate"] == 0
    assert e["righe_lette"] == e["righe_accettate"] + e["righe_corrette"]
    assert [conta(db, t) for t in ("espositore", "stand", "listino_prezzo", "contratto", "contratto_riga")] == [2, 3, 1, 2, 3]
    # R-C01: l'ID espositore del contratto 2024 e' derivato dal nome (regola della 's' finale) e marcato come tale
    assert db.execute("SELECT id_espositore, id_espositore_origine FROM arcade.contratto WHERE id_contratto='C2024-0001'").fetchone() == ("ESP002", "derivato")
    assert db.execute("SELECT id_espositore_origine FROM arcade.contratto WHERE id_contratto='C2025-0001'").fetchone()[0] == "sorgente"
    # R-C05: voci generiche -> codici canonici, originale conservato
    assert db.execute("SELECT codice_voce, codice_voce_origine FROM arcade.contratto_riga WHERE id_contratto='C2025-0001' ORDER BY riga").fetchall() == \
        [("SPAZIO-P1", "SPAZIO"), ("MAGG-ANGOLO", "MAGG")]
    # R-C03: pagamento mancante conservato come NULL, nessuno stato dedotto
    assert db.execute("SELECT saldo_pagato_il FROM arcade.contratto WHERE id_contratto='C2024-0001'").fetchone()[0] is None
    assert db.execute("SELECT regola FROM arcade.importazione_anomalia WHERE esito='SEGNALATO'").fetchall()


def test_ricarico_identico_e_con_aggiunte(db, tmp_path):
    importa(xlsx(tmp_path))
    assert importa(xlsx(tmp_path))["stato"] == "gia_importato"
    def aggiungi(d):
        d["Espositori"].append({"id_espositore": "ESP003", "ragione_sociale": "Nuova S.r.l.", "partita_iva": "11111111111"})
    e = importa(xlsx(tmp_path, aggiungi, "c2.xlsx"))
    assert e["righe_nuove"]["espositore"] == 1 and e["righe_gia_presenti"]["espositore"] == 2 and conta(db, "espositore") == 3
    assert conta(db, "contratto") == 2


def test_partita_iva_con_zero_iniziale_ripristinato(db, tmp_path):
    importa(xlsx(tmp_path, lambda d: d["Espositori"][0].update(partita_iva="1965569816")))   # 10 cifre: lo zero e' andato perso
    assert db.execute("SELECT partita_iva FROM arcade.espositore WHERE id_espositore='ESP001'").fetchone()[0] == "01965569816"


@pytest.mark.parametrize("modifica,attese", [
    (lambda d: d["Espositori"][1].update(partita_iva="123"), [("R-C02", "QUARANTENA", "espositore"), ("R-C01", "QUARANTENA", "contratto"), ("R-C16", "QUARANTENA", "contratto_riga")]),
    (lambda d: d["Espositori"][1].update(partita_iva="01965569816"), [("R-C08", "QUARANTENA", "espositore")]),
    (lambda d: d["Planimetria"][0].update(mq=-5), [("R-C09", "QUARANTENA", "stand")]),
    (lambda d: d["Contratti"][1].update(codice_stand="P9-Z99"), [("R-C09", "QUARANTENA", "contratto")]),
    (lambda d: d["Contratti"][1].update(imponibile_eur=1), [("R-C12", "QUARANTENA", "contratto")]),
    (lambda d: d["Contratti"][1].update(acconto_scadenza=pd.Timestamp("2025-01-01")), [("R-C13", "QUARANTENA", "contratto")]),
    (lambda d: d["Contratti"][1].update(id_espositore="ESP777"), [("R-C06", "QUARANTENA", "contratto")]),
    (lambda d: d["Contratti"][1].update(codice_stand="P2-B01"), [("R-C09", "QUARANTENA", "contratto")]),     # stand attivo dal 2026
    (lambda d: d["Contratti"][1].update(codice_stand="P1-A01", id_contratto="C2025-0001") or d["Contratti"][0].update(edizione=2025, id_contratto="C2025-0009"), [("R-C15", "QUARANTENA", "contratto")]),
])
def test_record_commerciali_non_validi(db, tmp_path, modifica, attese):
    e = importa(xlsx(tmp_path, modifica))
    assert e["stato"] == "completata"
    trovate = anomalie(db)
    for a in attese:
        assert a in trovate, (a, trovate)
    assert e["righe_lette"] == e["righe_accettate"] + e["righe_corrette"] + e["righe_quarantena"] + e["righe_scartate"]


def test_riga_di_contratto_incoerente(db, tmp_path):
    e = importa(xlsx(tmp_path, lambda d: d["Righe_contratto"][1].update(importo_eur=1)))
    assert ("R-C17", "QUARANTENA", "contratto_riga") in anomalie(db) and conta(db, "contratto_riga") == 2


def test_maggiorazione_non_applicabile_a_stand_in_linea(db, tmp_path):
    importa(xlsx(tmp_path, lambda d: d["Righe_contratto"].append(
        {"id_contratto": "C2024-0001", "riga": 2, "codice_voce": "MAGG", "descrizione": "x", "quantita": 1, "prezzo_unitario_eur": 10, "importo_eur": 10})))
    assert ("R-C07", "QUARANTENA", "contratto_riga") in anomalie(db)


@pytest.mark.parametrize("modifica", [lambda d: d.pop("Contratti"), lambda d: d["Planimetria"][0].pop("mq") and [r.pop("mq", None) for r in d["Planimetria"]]])
def test_struttura_del_file_errata(db, tmp_path, modifica):
    e = importa(xlsx(tmp_path, modifica))
    assert e["stato"] == "fallita" and conta(db, "stand") == 0 and conta(db, "espositore") == 0


def test_file_non_excel(db, tmp_path):
    p = tmp_path / "x.xlsx"; p.write_text("non e' un file excel")
    assert importa(p)["stato"] == "fallita"

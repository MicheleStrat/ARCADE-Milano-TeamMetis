import pytest

from arcade_import.core import esegui_importazione
from arcade_import.sources import prepara_biglietteria, prepara_tornelli
from conftest import conta
from test_biglietteria import INT, importa as importa_bigl, riga as riga_bigl, scrivi as scrivi_bigl

H24 = "data;ora;varco;codice;esito"
H25 = "timestamp_utc,ticket_code,gate_id,result"


def tornelli(tmp_path, righe, ed=2024, nome="t.csv"):
    p = tmp_path / nome
    p.write_text("\n".join([H24 if ed == 2024 else H25, *righe]) + "\n")
    return esegui_importazione("tornelli", p, ed, prepara_tornelli)


@pytest.fixture
def biglietti24(db, tmp_path):
    importa_bigl(scrivi_bigl(tmp_path, [riga_bigl(), riga_bigl(t="T24000002"), riga_bigl(t="T24000003")], "bigl.csv"))
    return db


def test_formato_2024_ora_locale_in_utc(biglietti24, tmp_path):
    e = tornelli(tmp_path, ["20/12/2024;09:00:02;P1 Nord;T24000001;1"])
    assert e["stato"] == "completata" and e["righe_nuove"]["lettura_tornello"] == 1
    r = biglietti24.execute("SELECT ts AT TIME ZONE 'UTC', varco, id_biglietto, accettata FROM arcade.lettura_tornello").fetchone()
    assert (str(r[0]), r[1], r[2], r[3]) == ("2024-12-20 08:00:02", "P1-Nord", "T24000001", True)


def test_formato_2025_utc(db, tmp_path):
    importa_bigl(scrivi_bigl(tmp_path, [riga_bigl(o="O25000001", t="T25000001", acq="01/12/2025 10:00", tipo="Giornaliero intero", giorno="19/12/2025")], "b25.csv"), ed=2025)
    e = tornelli(tmp_path, ["2025-12-19T08:00:05Z,T25000001,P1-Sud,OK"], ed=2025)
    assert e["stato"] == "completata"
    assert str(db.execute("SELECT ts AT TIME ZONE 'UTC' FROM arcade.lettura_tornello").fetchone()[0]) == "2025-12-19 08:00:05"


def test_respinti_e_codici_sconosciuti(biglietti24, tmp_path):
    e = tornelli(tmp_path, ["20/12/2024;09:00:02;P1 Nord;T24000001;1",
                            "20/12/2024;09:00:03;P1 Nord;T24000002;0",       # KO su biglietto noto
                            "20/12/2024;09:00:04;P1 Sud;T24099999;0"])       # KO su codice sconosciuto
    assert e["righe_quarantena"] == 0 and conta(biglietti24, "lettura_tornello") == 3
    assert conta(biglietti24, "lettura_tornello", "id_biglietto IS NULL AND NOT accettata") == 1   # respinta conservata (R-T02)
    assert conta(biglietti24, "lettura_tornello", "accettata") == 1
    regole = {r[0] for r in biglietti24.execute("SELECT regola FROM arcade.importazione_anomalia WHERE esito='SEGNALATO'")}
    assert regole == {"R-T02", "R-T03"}


@pytest.mark.parametrize("riga,regola,esito", [
    ("20/12/2024;09:00:04;P1 Sud;T24099999;1", "R-T02", "QUARANTENA"),   # OK su codice assente in biglietteria
    ("20/12/2024;09:00:04;P9 Nord;T24000001;1", "R-T01", "QUARANTENA"),  # varco sconosciuto
    ("25/12/2024;09:00:04;P1 Nord;T24000001;1", "R-T07", "QUARANTENA"),  # fuori dai giorni dell'edizione
    ("20/12/2024;99:00:04;P1 Nord;T24000001;1", "R-F02", "SCARTATO"),    # ora non valida
    ("20/12/2024;09:00:04;P1 Nord;XYZ;1", "R-F01", "SCARTATO"),          # codice malformato
    ("20/12/2024;09:00:04;P1 Nord;T24000001;7", "R-F06", "SCARTATO"),    # esito non interpretabile
])
def test_letture_non_valide_tracciate(biglietti24, tmp_path, riga, regola, esito):
    e = tornelli(tmp_path, ["20/12/2024;09:00:02;P1 Nord;T24000001;1", riga])
    assert e["stato"] == "completata" and conta(biglietti24, "lettura_tornello") == 1
    assert e["righe_lette"] == e["righe_accettate"] + e["righe_corrette"] + e["righe_quarantena"] + e["righe_scartate"]
    a = biglietti24.execute("SELECT regola, esito FROM arcade.importazione_anomalia WHERE esito IN ('QUARANTENA','SCARTATO')").fetchall()
    assert a == [(regola, esito)]


def test_doppia_lettura_ravvicinata_non_e_scartata(biglietti24, tmp_path):
    """Due letture dello stesso biglietto a 5 s di distanza NON sono duplicati: la regola dei 60 s e' una proposta (R-T04)."""
    tornelli(tmp_path, ["20/12/2024;09:00:02;P1 Nord;T24000001;1", "20/12/2024;09:00:07;P1 Nord;T24000001;1"])
    assert conta(biglietti24, "lettura_tornello") == 2


def test_riga_identica_nel_file_e_tracciata(biglietti24, tmp_path):
    r = "20/12/2024;09:00:02;P1 Nord;T24000001;1"
    e = tornelli(tmp_path, [r, r])
    assert conta(biglietti24, "lettura_tornello") == 1 and e["righe_scartate"] == 1


def test_ricarico_con_sovrapposizione_non_duplica(biglietti24, tmp_path):
    a = ["20/12/2024;09:00:02;P1 Nord;T24000001;1", "20/12/2024;09:00:09;P1 Sud;T24000002;1"]
    tornelli(tmp_path, a, nome="a.csv")
    e = tornelli(tmp_path, [*a, "20/12/2024;09:01:00;P2 Ovest;T24000003;1"], nome="b.csv")
    assert e["righe_nuove"]["lettura_tornello"] == 1 and e["righe_gia_presenti"]["lettura_tornello"] == 2
    assert conta(biglietti24, "lettura_tornello") == 3
    assert tornelli(tmp_path, a, nome="a.csv")["stato"] == "gia_importato"


def test_senza_biglietteria_nessuna_lettura_accettata(db, tmp_path):
    """Dipendenza tra fonti: caricando i tornelli prima della biglietteria le letture OK vengono messe in quarantena."""
    e = tornelli(tmp_path, ["20/12/2024;09:00:02;P1 Nord;T24000001;1", "20/12/2024;09:00:03;P1 Nord;T24000002;0"])
    assert conta(db, "lettura_tornello", "accettata") == 0 and e["righe_quarantena"] == 1


def test_intestazione_non_riconosciuta(db, tmp_path):
    p = tmp_path / "x.csv"; p.write_text("a,b,c\n1,2,3\n")
    e = esegui_importazione("tornelli", p, 2024, prepara_tornelli)
    assert e["stato"] == "fallita" and conta(db, "lettura_tornello") == 0

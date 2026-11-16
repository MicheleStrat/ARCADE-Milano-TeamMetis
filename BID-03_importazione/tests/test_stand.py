import pytest

from arcade_import.core import esegui_importazione
from arcade_import.sources import prepara_contatti, prepara_visite
from conftest import conta

HV = "codice_stand,data,ora,scansioni"
HC = "id_contatto,codice_stand,id_espositore,timestamp,email,fascia_eta,provincia,consenso_marketing,interesse"


def visite(tmp_path, righe, nome="v.csv"):
    p = tmp_path / nome; p.write_text("\n".join([HV, *righe]) + "\n")
    return esegui_importazione("visite_stand", p, 2025, prepara_visite)


def contatti(tmp_path, righe, nome="c.csv"):
    p = tmp_path / nome; p.write_text("\n".join([HC, *righe]) + "\n")
    return esegui_importazione("contatti_stand", p, 2025, prepara_contatti)


def c(i=1, stand="P1-A01", esp="ESP001", ts="2025-12-19 14:46", email="a@example.org", fascia="35-44", prov="MB", cons="SI", int_="evento"):
    return ",".join([f"L25{i:05d}", stand, esp, ts, email, fascia, prov, cons, int_])


# --------------------------------------------------------------- visite
def test_visite_valide_e_zero_scansioni(base_commerciale, tmp_path):
    e = visite(tmp_path, ["P1-A01,2025-12-19,09:00,3", "P1-A01,2025-12-19,10:00,0"])
    assert e["stato"] == "completata" and conta(base_commerciale, "visita_stand_oraria") == 2
    assert conta(base_commerciale, "visita_stand_oraria", "scansioni = 0") == 1   # 0 scansioni e' un dato valido (R-S03)


@pytest.mark.parametrize("riga,regola,esito", [
    ("P1-A01,2025-12-19,08:00,912", "R-S01", "QUARANTENA"),
    ("P1-A01,2025-12-19,19:00,5", "R-S01", "QUARANTENA"),
    ("P9-Z99,2025-12-19,10:00,5", "R-S07", "QUARANTENA"),
    ("P1-A01,2025-12-25,10:00,5", "R-S08", "QUARANTENA"),
    ("P1-A01,2025-12-19,10:30,5", "R-F02", "SCARTATO"),
    ("P1-A01,19/12/2025,10:00,5", "R-F02", "SCARTATO"),
    ("P1-A01,2025-12-19,10:00,-4", "R-F03", "SCARTATO"),
    ("P1-A01,2025-12-19,10:00,molte", "R-F03", "SCARTATO"),
])
def test_visite_non_valide(base_commerciale, tmp_path, riga, regola, esito):
    e = visite(tmp_path, ["P1-A01,2025-12-19,09:00,3", riga])
    assert conta(base_commerciale, "visita_stand_oraria") == 1
    assert base_commerciale.execute("SELECT regola, esito FROM arcade.importazione_anomalia").fetchall() == [(regola, esito)]
    assert e["righe_lette"] == 2 and e["righe_accettate"] == 1


def test_visite_la_quarantena_conserva_le_scansioni(base_commerciale, tmp_path):
    visite(tmp_path, ["P1-A01,2025-12-19,08:00,912"])
    assert base_commerciale.execute("SELECT dettaglio->'record'->>'scansioni' FROM arcade.importazione_anomalia").fetchone()[0] == "912"


def test_visite_slot_mancanti_non_imputati(base_commerciale, tmp_path):
    visite(tmp_path, ["P1-A01,2025-12-19,09:00,3", "P1-A01,2025-12-19,11:00,4"])
    assert conta(base_commerciale, "visita_stand_oraria") == 2     # nessuna riga inventata per le 10:00


def test_visite_ricarico_e_conflitto(base_commerciale, tmp_path):
    visite(tmp_path, ["P1-A01,2025-12-19,09:00,3"], "a.csv")
    e = visite(tmp_path, ["P1-A01,2025-12-19,09:00,3", "P1-A01,2025-12-19,10:00,4"], "b.csv")
    assert e["righe_nuove"]["visita_stand_oraria"] == 1 and e["righe_gia_presenti"]["visita_stand_oraria"] == 1
    e = visite(tmp_path, ["P1-A01,2025-12-19,09:00,99"], "c.csv")       # stesso slot, valore diverso: non sovrascrive
    assert e["conflitti_non_applicati"] == 1
    assert base_commerciale.execute("SELECT scansioni FROM arcade.visita_stand_oraria WHERE ora='09:00'").fetchone()[0] == 3


def test_visite_stesso_slot_due_valori_nel_file(base_commerciale, tmp_path):
    e = visite(tmp_path, ["P1-A01,2025-12-19,09:00,3", "P1-A01,2025-12-19,09:00,5"])
    assert conta(base_commerciale, "visita_stand_oraria") == 1 and e["righe_quarantena"] == 1


# --------------------------------------------------------------- contatti
def test_contatti_validi_e_minorenni(base_commerciale, tmp_path):
    e = contatti(tmp_path, [c(1), c(2, fascia="14-17"), c(3, cons="")])
    assert e["stato"] == "completata" and conta(base_commerciale, "contatto_stand") == 3
    assert conta(base_commerciale, "contatto_stand", "minorenne") == 1
    assert base_commerciale.execute("SELECT consenso_marketing, consenso_non_registrato FROM arcade.contatto_stand WHERE id_contatto='L2500003'").fetchone() == (False, True)
    # il contatto del minorenne non espone l'e-mail nella vista del portale
    assert base_commerciale.execute("SELECT email FROM arcade.v_contatto_portale WHERE id_contatto='L2500002'").fetchone()[0] is None


@pytest.mark.parametrize("riga,regola", [
    (c(9, stand="P1-A02"), "R-S10"),            # lo stand non e' di questo espositore (nessun contratto)
    (c(9, esp="ESP999"), "R-S10"),              # espositore inesistente
    (c(9, email="non-una-mail"), "R-S11"),
    (c(9, fascia="famiglia"), "R-S12"),
    (c(9, cons="forse"), "R-S04"),
    (c(9, ts="2025-12-30 10:00"), "R-S08"),
    (c(9, prov="Atlantide"), "R-B03"),
])
def test_contatti_non_validi_in_quarantena(base_commerciale, tmp_path, riga, regola):
    e = contatti(tmp_path, [c(1), riga])
    assert conta(base_commerciale, "contatto_stand") == 1 and e["righe_quarantena"] == 1
    assert base_commerciale.execute("SELECT regola FROM arcade.importazione_anomalia WHERE esito='QUARANTENA'").fetchone()[0] == regola


def test_contatti_id_malformato_e_scartato(base_commerciale, tmp_path):
    e = contatti(tmp_path, [c(1), "XX1,P1-A01,ESP001,2025-12-19 14:46,a@example.org,35-44,MB,SI,evento"])
    assert e["righe_scartate"] == 1 and conta(base_commerciale, "contatto_stand") == 1


def test_contatti_stessa_email_su_stand_diversi_si_mantiene(base_commerciale, tmp_path):
    base_commerciale.execute("INSERT INTO arcade.contratto (id_contratto, edizione, id_espositore, ragione_sociale_contratto, codice_stand, data_firma,"
                             " imponibile_listino_eur, sconto_pct, imponibile_eur, acconto_scadenza, saldo_scadenza, rinnovo) VALUES"
                             " ('C2025-0002',2025,'ESP001','Onda S.r.l.','P1-A02','2025-05-01',500,0,500,'2025-05-15','2025-11-01',false)")
    contatti(tmp_path, [c(1, stand="P1-A01"), c(2, stand="P1-A02")])
    assert conta(base_commerciale, "contatto_stand") == 2           # R-S06: contatti unici = e-mail distinte, non si scarta


def test_contatti_senza_contratti_tutto_in_quarantena(db, tmp_path):
    """Dipendenza tra fonti: senza i dati commerciali nessun contatto e' attribuibile a un espositore."""
    e = contatti(tmp_path, [c(1), c(2)])
    assert conta(db, "contatto_stand") == 0 and e["righe_quarantena"] == 2

import pytest

from arcade_import.core import esegui_importazione
from arcade_import.sources import prepara_biglietteria
from conftest import conta

INT = "ID ordine;ID biglietto;Data acquisto;Canale;Tipo biglietto;Giorno valido;Prezzo;Persone;Fascia eta titolare;Provincia;Codice sconto"


def riga(o="O24000001", t="T24000001", acq="21/12/2024 12:14", canale="Cassa", tipo="Intero", giorno="21/12/2024",
         prezzo="22,00", pers="1", fascia="25-34", prov="MI", sconto=""):
    return ";".join([o, t, acq, canale, tipo, giorno, prezzo, pers, fascia, prov, sconto])


def scrivi(tmp_path, righe, nome="b.csv", intestazione=INT):
    p = tmp_path / nome
    p.write_text("\n".join([intestazione, *righe]) + "\n", encoding="utf-8")
    return p


def importa(p, ed=2024):
    return esegui_importazione("biglietteria", p, ed, prepara_biglietteria)


def quadra(e):
    assert e["righe_lette"] == e["righe_accettate"] + e["righe_corrette"] + e["righe_quarantena"] + e["righe_scartate"]


def test_file_valido_con_correzioni(db, tmp_path):
    p = scrivi(tmp_path, [
        riga(),
        riga(t="T24000002", tipo="Abb. 3gg", giorno="3 giorni", prov="Milano", fascia="8-13", pers="1"),
        riga(o="O24000002", t="T24000003", tipo="Family", prezzo="55,00", pers="4", fascia="famiglia", prov="", canale="Online"),
    ])
    e = importa(p)
    assert e["stato"] == "completata"
    quadra(e)
    assert (e["righe_lette"], e["righe_quarantena"], e["righe_scartate"]) == (3, 0, 0)
    assert e["righe_corrette"] == 1  # solo il secondo biglietto (abbonamento + provincia estesa)
    assert conta(db, "biglietto") == 3 and conta(db, "ordine") == 2
    r = db.execute("SELECT giorno_valido, provincia, provincia_origine, minorenne, tipo FROM arcade.biglietto WHERE id_biglietto='T24000002'").fetchone()
    assert r[0] is None and r[1] == "MI" and r[2] == "Milano" and r[3] is True and r[4] == "ABB_3GG"
    assert db.execute("SELECT prezzo_eur, provincia FROM arcade.biglietto WHERE id_biglietto='T24000003'").fetchone() == (55, None)
    # il registro conserva la traccia delle correzioni e delle segnalazioni, senza una riga per ogni record
    regole = {(r[0], r[1]) for r in db.execute("SELECT regola, esito FROM arcade.importazione_anomalia")}
    assert {("R-B02", "CORRETTO"), ("R-B03", "CORRETTO"), ("R-B03", "SEGNALATO"), ("R-B06", "SEGNALATO")} <= regole


def test_ora_locale_convertita_in_utc(db, tmp_path):
    importa(scrivi(tmp_path, [riga(acq="21/12/2024 12:14")]))
    assert str(db.execute("SELECT data_acquisto AT TIME ZONE 'UTC' FROM arcade.ordine").fetchone()[0]) == "2024-12-21 11:14:00"


def test_rieseguire_lo_stesso_file_non_duplica(db, tmp_path):
    p = scrivi(tmp_path, [riga(), riga(t="T24000002")])
    primo = importa(p)
    secondo = importa(p)
    assert primo["stato"] == "completata" and secondo["stato"] == "gia_importato"
    assert secondo["importazione_id"] == primo["importazione_id"]
    assert conta(db, "biglietto") == 2 and conta(db, "importazione") == 1


def test_file_con_righe_nuove_e_gia_presenti(db, tmp_path):
    importa(scrivi(tmp_path, [riga(), riga(t="T24000002")], "a.csv"))
    e = importa(scrivi(tmp_path, [riga(), riga(t="T24000002"), riga(t="T24000003")], "b.csv"))
    assert e["righe_nuove"]["biglietto"] == 1 and e["righe_gia_presenti"]["biglietto"] == 2
    assert conta(db, "biglietto") == 3 and conta(db, "ordine") == 1


def test_stessa_chiave_con_valori_diversi_non_sovrascrive(db, tmp_path):
    importa(scrivi(tmp_path, [riga(prezzo="22,00")], "a.csv"))
    e = importa(scrivi(tmp_path, [riga(prezzo="30,00")], "b.csv"))
    assert e["conflitti_non_applicati"] == 1          # l'ordine e' identico; cambia solo il prezzo del biglietto
    assert db.execute("SELECT prezzo_eur FROM arcade.biglietto").fetchone()[0] == 22
    t, k, d = db.execute("SELECT tabella, chiave_record, dettaglio FROM arcade.importazione_anomalia WHERE regola='R-X02'").fetchone()
    assert (t, k) == ("biglietto", "T24000001") and set(d["differenze"]) == {"prezzo_eur"}


@pytest.mark.parametrize("riga_errata,regola,esito", [
    (riga(t="T24000009", prezzo="abc"), "R-B05", "QUARANTENA"),
    (riga(t="T24000009", prezzo="-5,00"), "R-B05", "QUARANTENA"),
    (riga(t="T24000009", tipo="Tipo sconosciuto"), "R-B01", "QUARANTENA"),
    (riga(t="T24000009", fascia="99-100"), "R-B04", "QUARANTENA"),
    (riga(t="T24000009", prov="Atlantide"), "R-B03", "QUARANTENA"),
    (riga(t="T24000009", canale="Bancarella"), "R-B10", "QUARANTENA"),
    (riga(t="T24000009", giorno="03/01/2030"), "R-B08", "QUARANTENA"),
    (riga(t="T24000009", giorno=""), "R-B08", "QUARANTENA"),
    (riga(t="T24000009", tipo="Abb. 3gg", giorno="21/12/2024"), "R-B08", "QUARANTENA"),
    (riga(t="T24000009", acq="31/02/2024 10:00"), "R-F02", "SCARTATO"),
    (riga(t="T24000009", giorno="boh"), "R-F02", "SCARTATO"),
    (riga(t="T24000009", pers="0"), "R-F03", "SCARTATO"),
    (riga(t="T25000009"), "R-F01", "SCARTATO"),     # biglietto di un'altra edizione
    (riga(t=""), "R-F01", "SCARTATO"),              # record incompleto: ID mancante
    (riga(o="X24000001"), "R-F01", "SCARTATO"),
])
def test_record_non_validi_non_fermano_il_caricamento(db, tmp_path, riga_errata, regola, esito):
    e = importa(scrivi(tmp_path, [riga(), riga_errata, riga(t="T24000002")]))
    assert e["stato"] == "completata"
    quadra(e)
    assert conta(db, "biglietto") == 2            # i due record validi sono stati caricati
    a = db.execute("SELECT regola, esito, riga_sorgente, dettaglio FROM arcade.importazione_anomalia WHERE esito IN ('QUARANTENA','SCARTATO')").fetchall()
    assert len(a) == 1 and a[0][0] == regola and a[0][1] == esito and a[0][2] == 3
    assert "record" in a[0][3]                    # il contenuto originale e' conservato per la correzione
    assert e["righe_quarantena"] + e["righe_scartate"] == 1


def test_id_ripetuto_nel_file(db, tmp_path):
    e = importa(scrivi(tmp_path, [riga(), riga(), riga(prezzo="99,00")]))
    assert conta(db, "biglietto") == 1
    assert (e["righe_scartate"], e["righe_quarantena"]) == (1, 1)   # identica -> scartata (tracciata); diversa -> quarantena


def test_dati_diversi_nello_stesso_ordine(db, tmp_path):
    e = importa(scrivi(tmp_path, [riga(), riga(t="T24000002", canale="Online")]))
    assert conta(db, "biglietto") == 1 and e["righe_quarantena"] == 1
    assert db.execute("SELECT regola FROM arcade.importazione_anomalia WHERE esito='QUARANTENA'").fetchone()[0] == "R-B09"


def test_riga_con_numero_di_campi_errato(db, tmp_path):
    p = scrivi(tmp_path, [riga(), "O24000001;T24000005;solo tre campi", riga(t="T24000002")])
    e = importa(p)
    assert conta(db, "biglietto") == 2 and e["righe_scartate"] == 1
    assert db.execute("SELECT regola, dettaglio->>'riga_grezza' FROM arcade.importazione_anomalia WHERE esito='SCARTATO'").fetchone()[0] == "R-F05"


@pytest.mark.parametrize("testo", ["", "ID ordine;ID biglietto\nO24000001;T24000001\n"])
def test_file_malformato_non_carica_nulla(db, tmp_path, testo):
    p = tmp_path / "x.csv"; p.write_text(testo)
    e = importa(p)
    assert e["stato"] == "fallita"
    assert conta(db, "biglietto") == 0 and conta(db, "ordine") == 0
    st, nota = db.execute("SELECT stato, note FROM arcade.importazione").fetchone()
    assert st == "fallita" and "errore" in nota
    # un file corretto dopo il fallimento puo' essere importato
    assert importa(scrivi(tmp_path, [riga()], "ok.csv"))["stato"] == "completata"


def test_file_non_utf8(db, tmp_path):
    p = tmp_path / "x.csv"; p.write_bytes((INT + "\n").encode() + "O24000001;T24000001;caffè".encode("latin-1"))
    assert importa(p)["stato"] == "fallita"


def test_edizione_inesistente(db, tmp_path):
    assert importa(scrivi(tmp_path, [riga()]), ed=1999)["stato"] == "fallita"

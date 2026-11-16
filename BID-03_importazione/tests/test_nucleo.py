"""Test del nucleo: atomicita', registro delle importazioni, interfaccia a riga di comando."""
import pandas as pd
import pytest

from arcade_import.__main__ import main
from arcade_import.core import Preparato, Raccolta, esegui_importazione
from conftest import conta


def test_errore_imprevisto_annulla_tutto_il_caricamento(db):
    """La prima tabella e' valida, la seconda viola un vincolo (tipo biglietto inesistente): nulla deve restare."""
    ordine = pd.DataFrame({"id_ordine": ["O24000001"], "edizione": [2024], "data_acquisto": ["2024-12-21 10:00:00+0000"], "canale": ["Cassa"]})
    bigl = pd.DataFrame({"id_biglietto": ["T24000001"], "id_ordine": ["O24000001"], "edizione": [2024], "tipo": ["NON_ESISTE"],
                         "giorno_valido": ["2024-12-21"], "prezzo_eur": ["10.00"], "persone": [1]})

    def prep(cur, p, ed):
        return Preparato({"ordine": ordine, "biglietto": bigl}, {"ordine": ["id_ordine"], "biglietto": ["id_biglietto"]}, Raccolta(), 1)
    import tempfile, pathlib
    f = pathlib.Path(tempfile.mkdtemp()) / "x.csv"; f.write_text("a")
    with pytest.raises(Exception):
        esegui_importazione("biglietteria", f, 2024, prep)
    assert conta(db, "ordine") == 0 and conta(db, "biglietto") == 0
    stato, nota = db.execute("SELECT stato, note FROM arcade.importazione").fetchone()
    assert stato == "fallita" and "errore" in nota                      # il fallimento resta tracciato
    # il file non e' marcato come completato: un nuovo tentativo e' possibile
    assert db.execute("SELECT count(*) FROM arcade.importazione WHERE stato='completata'").fetchone()[0] == 0


def test_registro_importazione(db, tmp_path):
    from test_biglietteria import importa, riga, scrivi
    e = importa(scrivi(tmp_path, [riga(), riga(t="T24000002", tipo="???")]))
    r = db.execute("SELECT fonte, edizione, nome_file, length(hash_file), stato, righe_lette, righe_accettate, righe_quarantena, terminata_il IS NOT NULL"
                   " FROM arcade.importazione WHERE id=%s", (e["importazione_id"],)).fetchone()
    assert r == ("biglietteria", 2024, "b.csv", 64, "completata", 2, 1, 1, True)


def test_cli_edizione_obbligatoria(db, tmp_path, capsys):
    p = tmp_path / "x.csv"; p.write_text("a")
    with pytest.raises(SystemExit) as e:
        main(["tornelli", str(p)])
    assert e.value.code == 2


def test_cli_esito(db, tmp_path, capsys):
    from test_biglietteria import riga, scrivi
    p = scrivi(tmp_path, [riga()])
    assert main(["biglietteria", str(p), "--edizione", "2024"]) == 0
    assert '"stato": "completata"' in capsys.readouterr().out
    assert main(["biglietteria", str(p), "--edizione", "2024"]) == 0
    assert '"gia_importato"' in capsys.readouterr().out
    bad = tmp_path / "bad.csv"; bad.write_text("x;y\n1;2\n")
    assert main(["biglietteria", str(bad), "--edizione", "2024"]) == 2

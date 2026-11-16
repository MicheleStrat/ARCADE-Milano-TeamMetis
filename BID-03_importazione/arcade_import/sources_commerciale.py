"""Importatore dei dati commerciali (cartella Excel del cliente / futura esportazione del BAD).
Fogli: Espositori, Planimetria, Listino_<anno>, Contratti, Righe_contratto. Regole R-C01...R-C05 (BID-01) piu' i
controlli R-C06...R-C17 introdotti in BID-03 (docs/02_registro_regole.md)."""
import pandas as pd

from . import rules
from .core import FileNonValido, Preparato, Raccolta
from .lettura import blocca_se
import re

FOGLI = {"Espositori": ["id_espositore", "ragione_sociale", "partita_iva"],
         "Planimetria": ["codice_stand", "padiglione", "mq", "posizione", "attivo_dal"],
         "Contratti": ["id_contratto", "edizione", "ragione_sociale", "codice_stand", "data_firma", "imponibile_listino_eur",
                       "sconto_pct", "imponibile_eur", "acconto_scadenza", "saldo_scadenza", "rinnovo"],
         "Righe_contratto": ["id_contratto", "riga", "codice_voce", "descrizione", "quantita", "prezzo_unitario_eur", "importo_eur"]}
POSIZIONE_MAGG = {"angolo": "MAGG-ANGOLO", "penisola": "MAGG-PENISOLA", "isola": "MAGG-ISOLA"}
BOOL = {True: True, False: False, "True": True, "False": False, "true": True, "false": False, "SI": True, "NO": False}
LISTINO = ["codice", "prezzo_unitario_eur"]


def _num(s):
    return pd.to_numeric(s, errors="coerce")


def _foglio(x, nome, rac, dtype=None):
    d = pd.read_excel(x, sheet_name=nome, dtype=dtype if dtype is not None else None)
    d["z_riga"] = range(2, len(d) + 2)
    return d


def prepara_commerciale(cur, percorso, edizione):
    rac = Raccolta()
    try:
        x = pd.ExcelFile(percorso)
    except Exception as e:
        raise FileNonValido(f"File Excel non leggibile: {e}") from e
    for nome, richieste in FOGLI.items():
        if nome not in x.sheet_names:
            raise FileNonValido(f"Foglio obbligatorio mancante: {nome}")
        mancanti = [c for c in richieste if c not in pd.read_excel(x, sheet_name=nome, nrows=0).columns]
        if mancanti:
            raise FileNonValido(f"Foglio {nome}: colonne obbligatorie mancanti {mancanti}")
    fogli_listino = [s for s in x.sheet_names if re.fullmatch(r"Listino_\d{4}", s)]

    cur.execute("SELECT anno FROM arcade.edizione"); edizioni = {r[0] for r in cur.fetchall()}
    cur.execute("SELECT codice FROM arcade.padiglione"); padiglioni = {r[0] for r in cur.fetchall()}
    cur.execute("SELECT codice FROM arcade.voce_listino"); voci = {r[0] for r in cur.fetchall()}
    cur.execute("SELECT id_espositore, ragione_sociale, partita_iva FROM arcade.espositore"); esp_db = cur.fetchall()
    cur.execute("SELECT codice_stand, padiglione, posizione, attivo_dal FROM arcade.stand"); stand_db = {r[0]: r[1:] for r in cur.fetchall()}
    cur.execute("SELECT edizione, codice_stand, id_contratto FROM arcade.contratto"); contr_stand_db = {(a, b): c for a, b, c in cur.fetchall()}
    cur.execute("SELECT id_contratto, codice_stand FROM arcade.contratto"); contr_db = dict(cur.fetchall())
    lette = 0

    # ------------------------------------------------ Espositori
    T = "espositore"
    esp = _foglio(x, "Espositori", rac, dtype=str).fillna("")
    lette += len(esp)
    cols = [c for c in esp.columns if c != "z_riga"]
    esp = blocca_se(rac, esp, ~esp.id_espositore.str.fullmatch(rules.RE_ESPOSITORE.pattern), "R-F01", "SCARTATO", T, "id_espositore", "ID espositore non valido", cols)
    dup = esp.duplicated("id_espositore", keep="first")
    esp = blocca_se(rac, esp, dup & esp.duplicated(cols, keep="first"), "R-F04", "SCARTATO", T, "id_espositore", "riga identica ripetuta", cols)
    esp = blocca_se(rac, esp, esp.duplicated("id_espositore", keep="first"), "R-F04", "QUARANTENA", T, "id_espositore", "stesso ID con valori diversi", cols)
    esp = blocca_se(rac, esp, esp.ragione_sociale.str.strip() == "", "R-C02", "QUARANTENA", T, "id_espositore", "ragione sociale mancante", cols)
    piva = esp.partita_iva.str.strip()
    esp = esp.assign(z_piva=piva.where(~piva.str.fullmatch(r"\d{10}"), piva.str.zfill(11)), z_zero=piva.str.fullmatch(r"\d{10}"))
    esp = blocca_se(rac, esp, ~esp.z_piva.str.fullmatch(r"\d{11}"), "R-C02", "QUARANTENA", T, "id_espositore", "partita IVA non valida (attese 11 cifre)", cols)
    esp = blocca_se(rac, esp, esp.duplicated("z_piva", keep="first"), "R-C08", "QUARANTENA", T, "id_espositore", "partita IVA gia' usata da un altro espositore nel file", cols)
    piva_db = {p: i for i, _, p in esp_db}
    esp = blocca_se(rac, esp, [piva_db.get(p, i) != i for p, i in zip(esp.z_piva, esp.id_espositore)], "R-C08", "QUARANTENA", T, "id_espositore",
                    "partita IVA gia' usata da un altro espositore nel database", cols)
    for r in esp.itertuples():
        if r.z_zero:
            rac.aggrega("R-C02", "CORRETTO", T, int(r.z_riga), r.id_espositore, "P.IVA con zeri iniziali persi: ripristinato lo zero iniziale perso (10 cifre -> 11)")
    t_esp = pd.DataFrame({"id_espositore": esp.id_espositore, "ragione_sociale": esp.ragione_sociale, "partita_iva": esp.z_piva,
                          **{c: esp[c].replace("", pd.NA) for c in ("settore", "citta", "referente", "email_referente") if c in esp}})
    esp_ok = {i: n for i, n in zip(esp.id_espositore, esp.ragione_sociale)}
    tutti_esp = {**{i: n for i, n, _ in esp_db}, **esp_ok}
    piva_esp = {**{i: p for i, _, p in esp_db}, **dict(zip(esp.id_espositore, esp.z_piva))}

    # ------------------------------------------------ Planimetria (stand)
    T = "stand"
    pl = _foglio(x, "Planimetria", rac).copy()
    lette += len(pl)
    for c in ("codice_stand", "padiglione", "posizione"):
        pl[c] = pl[c].astype(str).str.strip()
    cols = [c for c in ("codice_stand", "padiglione", "mq", "posizione", "attivo_dal") if c in pl]
    pl = pl.assign(z_mq=_num(pl.mq), z_att=_num(pl.attivo_dal))
    pl = blocca_se(rac, pl, ~pl.codice_stand.str.fullmatch(rules.RE_STAND.pattern), "R-F01", "SCARTATO", T, "codice_stand", "codice stand non valido", cols)
    dup = pl.duplicated("codice_stand", keep="first")
    pl = blocca_se(rac, pl, dup & pl.duplicated(cols, keep="first"), "R-F04", "SCARTATO", T, "codice_stand", "riga identica ripetuta", cols)
    pl = blocca_se(rac, pl, pl.duplicated("codice_stand", keep="first"), "R-F04", "QUARANTENA", T, "codice_stand", "stesso stand con valori diversi", cols)
    pl = blocca_se(rac, pl, ~(pl.z_mq > 0), "R-C09", "QUARANTENA", T, "codice_stand", "superficie non numerica o <= 0", cols)
    pl = blocca_se(rac, pl, ~pl.posizione.isin(["linea", "angolo", "penisola", "isola"]), "R-C09", "QUARANTENA", T, "codice_stand", "posizione sconosciuta", cols)
    pl = blocca_se(rac, pl, ~(pl.padiglione.isin(padiglioni) & (pl.codice_stand.str[:2] == pl.padiglione)), "R-C09", "QUARANTENA", T, "codice_stand", "padiglione inesistente o incoerente col codice stand", cols)
    pl = blocca_se(rac, pl, ~pl.z_att.isin(edizioni), "R-C09", "QUARANTENA", T, "codice_stand", "attivo_dal non e' un'edizione nota", cols)
    t_stand = pd.DataFrame({"codice_stand": pl.codice_stand, "padiglione": pl.padiglione, "mq": pl.z_mq,
                            "posizione": pl.posizione, "attivo_dal": pl.z_att.astype(int)})
    stand = {**stand_db, **{r.codice_stand: (r.padiglione, r.posizione, int(r.z_att)) for r in pl.itertuples()}}

    # ------------------------------------------------ Listino_<anno>
    T = "listino_prezzo"
    parti = []
    for nome in fogli_listino:
        anno = int(nome[-4:])
        li = _foglio(x, nome, rac).copy()
        lette += len(li)
        li["codice"] = li.codice.astype(str).str.strip()
        for c in ("disponibilita", "note"):
            if c not in li: li[c] = pd.NA
        li = li.assign(z_k=li.codice)
        cols = [c for c in ("codice", "prezzo_unitario_eur", "disponibilita", "note") if c in li]
        if anno not in edizioni:
            li = blocca_se(rac, li, pd.Series(True, index=li.index), "R-C09", "QUARANTENA", T, "z_k", f"edizione {anno} inesistente", cols)
        li = blocca_se(rac, li, ~li.codice.isin(voci), "R-C07", "QUARANTENA", T, "z_k", "voce non presente nel catalogo voce_listino", cols)
        li = blocca_se(rac, li, li.duplicated("codice", keep="first"), "R-F04", "QUARANTENA", T, "z_k", "voce ripetuta nel foglio", cols)
        valore = _num(li.prezzo_unitario_eur)
        disp = _num(li.disponibilita)
        for r, v, d in zip(li.itertuples(), valore, disp):
            if pd.isna(v):
                rac.aggrega("R-C05", "SEGNALATO", T, int(r.z_riga), r.codice, "prezzo non numerico: valore NULL (decisione aperta A-C08)")
        nota = li.note.where(li.note.notna(), li.disponibilita.where(li.disponibilita.astype(str) == "da planimetria"))
        parti.append(pd.DataFrame({"edizione": anno, "codice": li.codice, "valore": valore, "disponibilita": disp.astype("Int64"), "note": nota}))
    t_list = pd.concat(parti, ignore_index=True) if parti else pd.DataFrame(columns=["edizione", "codice", "valore", "disponibilita", "note"])

    # ------------------------------------------------ Contratti
    T = "contratto"
    co = _foglio(x, "Contratti", rac, dtype={"partita_iva": str, "id_espositore": str}).copy()
    lette += len(co)
    for c in ("id_espositore", "partita_iva", "id_contratto", "codice_stand", "ragione_sociale"):
        co[c] = co[c].where(co[c].notna(), "") if c in co else ""
        co[c] = co[c].astype(str).str.strip()
    cols = [c for c in co.columns if c != "z_riga"]
    co = co.assign(z_ed=_num(co.edizione), z_lis=_num(co.imponibile_listino_eur), z_sc=_num(co.sconto_pct), z_imp=_num(co.imponibile_eur),
                   z_firma=pd.to_datetime(co.data_firma, errors="coerce"), z_acc_s=pd.to_datetime(co.acconto_scadenza, errors="coerce"),
                   z_sal_s=pd.to_datetime(co.saldo_scadenza, errors="coerce"),
                   z_acc_p=pd.to_datetime(co.get("acconto_pagato_il"), errors="coerce"), z_sal_p=pd.to_datetime(co.get("saldo_pagato_il"), errors="coerce"),
                   z_riv=co.rinnovo.map(lambda v: BOOL.get(v)))
    dupl = lambda k: co.duplicated(k, keep="first")
    co = blocca_se(rac, co, ~co.id_contratto.str.fullmatch(rules.RE_CONTRATTO.pattern), "R-F01", "SCARTATO", T, "id_contratto", "ID contratto non valido", cols)
    co = blocca_se(rac, co, dupl("id_contratto") & co.duplicated(cols, keep="first"), "R-F04", "SCARTATO", T, "id_contratto", "riga identica ripetuta", cols)
    co = blocca_se(rac, co, dupl("id_contratto"), "R-F04", "QUARANTENA", T, "id_contratto", "stesso ID con valori diversi", cols)
    co = blocca_se(rac, co, co.z_ed.isna() | co.z_firma.isna() | co.z_acc_s.isna() | co.z_sal_s.isna() | co.z_lis.isna() | co.z_sc.isna() | co.z_imp.isna(),
                   "R-F02", "SCARTATO", T, "id_contratto", "data, importo o sconto mancante o non interpretabile", cols)
    co = blocca_se(rac, co, ~co.z_ed.isin(edizioni) | (co.id_contratto.str[1:5].astype(int) != co.z_ed), "R-C09", "QUARANTENA", T, "id_contratto", "edizione sconosciuta o diversa da quella nell'ID contratto", cols)
    co = blocca_se(rac, co, ~co.codice_stand.isin(stand), "R-C09", "QUARANTENA", T, "id_contratto", "stand inesistente in planimetria", cols)
    co = blocca_se(rac, co, [stand[s][2] > e for s, e in zip(co.codice_stand, co.z_ed)], "R-C09", "QUARANTENA", T, "id_contratto", "stand non ancora esistente nell'edizione del contratto", cols)
    co = blocca_se(rac, co, co.z_riv.isna(), "R-F03", "QUARANTENA", T, "id_contratto", "campo rinnovo non interpretabile", cols)
    co = blocca_se(rac, co, (co.z_sc < 0) | (co.z_sc > 1) | (co.z_lis < 0) | (co.z_imp < 0), "R-C12", "QUARANTENA", T, "id_contratto", "sconto fuori da 0-1 o importi negativi", cols)
    co = blocca_se(rac, co, (co.z_imp - (co.z_lis * (1 - co.z_sc)).round(2)).abs() > 0.01, "R-C12", "QUARANTENA", T, "id_contratto", "imponibile diverso da listino x (1 - sconto)", cols)
    co = blocca_se(rac, co, co.z_acc_s < co.z_firma, "R-C13", "QUARANTENA", T, "id_contratto", "scadenza acconto precedente alla firma", cols)
    co = blocca_se(rac, co, co.duplicated(["z_ed", "codice_stand"], keep="first"), "R-C15", "QUARANTENA", T, "id_contratto", "stand gia' venduto in questa edizione (altro contratto nel file)", cols)
    co = blocca_se(rac, co, [contr_stand_db.get((int(e), s), i) != i for e, s, i in zip(co.z_ed, co.codice_stand, co.id_contratto)], "R-C15", "QUARANTENA", T, "id_contratto",
                   "stand gia' venduto in questa edizione con un altro contratto nel database", cols)
    riconcilia = rules.costruisci_riconciliatore(list(tutti_esp.items()))
    id_esp, origine, motivo = [], [], []
    for r in co.itertuples():
        if r.id_espositore:
            id_esp.append(r.id_espositore); origine.append("sorgente"); motivo.append(None if r.id_espositore in tutti_esp else "R-C06")
        else:
            d = riconcilia(r.ragione_sociale)
            id_esp.append(d); origine.append("derivato"); motivo.append(None if d else "R-C01")
    co = co.assign(z_esp=id_esp, z_orig=origine, z_mot=motivo)
    for regola, msg in (("R-C06", "id_espositore inesistente"), ("R-C01", "id_espositore assente e nome non riconciliabile in modo univoco")):
        co = blocca_se(rac, co, co.z_mot == regola, regola, "QUARANTENA", T, "id_contratto", msg, cols)
    for r in co.itertuples():
        if r.z_orig == "derivato":
            rac.aggrega("R-C01", "CORRETTO", T, int(r.z_riga), r.id_contratto, "id_espositore derivato dal nome (origine='derivato'): da confermare col BAD")
        elif r.partita_iva and piva_esp.get(r.z_esp) and r.partita_iva != piva_esp[r.z_esp]:
            rac.aggrega("R-C11", "SEGNALATO", T, int(r.z_riga), r.id_contratto, "partita IVA del contratto diversa da quella dell'anagrafica")
        if pd.isna(r.z_acc_p) or pd.isna(r.z_sal_p):
            rac.aggrega("R-C03", "SEGNALATO", T, int(r.z_riga), r.id_contratto, "data di pagamento (acconto o saldo) assente: NULL, nessuno stato dedotto")
        if (r.z_sal_s < r.z_acc_s) or (pd.notna(r.z_acc_p) and pd.notna(r.z_sal_p) and r.z_sal_p < r.z_acc_p):
            rac.aggrega("R-C04", "SEGNALATO", T, int(r.z_riga), r.id_contratto, "date di scadenza/pagamento in ordine incoerente: caricato, da verificare")
    fmt = lambda s: s.dt.strftime("%Y-%m-%d")
    t_con = pd.DataFrame({"id_contratto": co.id_contratto, "edizione": co.z_ed.astype(int), "id_espositore": co.z_esp,
                          "id_espositore_origine": co.z_orig, "ragione_sociale_contratto": co.ragione_sociale, "codice_stand": co.codice_stand,
                          "data_firma": fmt(co.z_firma), "imponibile_listino_eur": co.z_lis, "sconto_pct": co.z_sc, "imponibile_eur": co.z_imp,
                          "acconto_scadenza": fmt(co.z_acc_s), "acconto_pagato_il": fmt(co.z_acc_p), "saldo_scadenza": fmt(co.z_sal_s),
                          "saldo_pagato_il": fmt(co.z_sal_p), "rinnovo": co.z_riv.astype(bool)})
    contratti_stand = {**contr_db, **dict(zip(co.id_contratto, co.codice_stand))}

    # ------------------------------------------------ Righe contratto
    T = "contratto_riga"
    rg = _foglio(x, "Righe_contratto", rac).copy()
    lette += len(rg)
    rg["id_contratto"] = rg.id_contratto.astype(str).str.strip(); rg["codice_voce"] = rg.codice_voce.astype(str).str.strip()
    cols = [c for c in rg.columns if c != "z_riga"]
    rg = rg.assign(z_r=_num(rg.riga), z_q=_num(rg.quantita), z_p=_num(rg.prezzo_unitario_eur), z_i=_num(rg.importo_eur),
                   z_k=rg.id_contratto + "#" + rg.riga.astype(str))
    rg = blocca_se(rac, rg, ~(rg.z_r.notna() & (rg.z_r > 0) & (rg.z_r % 1 == 0)), "R-F03", "SCARTATO", T, "z_k", "numero di riga non valido", cols)
    rg = blocca_se(rac, rg, rg.z_q.isna() | rg.z_p.isna() | rg.z_i.isna(), "R-F03", "SCARTATO", T, "z_k", "quantita', prezzo o importo non numerici", cols)
    dup = rg.duplicated(["id_contratto", "z_r"], keep="first")
    rg = blocca_se(rac, rg, dup & rg.duplicated(cols, keep="first"), "R-F04", "SCARTATO", T, "z_k", "riga identica ripetuta", cols)
    rg = blocca_se(rac, rg, rg.duplicated(["id_contratto", "z_r"], keep="first"), "R-F04", "QUARANTENA", T, "z_k", "stessa riga contratto con valori diversi", cols)
    rg = blocca_se(rac, rg, ~rg.id_contratto.isin(contratti_stand), "R-C16", "QUARANTENA", T, "z_k", "contratto inesistente o non caricato", cols)

    def canonica(r):  # R-C05
        pad, pos, _ = stand[contratti_stand[r.id_contratto]]
        if r.codice_voce == "SPAZIO": return "SPAZIO-" + pad
        if r.codice_voce == "MAGG": return POSIZIONE_MAGG.get(pos)
        return r.codice_voce
    rg = rg.assign(z_v=[canonica(r) for r in rg.itertuples()])
    rg = blocca_se(rac, rg, rg.z_v.isna() | ~rg.z_v.isin(voci), "R-C07", "QUARANTENA", T, "z_k", "voce non a catalogo o maggiorazione non applicabile alla posizione dello stand", cols)
    rg = blocca_se(rac, rg, (rg.z_q <= 0) | (rg.z_p < 0) | (rg.z_i < 0), "R-C17", "QUARANTENA", T, "z_k", "quantita' <= 0 o importi negativi", cols)
    rg = blocca_se(rac, rg, (rg.z_i - (rg.z_q * rg.z_p).round(2)).abs() > 0.01, "R-C17", "QUARANTENA", T, "z_k", "importo diverso da quantita' x prezzo", cols)
    for r in rg.itertuples():
        if r.z_v != r.codice_voce:
            rac.aggrega("R-C05", "CORRETTO", T, int(r.z_riga), r.z_k, "codice voce generico -> codice canonico (originale in codice_voce_origine)")
    t_rig = pd.DataFrame({"id_contratto": rg.id_contratto, "riga": rg.z_r.astype(int), "codice_voce": rg.z_v, "codice_voce_origine": rg.codice_voce,
                          "descrizione": rg.descrizione, "quantita": rg.z_q, "prezzo_unitario_eur": rg.z_p, "importo_eur": rg.z_i})

    tabelle = {"espositore": t_esp, "stand": t_stand, "listino_prezzo": t_list, "contratto": t_con, "contratto_riga": t_rig}
    chiavi = {"espositore": ["id_espositore"], "stand": ["codice_stand"], "listino_prezzo": ["edizione", "codice"],
              "contratto": ["id_contratto"], "contratto_riga": ["id_contratto", "riga"]}
    return Preparato(tabelle, chiavi, rac, lette)

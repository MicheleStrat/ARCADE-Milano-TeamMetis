"""Importatori per fonte: validano e normalizzano SENZA scrivere nel DB (le letture di riferimento usano il cursore).
Regole: BID-01 documento 04. Codici R-F* = controlli di formato introdotti in BID-03 (docs/02_registro_regole.md)."""
import json
from pathlib import Path

import pandas as pd

from . import rules
from .core import FileNonValido, Preparato, Raccolta
from .lettura import blocca_se, doppioni, leggi_csv

TZ = "Europe/Rome"


def _edizione(cur, anno):
    cur.execute("SELECT data_inizio, data_fine FROM arcade.edizione WHERE anno=%s", (anno,))
    r = cur.fetchone()
    if not r:
        raise FileNonValido(f"Edizione {anno} inesistente in arcade.edizione")
    return r


def _locale(serie_naive):
    """Orario locale senza fuso -> Europe/Rome; ambiguo/inesistente -> NaT (verra' scartato)."""
    return serie_naive.dt.tz_localize(TZ, ambiguous="NaT", nonexistent="NaT")


def _iso(ts):
    return ts.dt.strftime("%Y-%m-%d %H:%M:%S%z")


# ===================================================================== BIGLIETTERIA
COL_BIGL = {"ID ordine": "id_ordine", "ID biglietto": "id_biglietto", "Data acquisto": "acquisto", "Canale": "canale",
            "Tipo biglietto": "tipo", "Giorno valido": "giorno", "Prezzo": "prezzo", "Persone": "persone",
            "Fascia eta titolare": "fascia", "Provincia": "provincia", "Codice sconto": "sconto"}


def prepara_biglietteria(cur, percorso, edizione):
    rac = Raccolta()
    df, lette, _ = leggi_csv(percorso, ";", COL_BIGL, rac, "biglietto")
    df = df.rename(columns=COL_BIGL)[[*COL_BIGL.values(), "z_riga"]]
    cols = list(COL_BIGL.values())
    inizio, fine = _edizione(cur, edizione)
    if edizione not in rules.ETICHETTE_TIPO:
        raise FileNonValido(f"Nessuna decodifica delle etichette dei biglietti per l'edizione {edizione} (R-B01)")
    cur.execute("SELECT codice, abbonamento FROM arcade.tipo_biglietto")
    abbonamento = dict(cur.fetchall())
    anno2 = f"{edizione % 100:02d}"
    T = "biglietto"

    # R-F01 formato degli identificativi
    ok = (df.id_ordine.str.fullmatch(rules.RE_ID_ORDINE.pattern) & df.id_biglietto.str.fullmatch(rules.RE_ID_BIGLIETTO.pattern)
          & (df.id_ordine.str[1:3] == anno2) & (df.id_biglietto.str[1:3] == anno2))
    df = blocca_se(rac, df, ~ok, "R-F01", "SCARTATO", T, "id_biglietto", f"ID non valido o di altra edizione (atteso anno {anno2})", cols)
    # doppioni di ID biglietto nello stesso file
    df = doppioni(rac, df, "id_biglietto", cols, "R-F04", T, "id_biglietto", "riga identica ripetuta nel file", "stesso ID con valori diversi nel file", cols)
    # R-F02 / R-F03 date e numeri interpretabili
    df = df.assign(z_acq=_locale(pd.to_datetime(df.acquisto, format="%d/%m/%Y %H:%M", errors="coerce")))
    df = blocca_se(rac, df, df.z_acq.isna(), "R-F02", "SCARTATO", T, "id_biglietto", "data di acquisto non interpretabile", cols)
    gv = df.giorno.str.strip()
    df = df.assign(z_gv=pd.to_datetime(gv.where(~gv.isin(["", "3 giorni"])), format="%d/%m/%Y", errors="coerce"))
    df = blocca_se(rac, df, ~gv.isin(["", "3 giorni"]) & df.z_gv.isna(), "R-F02", "SCARTATO", T, "id_biglietto", "giorno valido non interpretabile", cols)
    pers = df.persone.str.strip()
    df = blocca_se(rac, df, ~pers.str.fullmatch(r"[1-9][0-9]{0,3}"),
                   "R-F03", "SCARTATO", T, "id_biglietto", "numero di persone non valido", cols)
    # R-B05 prezzo
    prezzo = df.prezzo.map(rules.prezzo_decimale)
    df = blocca_se(rac, df, prezzo.isna(), "R-B05", "QUARANTENA", T, "id_biglietto", "prezzo non numerico o negativo", cols)
    # R-B01 tipo
    df = df.assign(z_tipo=df.tipo.map(rules.ETICHETTE_TIPO[edizione]))
    df = blocca_se(rac, df, df.z_tipo.isna(), "R-B01", "QUARANTENA", T, "id_biglietto", "etichetta del tipo biglietto sconosciuta", cols)
    # R-B08 coerenza tipo / giorno valido / giorni dell'edizione
    abb = df.z_tipo.map(abbonamento).astype(bool)
    giorno_ok = df.z_gv.isna() | ((df.z_gv >= pd.Timestamp(inizio)) & (df.z_gv <= pd.Timestamp(fine)))
    coerente = (abb & df.z_gv.isna()) | (~abb & df.z_gv.notna() & giorno_ok)
    df = blocca_se(rac, df, ~coerente, "R-B08", "QUARANTENA", T, "id_biglietto",
                   "abbonamento con giorno singolo, giornaliero senza giorno o giorno fuori dall'edizione", cols)
    # R-B04 fascia / R-B10 canale
    df = blocca_se(rac, df, ~(df.fascia.isin(rules.FASCE_BIGLIETTO) | (df.fascia == "")), "R-B04", "QUARANTENA", T, "id_biglietto", "fascia d'eta' non ammessa", cols)
    df = blocca_se(rac, df, ~df.canale.isin(rules.CANALI), "R-B10", "QUARANTENA", T, "id_biglietto", "canale di vendita sconosciuto", cols)
    # R-B03 provincia
    mappa = {v: rules.sigla_provincia(v) for v in df.provincia.unique()}
    df = df.assign(z_prov=df.provincia.map(lambda v: mappa[v][0]), z_prov_esito=df.provincia.map(lambda v: mappa[v][1]))
    df = blocca_se(rac, df, df.z_prov_esito == "non_riconosciuto", "R-B03", "QUARANTENA", T, "id_biglietto", "provincia non riconosciuta", cols)
    # R-B09 coerenza dei dati d'ordine tra i biglietti dello stesso ordine
    primo = df.groupby("id_ordine")[["acquisto", "canale"]].transform("first")
    diverso = (df.acquisto != primo.acquisto) | (df.canale != primo.canale)
    df = blocca_se(rac, df, diverso, "R-B09", "QUARANTENA", T, "id_biglietto", "data o canale diversi dagli altri biglietti dello stesso ordine", cols)

    # correzioni e segnalazioni, contate solo sui record che arrivano al DB
    for r in df.itertuples():
        if r.giorno == "3 giorni":
            rac.aggrega("R-B02", "CORRETTO", T, int(r.z_riga), r.id_biglietto, '"3 giorni" -> giorno_valido NULL (abbonamento)')
        if r.z_prov_esito == "corretto":
            rac.aggrega("R-B03", "CORRETTO", T, int(r.z_riga), r.id_biglietto, "provincia estesa -> sigla (originale in provincia_origine)")
        elif r.z_prov_esito == "vuoto":
            rac.aggrega("R-B03", "SEGNALATO", T, int(r.z_riga), r.id_biglietto, "provincia vuota: NULL, non imputata")
        if r.fascia == "":
            rac.aggrega("R-B04", "SEGNALATO", T, int(r.z_riga), r.id_biglietto, "fascia d'eta' vuota: NULL, non imputata")
        elif r.fascia in rules.FASCE_MINORI:
            rac.aggrega("R-B06", "SEGNALATO", T, int(r.z_riga), r.id_biglietto, "minorenne: dati individuali mai esposti (solo aggregati)")

    ordine = pd.DataFrame({"id_ordine": df.id_ordine, "edizione": edizione, "data_acquisto": _iso(df.z_acq),
                           "canale": df.canale}).drop_duplicates("id_ordine")
    bigl = pd.DataFrame({"id_biglietto": df.id_biglietto, "id_ordine": df.id_ordine, "edizione": edizione, "tipo": df.z_tipo,
                         "giorno_valido": df.z_gv.dt.strftime("%Y-%m-%d"), "prezzo_eur": prezzo.loc[df.index],
                         "persone": df.persone.str.strip().astype(int), "fascia_eta": df.fascia.replace("", pd.NA),
                         "provincia": df.z_prov, "provincia_origine": df.provincia.replace("", pd.NA),
                         "codice_sconto": df.sconto.replace("", pd.NA)})
    return Preparato({"ordine": ordine, "biglietto": bigl}, {"ordine": ["id_ordine"], "biglietto": ["id_biglietto"]}, rac, lette)


# ===================================================================== TORNELLI
FORMATO_2024 = ["data", "ora", "varco", "codice", "esito"]
FORMATO_2025 = ["timestamp_utc", "ticket_code", "gate_id", "result"]


def prepara_tornelli(cur, percorso, edizione):
    rac = Raccolta()
    intestazione = Path(percorso).read_text(encoding="utf-8-sig").split("\n", 1)[0].strip()
    if ";" in intestazione and all(c in intestazione.split(";") for c in FORMATO_2024):
        df, lette, _ = leggi_csv(percorso, ";", FORMATO_2024, rac, "lettura_tornello")
        ts_locale = _locale(pd.to_datetime(df.data + " " + df.ora, format="%d/%m/%Y %H:%M:%S", errors="coerce"))
        df = df.assign(z_ts=ts_locale, z_varco=df.varco.map(rules.varco_canonico), z_cod=df.codice.str.strip(),
                       z_acc=df.esito.str.strip().map({"1": True, "0": False}))
        formato = "tornelli_v1 (data;ora;varco;codice;esito, orario locale)"
    elif "," in intestazione and all(c in intestazione.split(",") for c in FORMATO_2025):
        df, lette, _ = leggi_csv(percorso, ",", FORMATO_2025, rac, "lettura_tornello")
        df = df.assign(z_ts=pd.to_datetime(df.timestamp_utc, format="%Y-%m-%dT%H:%M:%SZ", errors="coerce", utc=True),
                       z_varco=df.gate_id.map(rules.varco_canonico), z_cod=df.ticket_code.str.strip(),
                       z_acc=df.result.str.strip().map({"OK": True, "KO": False}))
        formato = "tornelli_v2 (timestamp_utc,ticket_code,gate_id,result, UTC)"
    else:
        raise FileNonValido(f"Intestazione dei tornelli non riconosciuta: {intestazione!r}")
    cols = [c for c in df.columns if not c.startswith("z_")]
    T = "lettura_tornello"
    inizio, fine = _edizione(cur, edizione)
    cur.execute("SELECT codice FROM arcade.varco"); varchi = {r[0] for r in cur.fetchall()}
    cur.execute("SELECT id_biglietto FROM arcade.biglietto WHERE edizione=%s", (edizione,)); noti = {r[0] for r in cur.fetchall()}

    df = blocca_se(rac, df, df.z_ts.isna(), "R-F02", "SCARTATO", T, "z_cod", "data/ora non interpretabile", cols)
    df = blocca_se(rac, df, ~df.z_cod.str.fullmatch(rules.RE_ID_BIGLIETTO.pattern), "R-F01", "SCARTATO", T, "z_cod", "codice biglietto con formato non valido", cols)
    df = blocca_se(rac, df, df.z_acc.isna(), "R-F06", "SCARTATO", T, "z_cod", "esito non interpretabile", cols)
    df = blocca_se(rac, df, ~df.z_varco.isin(varchi), "R-T01", "QUARANTENA", T, "z_cod", "varco sconosciuto", cols)
    giorno_locale = df.z_ts.dt.tz_convert(TZ).dt.tz_localize(None).dt.normalize()
    df = blocca_se(rac, df, (giorno_locale < pd.Timestamp(inizio)) | (giorno_locale > pd.Timestamp(fine)), "R-T07", "QUARANTENA", T, "z_cod",
                   f"lettura fuori dai giorni dell'edizione ({inizio} - {fine})", cols)
    noto = df.z_cod.isin(noti)
    df = blocca_se(rac, df, df.z_acc & ~noto, "R-T02", "QUARANTENA", T, "z_cod", "lettura accettata di un codice assente in biglietteria", cols)
    noto = df.z_cod.isin(noti)
    # R-T06 chiave di deduplicazione (edizione, varco, codice, istante)
    df = doppioni(rac, df, ["z_varco", "z_cod", "z_ts"], ["z_varco", "z_cod", "z_ts", "z_acc"], "R-T06", T, "z_cod",
                  "lettura identica (stesso varco, codice, istante, esito) gia' nel file", "stessa chiave con esito diverso nel file", cols)
    noto = df.z_cod.isin(noti)

    for r, n in zip(df.itertuples(), noto):
        if not r.z_acc and not n:
            rac.aggrega("R-T02", "SEGNALATO", T, int(r.z_riga), r.z_cod, "codice assente in biglietteria: lettura respinta conservata, mai conteggiata come ingresso")
        elif not r.z_acc:
            rac.aggrega("R-T03", "SEGNALATO", T, int(r.z_riga), r.z_cod, "KO su biglietto noto (motivo non indicato): conservato, non conteggiato")

    lett = pd.DataFrame({"edizione": edizione, "ts": _iso(df.z_ts.dt.tz_convert("UTC")), "varco": df.z_varco, "codice_letto": df.z_cod,
                         "id_biglietto": df.z_cod.where(noto), "accettata": df.z_acc.astype(bool)})
    return Preparato({"lettura_tornello": lett}, {"lettura_tornello": ["edizione", "varco", "codice_letto", "ts"]}, rac, lette,
                     {"formato": formato})


# ===================================================================== VISITE AGLI STAND
def prepara_visite(cur, percorso, edizione):
    rac = Raccolta()
    cols = ["codice_stand", "data", "ora", "scansioni"]
    df, lette, _ = leggi_csv(percorso, ",", cols, rac, "visita_stand_oraria")
    T = "visita_stand_oraria"
    inizio, fine = _edizione(cur, edizione)
    cur.execute("SELECT codice_stand FROM arcade.stand"); stand = {r[0] for r in cur.fetchall()}
    df = df.assign(z_d=pd.to_datetime(df.data, format="%Y-%m-%d", errors="coerce"))
    k = df.codice_stand + "|" + df.data + "|" + df.ora
    df = df.assign(z_k=k)
    df = blocca_se(rac, df, df.z_d.isna(), "R-F02", "SCARTATO", T, "z_k", "data non interpretabile", cols)
    df = blocca_se(rac, df, ~df.ora.str.fullmatch(r"([01]\d|2[0-3]):00"), "R-F02", "SCARTATO", T, "z_k", "ora non interpretabile o non piena (attesa HH:00)", cols)
    df = blocca_se(rac, df, ~df.scansioni.str.fullmatch(r"\d{1,9}"), "R-F03", "SCARTATO", T, "z_k", "numero di scansioni non valido", cols)
    df = blocca_se(rac, df, ~df.ora.between(rules.ORA_MIN, rules.ORA_MAX), "R-S01", "QUARANTENA", T, "z_k",
                   f"ora fuori dall'apertura {rules.ORA_MIN}-{rules.ORA_MAX}: esclusa dai totali, in attesa di chiarimento col cliente", cols)
    df = blocca_se(rac, df, ~df.codice_stand.isin(stand), "R-S07", "QUARANTENA", T, "z_k", "stand inesistente in planimetria", cols)
    df = blocca_se(rac, df, (df.z_d < pd.Timestamp(inizio)) | (df.z_d > pd.Timestamp(fine)), "R-S08", "QUARANTENA", T, "z_k",
                   f"data fuori dall'edizione ({inizio} - {fine})", cols)
    df = doppioni(rac, df, "z_k", ["z_k", "scansioni"], "R-S09", T, "z_k", "riga identica ripetuta nel file", "stesso stand/data/ora con scansioni diverse nel file", cols)
    v = pd.DataFrame({"edizione": edizione, "codice_stand": df.codice_stand, "data": df.data, "ora": df.ora + ":00",
                      "scansioni": df.scansioni.astype(int)})
    return Preparato({T: v}, {T: ["edizione", "codice_stand", "data", "ora"]}, rac, lette,
                     {"nota": "slot orari mancanti NON imputati (R-S02): assenza di riga = dato assente, non zero"})


# ===================================================================== CONTATTI AGLI STAND
def prepara_contatti(cur, percorso, edizione):
    rac = Raccolta()
    cols = ["id_contatto", "codice_stand", "id_espositore", "timestamp", "email", "fascia_eta", "provincia", "consenso_marketing", "interesse"]
    df, lette, _ = leggi_csv(percorso, ",", cols, rac, "contatto_stand")
    T = "contatto_stand"
    inizio, fine = _edizione(cur, edizione)
    cur.execute("SELECT codice_stand, id_espositore FROM arcade.contratto WHERE edizione=%s", (edizione,))
    contratti = set(cur.fetchall())
    df = df.assign(z_ts=_locale(pd.to_datetime(df.timestamp, format="%Y-%m-%d %H:%M", errors="coerce")))
    df = blocca_se(rac, df, ~df.id_contatto.str.fullmatch(rules.RE_ID_CONTATTO.pattern), "R-F01", "SCARTATO", T, "id_contatto", "ID contatto non valido", cols)
    df = blocca_se(rac, df, df.z_ts.isna(), "R-F02", "SCARTATO", T, "id_contatto", "data/ora non interpretabile", cols)
    df = doppioni(rac, df, "id_contatto", cols, "R-F04", T, "id_contatto", "riga identica ripetuta nel file", "stesso ID con valori diversi nel file", cols)
    giorno = df.z_ts.dt.tz_localize(None).dt.normalize()
    df = blocca_se(rac, df, (giorno < pd.Timestamp(inizio)) | (giorno > pd.Timestamp(fine)), "R-S08", "QUARANTENA", T, "id_contatto", "contatto fuori dai giorni dell'edizione", cols)
    ref_ok = [(s, e) in contratti for s, e in zip(df.codice_stand, df.id_espositore)]
    df = blocca_se(rac, df, ~pd.Series(ref_ok, index=df.index), "R-S10", "QUARANTENA", T, "id_contatto",
                   "nessun contratto di questo espositore su questo stand nell'edizione (riferimento mancante)", cols)
    df = blocca_se(rac, df, ~df.email.str.contains(r"^[^@\s]+@[^@\s]+$", regex=True), "R-S11", "QUARANTENA", T, "id_contatto", "e-mail non valida", cols)
    df = blocca_se(rac, df, ~df.fascia_eta.isin(rules.FASCE_CONTATTO), "R-S12", "QUARANTENA", T, "id_contatto", "fascia d'eta' non ammessa", cols)
    df = blocca_se(rac, df, ~df.consenso_marketing.isin(["SI", "NO", ""]), "R-S04", "QUARANTENA", T, "id_contatto", "consenso non interpretabile (atteso SI/NO/vuoto)", cols)
    mappa = {v: rules.sigla_provincia(v) for v in df.provincia.unique()}
    df = df.assign(z_prov=df.provincia.map(lambda v: mappa[v][0]), z_pe=df.provincia.map(lambda v: mappa[v][1]))
    df = blocca_se(rac, df, df.z_pe == "non_riconosciuto", "R-B03", "QUARANTENA", T, "id_contatto", "provincia non riconosciuta", cols)
    for r in df.itertuples():
        if r.consenso_marketing == "":
            rac.aggrega("R-S04", "CORRETTO", T, int(r.z_riga), r.id_contatto, "consenso vuoto -> NO (consenso_non_registrato = true), da confermare")
        if r.fascia_eta in rules.FASCE_MINORI:
            rac.aggrega("R-S05", "SEGNALATO", T, int(r.z_riga), r.id_contatto, "contatto di minorenne: e-mail e dettaglio mai esposti")
        if r.z_pe == "corretto":
            rac.aggrega("R-B03", "CORRETTO", T, int(r.z_riga), r.id_contatto, "provincia estesa -> sigla")
    c = pd.DataFrame({"id_contatto": df.id_contatto, "edizione": edizione, "codice_stand": df.codice_stand,
                      "id_espositore": df.id_espositore, "ts": _iso(df.z_ts), "email": df.email, "fascia_eta": df.fascia_eta,
                      "provincia": df.z_prov, "consenso_marketing": df.consenso_marketing == "SI",
                      "consenso_non_registrato": df.consenso_marketing == "", "interesse": df.interesse.replace("", pd.NA)})
    return Preparato({T: c}, {T: ["id_contatto"]}, rac, lette)

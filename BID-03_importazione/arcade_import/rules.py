"""Regole di pulizia e normalizzazione (BID-01, documento 04). Funzioni pure, senza accesso al database.

Le regole sono PROPOSTE del team BID: finche' non approvate dal cliente/BAD, ogni trattamento e' reversibile
(valore originale conservato) oppure registrato come anomalia.
"""
import re

# R-B01: decodifica delle etichette del tipo biglietto, per edizione (mappatura 1:1 da confermare, A-B01).
ETICHETTE_TIPO = {
    2024: {"Intero": "INTERO", "Abb. 3gg": "ABB_3GG", "Ridotto": "RIDOTTO", "Family": "FAMILY",
           "Omaggio U8": "GRATUITO_U8", "Business": "BUSINESS", "VIP": "VIP", "Stampa": "STAMPA"},
    2025: {"Giornaliero intero": "INTERO", "Abbonamento 3 giorni": "ABB_3GG", "Giornaliero ridotto 8-14 anni": "RIDOTTO",
           "Family 2 adulti + 2 ragazzi": "FAMILY", "Gratuito under 8": "GRATUITO_U8",
           "Business Day (venerdì mattina)": "BUSINESS", "VIP Experience": "VIP", "Accredito stampa": "STAMPA"},
}

# R-B03: nome esteso della provincia -> sigla.
PROVINCE = {"BERGAMO": "BG", "BOLOGNA": "BO", "BRESCIA": "BS", "COMO": "CO", "CREMONA": "CR", "FIRENZE": "FI",
            "GENOVA": "GE", "LECCO": "LC", "LODI": "LO", "MILANO": "MI", "MONZA E BRIANZA": "MB", "NAPOLI": "NA",
            "NOVARA": "NO", "PADOVA": "PD", "PARMA": "PR", "PAVIA": "PV", "PIACENZA": "PC", "ROMA": "RM",
            "TORINO": "TO", "VARESE": "VA", "VERONA": "VR"}
SIGLE = frozenset(PROVINCE.values())

FASCE_BIGLIETTO = frozenset({"0-7", "8-13", "14-17", "18-24", "25-34", "35-44", "45+", "famiglia"})
FASCE_CONTATTO = FASCE_BIGLIETTO - {"famiglia"}
FASCE_MINORI = frozenset({"0-7", "8-13", "14-17"})  # R-B06

CANALI = frozenset({"Online", "Cassa", "Rivenditore partner"})

RE_ID_ORDINE = re.compile(r"^O[0-9]{8}$")
RE_ID_BIGLIETTO = re.compile(r"^T[0-9]{8}$")
RE_ID_CONTATTO = re.compile(r"^L[0-9]{7}$")
RE_STAND = re.compile(r"^P[0-9]-[A-Z][0-9]{2}$")
RE_ESPOSITORE = re.compile(r"^ESP[0-9]{3}$")
RE_CONTRATTO = re.compile(r"^C[0-9]{4}-[0-9]{4}$")

# Orario di apertura per le scansioni agli stand (R-S01): le ore 09:00 ... 18:00 incluse.
ORA_MIN, ORA_MAX = "09:00", "18:00"


def sigla_provincia(valore):
    """R-B03. Restituisce (sigla|None, esito) con esito in {'ok','corretto','vuoto','non_riconosciuto'}."""
    v = (valore or "").strip().upper()
    if not v:
        return None, "vuoto"
    if v in SIGLE:
        return v, "ok"
    if v in PROVINCE:
        return PROVINCE[v], "corretto"
    return None, "non_riconosciuto"


def prezzo_decimale(valore):
    """R-B05. '55,00' -> '55.00'. None se non numerico o negativo."""
    v = (valore or "").strip().replace(",", ".")
    if not re.fullmatch(r"\d{1,6}(\.\d{1,2})?", v):
        return None
    return v


def varco_canonico(valore):
    """R-T01. 'P1 Nord' -> 'P1-Nord'."""
    return (valore or "").strip().replace(" ", "-")


# --- R-C01: riconciliazione dell'ID espositore dei contratti 2024 tramite il nome ---
_FORMA_LEGALE = r"\b(s\.?\s?p\.?\s?a|s\.?\s?r\.?\s?l\.?\s?s?|s\.?n\.?c|s\.?a\.?s|aps)\b\.?"


def nucleo_nome(nome):
    pulito = re.sub(_FORMA_LEGALE, "", str(nome).lower())
    return re.sub(r"[^a-z0-9 ]", "", pulito).split()


def _singolare(parole):
    return "".join(p[:-1] if p.endswith("s") and len(p) > 4 else p for p in parole)


def costruisci_riconciliatore(espositori):
    """espositori: iterabile di (id_espositore, ragione_sociale).
    Restituisce f(ragione_sociale) -> id_espositore | None. Regola: (1) nome identico dopo normalizzazione;
    (2) altrimenti regola della 's' finale, solo se la corrispondenza e' unica. Altrimenti None (nessuna ipotesi)."""
    esatti = {"".join(nucleo_nome(n)): i for i, n in espositori}
    plurali = {}
    for i, n in espositori:
        plurali.setdefault(_singolare(nucleo_nome(n)), set()).add(i)

    def riconcilia(ragione_sociale):
        chiave = "".join(nucleo_nome(ragione_sociale))
        if chiave in esatti:
            return esatti[chiave]
        cand = plurali.get(_singolare(nucleo_nome(ragione_sociale)), set())
        return next(iter(cand)) if len(cand) == 1 else None
    return riconcilia

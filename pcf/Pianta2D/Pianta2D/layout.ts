/*
 * Pianta2D - disposizione INDICATIVA degli stand per ISOLATI (prova "strada A", 12/11).
 * Il cliente non fornisce la planimetria: la posizione si ricava dal TIPO dello stand,
 * cosi' ogni stand sta in un punto coerente con i lati aperti che il tipo promette.
 *   LINEA    = 1 lato aperto  -> in mezzo a una fila
 *   ANGOLO   = 2 lati aperti  -> in fondo a una fila, contro un corridoio
 *   PENISOLA = 3 lati aperti  -> testata di un isolato (occupa le due file)
 *   ISOLA    = 4 lati aperti  -> da sola, nell'area davanti all'ingresso
 * Struttura del padiglione (dall'alto):
 *   fila a parete (1 o 2 tratti)  ->  fasce di isolati (2 file schiena contro schiena)  ->  area isole  ->  viale e ingresso
 * Dentro ogni gruppo gli stand seguono l'ordine del codice. Le lettere A/B/C del codice NON sono file vere.
 * Tre taglie di larghezza (S fino a 24 m2, M fino a 64, L oltre), stessa altezza: le superfici vere sono scritte nel riquadro e nella scheda.
 * Negli isolati gli stand in linea si accoppiano per taglia, quindi li' l'ordine e' per superficie.
 */

export interface StandIn { codice: string; mq: number; posizione: string; stato: string }
export interface StandOut extends StandIn { fila: string; numero: number; x: number; y: number; w: number; h: number; aperti: string }  // aperti: lati sul corridoio, lettere n s e o
export interface Fascia { fila: string; y: number; h: number }
export interface Corsia { x: number; y: number; w: number; h: number }
export interface Pianta {
    lunghezza: number; larghezza: number;
    stand: StandOut[]; file: Fascia[]; corsie: Corsia[];
    blocchi: Corsia[];   // fondo di ogni isolato e della fila a parete
    ingresso: { x: number; w: number };
}

export const LUNGHEZZA_RHO = 180;
export const LARGHEZZA_RHO = 95;
const MARGINE = 4;      // spazio lungo le pareti laterali e in alto
const VIALE = 8;        // spazio in basso, davanti all'ingresso
const CORRIDOIO = 4;    // corridoio minimo tra due fasce
const TRASVERSALE = 4;  // corsia tra due isolati della stessa fascia
const STACCO = 0.6;     // piccolo stacco tra stand vicini

export function filaDi(codice: string): string {
    const parte = (codice.split("-")[1] || "").trim();
    return parte.charAt(0).toUpperCase() || "?";
}

export function numeroDi(codice: string): number {
    const parte = (codice.split("-")[1] || "").trim();
    const n = parseInt(parte.slice(1), 10);
    return isNaN(n) ? 0 : n;
}

// ordine del codice: fila, poi numero
function perCodice(a: StandIn, b: StandIn): number {
    const fa = filaDi(a.codice), fb = filaDi(b.codice);
    return fa === fb ? numeroDi(a.codice) - numeroDi(b.codice) : fa < fb ? -1 : 1;
}

type Testata = "P" | "AA";
interface Isolato { sx: Testata; dx: Testata; k: number }   // k = stand in linea per fila
interface Tratto { angoli: number; linea: number; angoloSx: boolean; angoloDx: boolean }

interface Schema { tratti: Tratto[]; isolati: Isolato[]; avanzi: number }

/* Sceglie quanti angoli vanno sulla parete, quante testate hanno gli isolati e come si dividono gli stand in linea. */
function progetta(nL: number, nA: number, nP: number, fasceStimate: number): Schema {
    // angoli a parete: un tratto che parte dall'angolo del padiglione ne ha 1, un tratto libero ai due lati ne ha 2
    let angoliParete = -1;
    for (let a = 0; a <= Math.min(4, nA); a++) {
        const resto = nA - a;
        if (resto % 2 !== 0) continue;
        const testate = nP + resto / 2;
        if (testate % 2 === 0) { angoliParete = a; break; }
    }
    let avanzi = 0;   // angoli che non trovano posto coerente (finiscono in linea sulla parete)
    if (angoliParete < 0) {
        // nessuna combinazione perfetta: un angolo va in parete come avanzo
        for (let a = 0; a <= Math.min(4, nA); a++) {
            const resto = nA - a;
            if (resto % 2 === 0 && (nP + resto / 2) % 2 === 1) { angoliParete = a; break; }
        }
        if (angoliParete < 0) angoliParete = Math.min(4, nA);
        avanzi = 1;
    }
    const angoliIsolati = nA - angoliParete;
    const testateAA = Math.floor(angoliIsolati / 2);
    const testate: Testata[] = [];
    // alterna penisole e testate ad angolo, cosi' gli isolati sono vari
    let p = nP, aa = testateAA;
    while (p > 0 || aa > 0) {
        if (p > 0) { testate.push("P"); p--; }
        if (aa > 0) { testate.push("AA"); aa--; }
    }
    if (avanzi && testate.length % 2 === 1) testate.pop();   // la testata rimasta sola torna in parete
    const isolati: Isolato[] = [];
    for (let i = 0; i + 1 < testate.length; i += 2) isolati.push({ sx: testate[i], dx: testate[i + 1], k: 0 });
    const angoliUsatiIsolati = isolati.reduce((s, b) => s + (b.sx === "AA" ? 2 : 0) + (b.dx === "AA" ? 2 : 0), 0);
    const penisoleUsate = isolati.reduce((s, b) => s + (b.sx === "P" ? 1 : 0) + (b.dx === "P" ? 1 : 0), 0);
    const angoliInParete = nA - angoliUsatiIsolati;
    const penisoleInParete = nP - penisoleUsate;   // solo nei casi impossibili: vanno in parete

    // stand in linea: la parete prende circa una fila di lunghezza media, il resto agli isolati
    const righe = 1 + 2 * Math.max(1, fasceStimate);
    const celle = nL + nA + 2 * nP;
    let lineaParete = Math.max(0, Math.round(celle / righe) - angoliInParete);
    if (!isolati.length) lineaParete = nL;
    lineaParete = Math.min(nL, lineaParete);
    let lineaIsolati = nL - lineaParete;
    if (lineaIsolati % 2 === 1) { lineaIsolati--; lineaParete++; }
    const coppie = lineaIsolati / 2;
    isolati.forEach((b, i) => { b.k = Math.floor(coppie / isolati.length) + (i < coppie % isolati.length ? 1 : 0); });

    // tratti a parete: 1 tratto se bastano 2 angoli, altrimenti 2 tratti (una corsia in mezzo)
    const tratti: Tratto[] = [];
    const extra = penisoleInParete;   // penisole senza testata: le teniamo in parete, segnalate dal tipo
    if (angoliInParete <= 2) {
        tratti.push({ angoli: angoliInParete, linea: lineaParete + extra, angoloSx: angoliInParete === 2, angoloDx: angoliInParete >= 1 });
    } else {
        const l1 = Math.ceil(lineaParete / 2);
        tratti.push({ angoli: angoliInParete === 4 ? 2 : 1, linea: l1 + extra, angoloSx: angoliInParete === 4, angoloDx: true });
        tratti.push({ angoli: 2, linea: lineaParete - l1, angoloSx: true, angoloDx: true });
    }
    return { tratti, isolati, avanzi };
}

// taglia di larghezza (12/11): S fino a 24 m2, M fino a 64 m2, L oltre. Stessa altezza per tutti.
export function taglia(mq: number): number { return mq <= 24 ? 1 : mq <= 64 ? 1.5 : 2; }

interface Cella { s: StandIn; riga: 0 | 1 | 2; aperti: string }   // riga 2 = occupa le due file (penisola)
interface Colonna { u: number; celle: Cella[] }
interface Gruppo { colonne: Colonna[] }
const unita = (g: Gruppo) => g.colonne.reduce((t, c) => t + c.u, 0);

/* Mette gli stand veri negli schemi: parete in ordine di codice, isolati accoppiati per taglia. */
function riempi(schema: Schema, L: StandIn[], A: StandIn[], P: StandIn[]): { parete: Gruppo[]; isolati: Gruppo[] } {
    const Lq = L.slice(), Aq = A.slice(), Pq = P.slice();
    const parete: Gruppo[] = schema.tratti.map(t => {
        const colonne: Colonna[] = [];
        const una = (st: StandIn | undefined, aperti: string) => { if (st) colonne.push({ u: taglia(st.mq), celle: [{ s: st, riga: 0, aperti }] }); };
        if (t.angoloSx) una(Aq.shift(), "so");
        for (let j = 0; j < t.linea; j++) una(Lq.length ? Lq.shift() : Pq.shift(), "s");
        if (t.angoloDx) una(Aq.shift(), "se");
        return { colonne };
    });
    // negli isolati gli stand si accoppiano per taglia (sopra e sotto hanno la stessa larghezza)
    const perTaglia = (a: StandIn, b: StandIn) => b.mq - a.mq || perCodice(a, b);
    const Lr = Lq.sort(perTaglia), Ar = Aq.sort(perTaglia);
    const coppieL: StandIn[][] = [];
    for (let i = 0; i + 1 < Lr.length; i += 2) coppieL.push([Lr[i], Lr[i + 1]]);
    // le coppie si distribuiscono a giro, cosi' gli stand grandi non finiscono tutti nello stesso isolato
    const perIsolato: StandIn[][][] = schema.isolati.map(() => []);
    let giro = 0;
    for (const c of coppieL) {
        for (let t = 0; t < schema.isolati.length; t++) {
            const i = (giro + t) % schema.isolati.length;
            if (perIsolato[i].length < schema.isolati[i].k) { perIsolato[i].push(c); giro = i + 1; break; }
        }
    }
    let iA = 0;
    const isolati: Gruppo[] = schema.isolati.map((b, i) => {
        const colonne: Colonna[] = [];
        const testata = (t: Testata, lato: string) => {
            if (t === "P") { const st = Pq.shift(); if (st) colonne.push({ u: taglia(st.mq), celle: [{ s: st, riga: 2, aperti: "ns" + lato }] }); }
            else {
                const su = Ar[iA++], giu = Ar[iA++];
                const celle: Cella[] = [];
                if (su) celle.push({ s: su, riga: 0, aperti: "n" + lato });
                if (giu) celle.push({ s: giu, riga: 1, aperti: "s" + lato });
                if (celle.length) colonne.push({ u: Math.max(...celle.map(c => taglia(c.s.mq))), celle });
            }
        };
        testata(b.sx, "o");
        for (const [su, giu] of perIsolato[i]) {
            colonne.push({ u: Math.max(taglia(su.mq), taglia(giu.mq)), celle: [{ s: su, riga: 0, aperti: "n" }, { s: giu, riga: 1, aperti: "s" }] });
        }
        testata(b.dx, "e");
        return { colonne };
    });
    return { parete, isolati };
}

/* Divide gli isolati in fasce bilanciate per larghezza, in ordine. */
function fasceDi(isolati: Gruppo[], n: number): Gruppo[][] {
    const tot = isolati.reduce((t, g) => t + unita(g), 0);
    const fasce: Gruppo[][] = [];
    let cur: Gruppo[] = [], acc = 0;
    for (const g of isolati) {
        const obiettivo = (tot * (fasce.length + 1)) / n;
        if (cur.length && acc + unita(g) / 2 > obiettivo && fasce.length < n - 1) { fasce.push(cur); cur = []; }
        cur.push(g); acc += unita(g);
    }
    if (cur.length) fasce.push(cur);
    return fasce;
}

export function calcolaPianta(stand: StandIn[], lunghezza = LUNGHEZZA_RHO, larghezza = LARGHEZZA_RHO): Pianta {
    const ingresso = { x: lunghezza / 2 - 9, w: 18 };
    const vuota: Pianta = { lunghezza, larghezza, stand: [], file: [], corsie: [], blocchi: [], ingresso };
    if (!stand.length) return vuota;

    const tipo = (s: StandIn) => (s.posizione || "LINEA").toUpperCase();
    const L = stand.filter(s => !["ANGOLO", "PENISOLA", "ISOLA"].includes(tipo(s))).sort(perCodice);
    const A = stand.filter(s => tipo(s) === "ANGOLO").sort(perCodice);
    const P = stand.filter(s => tipo(s) === "PENISOLA").sort(perCodice);
    const I = stand.filter(s => tipo(s) === "ISOLA").sort(perCodice);

    const lungUtile = lunghezza - 2 * MARGINE;
    const altUtile = larghezza - MARGINE - VIALE;
    const GAP_ISOLE = 2 * TRASVERSALE;

    // larghezza di una "unita'" (taglia S) perche' una riga di gruppi stia nella larghezza utile
    const wRiga = (gruppi: Gruppo[], gap: number) => {
        const u = gruppi.reduce((t, g) => t + unita(g), 0);
        const c = gruppi.reduce((t, g) => t + g.colonne.length, 0);
        return u ? (lungUtile - (gruppi.length - 1) * gap - c * STACCO) / u : Infinity;
    };
    const uIsole = I.reduce((t, s) => t + taglia(s.mq), 0);

    // prova 1..4 fasce di isolati e tiene quella con i quadratini piu' grandi
    interface Prova { parete: Gruppo[]; fasce: Gruppo[][]; w: number; h: number; righe: number }
    let migliore: Prova | null = null;
    for (let n = 1; n <= 4; n++) {
        const schema = progetta(L.length, A.length, P.length, n);
        const { parete, isolati } = riempi(schema, L, A, P);
        const nf = Math.min(n, isolati.length);
        const fasce = isolati.length ? fasceDi(isolati, nf) : [];
        if (isolati.length && fasce.length !== nf) continue;
        const pareteVera = parete.filter(g => g.colonne.length);
        let w = Infinity;
        if (pareteVera.length) w = Math.min(w, wRiga(pareteVera, TRASVERSALE));
        for (const f of fasce) w = Math.min(w, wRiga(f, TRASVERSALE));
        if (I.length) w = Math.min(w, (lungUtile - (I.length + 1) * GAP_ISOLE) / uIsole);
        const righe = (pareteVera.length ? 1 : 0) + 2 * fasce.length + (I.length ? 1 : 0);
        const gruppi = (pareteVera.length ? 1 : 0) + fasce.length + (I.length ? 1 : 0);
        const hMax = (altUtile - CORRIDOIO * (gruppi - 1)) / Math.max(1, righe);
        const h = Math.max(1, Math.min(w * 1.5, hMax));
        const wFin = Math.min(w, h * 1.4);
        if (!migliore || wFin * h > migliore.w * migliore.h) migliore = { parete: pareteVera, fasce, w: wFin, h, righe };
    }
    if (!migliore) return vuota;
    const { parete, fasce, w, h } = migliore;

    // spazio verticale che avanza: va nei corridoi (al massimo 3 volte il minimo)
    const haParete = parete.length > 0;
    const gruppi = (haParete ? 1 : 0) + fasce.length + (I.length ? 1 : 0);
    const avanzo = Math.max(0, altUtile - (h * migliore.righe + CORRIDOIO * (gruppi - 1)));
    // con la fila a parete il blocco parte dal muro: lo spazio in piu' va nei corridoi e sotto, verso il viale
    const corr = gruppi > 1 ? CORRIDOIO + Math.min(avanzo / (haParete ? gruppi : gruppi + 1), CORRIDOIO * 2) : CORRIDOIO;
    const altFinale = h * migliore.righe + corr * (gruppi - 1);
    let y = haParete ? 1 : MARGINE + Math.max(0, (altUtile - altFinale) / 2);

    const out: StandOut[] = [];
    const blocchi: Corsia[] = [];
    const BORDO_BLOCCO = 1.2;
    const blocco = (x0: number, y0: number, x1: number, y1: number) => {
        const top = Math.max(0, y0 - BORDO_BLOCCO);   // la fila a parete non esce dal muro
        blocchi.push({ x: x0 - BORDO_BLOCCO, y: top, w: x1 - x0 + 2 * BORDO_BLOCCO, h: y1 + BORDO_BLOCCO - top });
    };
    const metti = (s: StandIn, x: number, yy: number, ww: number, hh: number, aperti: string) => {
        out.push({ ...s, fila: filaDi(s.codice), numero: numeroDi(s.codice), x, y: yy, w: ww, h: hh, aperti });
    };
    const largRiga = (gr: Gruppo[]) => gr.reduce((t, g) => t + g.colonne.reduce((a, c) => a + c.u * w + STACCO, 0), 0) - STACCO + (gr.length - 1) * (TRASVERSALE - STACCO);

    // disegna una riga di gruppi (parete o fascia di isolati) partendo da x
    const rigaDiGruppi = (gr: Gruppo[], x: number, alt: number) => {
        gr.forEach((g, gi) => {
            const x0 = x;
            for (const c of g.colonne) {
                const cw = c.u * w;
                for (const cella of c.celle) {
                    const cy = cella.riga === 1 ? y + h : y;
                    metti(cella.s, x, cy, cw, cella.riga === 2 ? 2 * h : h, cella.aperti);
                }
                x += cw + STACCO;
            }
            blocco(x0, y, x - STACCO, y + alt);
            if (gi < gr.length - 1) x += TRASVERSALE - STACCO;
        });
    };

    // 1. fila a parete (in alto, la parete fa da schiena)
    if (haParete) {
        // un tratto con un solo angolo parte dall'angolo del padiglione (lato sinistro)
        const daAngolo = parete[0].colonne.length > 0 && !parete[0].colonne[0].celle[0].aperti.includes("o");
        rigaDiGruppi(parete, daAngolo ? MARGINE : MARGINE + (lungUtile - largRiga(parete)) / 2, h);
        y += h;
        if (gruppi > 1) {
            // il resto (isolati e isole) sta al centro dello spazio tra la parete e il viale
            const resto = altFinale - h - corr;
            const spazio = larghezza - VIALE - y;
            y += Math.max(corr, (spazio - resto) / 2);
        }
    }

    // 2. fasce di isolati: due file schiena contro schiena, testate a penisola o ad angolo
    fasce.forEach((f, fi) => {
        rigaDiGruppi(f, MARGINE + (lungUtile - largRiga(f)) / 2, 2 * h);
        y += 2 * h;
        if (fi < fasce.length - 1 || I.length) y += corr;
    });

    // 3. area isole davanti all'ingresso, ognuna con il corridoio tutto intorno
    if (I.length) {
        const larg = uIsole * w + (I.length - 1) * GAP_ISOLE;
        let x = MARGINE + (lungUtile - larg) / 2;
        for (const s of I) {
            const iw = taglia(s.mq) * w;
            metti(s, x, y, iw, h, "nseo"); blocco(x, y, x + iw, y + h); x += iw + GAP_ISOLE;
        }
        y += h;
    }

    // eventuali stand rimasti (non dovrebbe succedere): in coda alla parete per non perderli
    const messi = new Set(out.map(s => s.codice));
    let xr = MARGINE;
    for (const s of stand.filter(st => !messi.has(st.codice))) { metti(s, xr, MARGINE, w, h, ""); xr += w + STACCO; }

    return { lunghezza, larghezza, stand: out, file: [], corsie: [], blocchi, ingresso };
}

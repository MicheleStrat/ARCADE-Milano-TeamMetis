/*
 * Pianta2D - componente PCF per la schermata Planimetria del back-office ARCADE (B-45).
 * Disegna in SVG un padiglione (proporzioni Fiera Milano Rho) con gli stand nella disposizione
 * INDICATIVA ricavata dai codici (vedi layout.ts), colorati per stato commerciale come la legenda dell'app.
 *
 * Input:  StandJson    JSON con l'elenco degli stand del padiglione:
 *                      [{"codice":"P1-A01","mq":36,"posizione":"LINEA","stato":"SOLD"}, ...]
 *                      (accetta anche "commercial_status" al posto di "stato"). Vuoto = dati demo.
 *         Padiglione   testo mostrato in alto (es. "P1 · Console & PC")
 *         Selezionato  codice dello stand da evidenziare (lo decide l'app)
 * Output: StandCliccato codice dell'ultimo stand toccato (fa scattare OnChange in Power Apps)
 */
import { IInputs, IOutputs } from "./generated/ManifestTypes";
import { calcolaPianta, StandIn, StandOut, Pianta, LUNGHEZZA_RHO } from "./layout";

const SVG = "http://www.w3.org/2000/svg";
const TESTO = "#1B2033", TESTO_SEC = "#5A6275", BORDO = "#D9DEE8", SELEZIONE = "#4338CA";

// stessi colori di statiStand (App.Formulas) e del mockup
const STATI: Record<string, { testo: string; bg: string; fg: string }> = {
    AVAILABLE: { testo: "Disponibile", bg: "#DCFCE7", fg: "#166534" },
    RESERVED: { testo: "Riservato", bg: "#FEF3C7", fg: "#92400E" },
    SOLD: { testo: "Venduto", bg: "#E0E7FF", fg: "#3730A3" },
    FREE: { testo: "Gratuito", bg: "#CFFAFE", fg: "#155E75" },
    NOT_SELLABLE: { testo: "Non vendibile", bg: "#F1F5F9", fg: "#475569" },
};
const SIMBOLI: Record<string, string> = { AVAILABLE: "✓", RESERVED: "◷", SOLD: "∘", FREE: "∘", NOT_SELLABLE: "—" };
const POSIZIONI: Record<string, string> = { LINEA: "Linea", ANGOLO: "Angolo", PENISOLA: "Penisola", ISOLA: "Isola" };

function el<K extends keyof SVGElementTagNameMap>(tag: K, attr: Record<string, string | number>, testo?: string): SVGElementTagNameMap[K] {
    const e = document.createElementNS(SVG, tag);
    for (const k of Object.keys(attr)) e.setAttribute(k, String(attr[k]));
    if (testo !== undefined) e.textContent = testo;
    return e;
}

function demo(): StandIn[] {
    const mq = [36, 64, 48, 144, 96, 36, 144, 144, 48, 64, 36, 48, 18, 36, 24];
    const pos = ["ANGOLO", "LINEA", "LINEA", "ISOLA", "LINEA", "LINEA", "PENISOLA", "LINEA", "LINEA", "LINEA", "LINEA", "LINEA", "LINEA", "LINEA", "ANGOLO"];
    const stati = ["SOLD", "SOLD", "AVAILABLE", "SOLD", "RESERVED", "SOLD", "AVAILABLE", "SOLD", "FREE", "SOLD", "AVAILABLE", "SOLD", "NOT_SELLABLE", "SOLD", "AVAILABLE"];
    const out: StandIn[] = [];
    ["A", "B", "C"].forEach((f, r) => {
        for (let i = 0; i < 15; i++) {
            const j = (i + r * 4) % 15;
            out.push({ codice: `P1-${f}${String(i + 1).padStart(2, "0")}`, mq: mq[j], posizione: pos[j], stato: stati[j] });
        }
    });
    return out;
}

export class Pianta2D implements ComponentFramework.StandardControl<IInputs, IOutputs> {
    private box!: HTMLDivElement;
    private titolo!: HTMLDivElement;
    private svg!: SVGSVGElement;
    private notify!: () => void;
    private pianta: Pianta | null = null;
    private lastJson: string | null = null;
    private lastSelInput: string | null = null;
    private selezionato = "";
    private cliccato = "";
    private lastLarg = 0;
    private demoAttiva = false;
    private testo = { completo: false, simbolo: true, fs: 2.5, pad: 1 };

    public init(context: ComponentFramework.Context<IInputs>, notifyOutputChanged: () => void, _state: ComponentFramework.Dictionary, container: HTMLDivElement): void {
        this.notify = notifyOutputChanged;
        context.mode.trackContainerResize(true);
        this.box = document.createElement("div");
        this.box.style.cssText = "position:relative;width:100%;height:100%;overflow:hidden;pointer-events:auto;font-family:'Segoe UI',system-ui,sans-serif;color:" + TESTO;
        this.titolo = document.createElement("div");
        this.titolo.style.cssText = "position:absolute;left:4px;top:0;right:4px;display:flex;justify-content:space-between;align-items:baseline;gap:12px;font-size:12px;pointer-events:none";
        this.svg = document.createElementNS(SVG, "svg");
        this.svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
        this.svg.style.cssText = "position:absolute;left:0;top:20px;width:100%;height:400px;pointer-events:auto";
        this.box.appendChild(this.titolo);
        this.box.appendChild(this.svg);
        container.appendChild(this.box);
    }

    public updateView(context: ComponentFramework.Context<IInputs>): void {
        // misure in pixel: il contenitore non sempre ha un'altezza propria (banco di prova)
        const w = Math.max(200, Math.round(context.mode.allocatedWidth > 0 ? context.mode.allocatedWidth : this.box.clientWidth || 746));
        const h = Math.max(160, Math.round(context.mode.allocatedHeight > 0 ? context.mode.allocatedHeight : this.box.clientHeight || 420));
        this.box.style.width = w + "px";
        this.box.style.height = h + "px";
        this.svg.style.height = (h - 20) + "px";

        // forma del padiglione = forma dello spazio disponibile (lunghezza fissa 180, larghezza in proporzione)
        const larg = Math.max(40, Math.round(((LUNGHEZZA_RHO + 6) * (h - 20) / w - 8) * 10) / 10);
        const json = context.parameters.StandJson.raw || "";
        if (json !== this.lastJson || larg !== this.lastLarg) {
            this.lastJson = json;
            this.lastLarg = larg;
            let elenco: StandIn[] = [];
            this.demoAttiva = false;
            try {
                const dati = json.trim() ? JSON.parse(json) : null;
                if (Array.isArray(dati)) {
                    elenco = dati.map((d: Record<string, unknown>) => ({
                        codice: String(d.codice ?? ""),
                        mq: Number(d.mq ?? 0),
                        posizione: String(d.posizione ?? "LINEA"),
                        stato: String(d.stato ?? d.commercial_status ?? "AVAILABLE"),
                    })).filter(s => s.codice);
                }
            } catch {
                elenco = [];
            }
            // vuoto o non valido (es. "val" del banco di prova) = dati demo
            if (!elenco.length) { elenco = demo(); this.demoAttiva = true; }
            this.pianta = calcolaPianta(elenco, LUNGHEZZA_RHO, larg);
        }
        const selIn = context.parameters.Selezionato.raw || "";
        if (selIn !== this.lastSelInput) {
            this.lastSelInput = selIn;
            this.selezionato = selIn;
        }
        const nome = context.parameters.Padiglione.raw || "";
        this.titolo.innerHTML = "";
        const sx = document.createElement("span");
        sx.style.cssText = "font-weight:600";
        sx.textContent = nome + (this.demoAttiva ? " · dati demo" : "");
        // la nota "disposizione indicativa" sta sotto la legenda nell'app, qui resta solo il titolo
        this.titolo.appendChild(sx);
        this.disegna();
    }

    public getOutputs(): IOutputs {
        return { StandCliccato: this.cliccato };
    }

    public destroy(): void {
        this.box.remove();
    }

    private disegna(): void {
        const svg = this.svg;
        while (svg.firstChild) svg.removeChild(svg.firstChild);
        const p = this.pianta;
        if (!p) return;
        svg.setAttribute("viewBox", `-3 -2 ${p.lunghezza + 6} ${p.larghezza + 8}`);

        // padiglione e ingresso
        svg.appendChild(el("rect", { x: 0, y: 0, width: p.lunghezza, height: p.larghezza, rx: 3, fill: "#F8FAFC", stroke: BORDO, "stroke-width": 0.6 }));
        svg.appendChild(el("rect", { x: p.ingresso.x, y: p.larghezza - 1, width: p.ingresso.w, height: 2, fill: "#FFFFFF" }));
        svg.appendChild(el("path", { d: `M${p.lunghezza / 2 - 2.5} ${p.larghezza + 4.5} L${p.lunghezza / 2} ${p.larghezza + 1.5} L${p.lunghezza / 2 + 2.5} ${p.larghezza + 4.5} Z`, fill: TESTO_SEC }));
        svg.appendChild(el("text", { x: p.lunghezza / 2 + 4, y: p.larghezza + 4.6, "font-size": 2.8, fill: TESTO_SEC }, "Ingresso"));

        // muro in alto: la fila a parete ci appoggia la schiena
        svg.appendChild(el("path", { d: `M1.5 0 H${p.lunghezza - 1.5}`, stroke: "#94A3B8", "stroke-width": 1.4, "stroke-linecap": "round", fill: "none" }));
        // fondo degli isolati: un blocco = un gruppo di stand schiena contro schiena
        for (const b of p.blocchi) {
            svg.appendChild(el("rect", { x: b.x, y: b.y, width: b.w, height: b.h, rx: 1.6, fill: "#E8ECF4" }));
        }
        // viale davanti all'ingresso
        svg.appendChild(el("text", { x: p.lunghezza / 2, y: p.larghezza - 2.6, "font-size": 2.6, "text-anchor": "middle", fill: TESTO_SEC, "letter-spacing": 0.4 }, "VIALE"));

        // nomi delle file
        for (const f of p.file) {
            svg.appendChild(el("text", { x: -4.5, y: f.y + f.h / 2 + 1.4, "font-size": 4, "font-weight": 600, "text-anchor": "middle", fill: TESTO_SEC }, f.fila));
        }

        // testo uguale per tutti gli stand del padiglione: si sceglie la variante con il carattere maggiore
        //   1) simbolo + codice completo   2) simbolo + codice corto   3) solo codice corto (lo stato resta nel colore)
        if (p.stand.length) {
            const w = Math.min(...p.stand.map(s => s.w));
            const h = Math.min(...p.stand.map(s => s.h));
            const pad = Math.max(0.7, w * 0.08);
            const lungo = Math.max(...p.stand.map(s => s.codice.length));
            const breve = Math.max(...p.stand.map(s => (s.codice.split("-")[1] || s.codice).length));
            // anche la riga dei m2 deve starci (si guarda lo stand piu' stretto con la superficie piu' lunga da scrivere)
            const strette = p.stand.filter(s => s.w <= w + 0.01);
            const mqLungo = Math.max(...strette.map(s => `${s.mq} m²`.length)) * 0.85;
            const misura = (n: number, sim: boolean) => Math.min(3.9, (w - 2 * pad) / (Math.max(n + (sim ? 1.6 : 0), mqLungo) * 0.6), h / 3.2);
            let scelta = { completo: false, simbolo: true, fs: misura(breve, true), pad };
            if (misura(lungo, true) >= 3.4) scelta = { completo: true, simbolo: true, fs: misura(lungo, true), pad };
            else if (scelta.fs < 3.0) scelta = { completo: false, simbolo: false, fs: misura(breve, false), pad };
            this.testo = scelta;
        }
        // stand
        for (const s of p.stand) svg.appendChild(this.disegnaStand(s));
    }

    private disegnaStand(s: StandOut): SVGGElement {
        const st = STATI[s.stato] || STATI.AVAILABLE;
        const sel = s.codice === this.selezionato;
        const g = el("g", { cursor: "pointer" });
        g.appendChild(el("title", {}, `${s.codice} · ${s.mq} m² · ${POSIZIONI[s.posizione] || s.posizione} · ${st.testo}`));
        // quadratino come nella griglia: angoli arrotondati, bordo tenue dello stesso colore
        const rx = Math.min(2.2, s.w * 0.16);
        g.appendChild(el("rect", {
            x: s.x, y: s.y, width: Math.max(0.5, s.w), height: s.h, rx,
            fill: st.bg,
            stroke: sel ? SELEZIONE : st.fg,
            "stroke-opacity": sel ? 1 : 0.28,
            "stroke-width": sel ? 0.9 : 0.35,
        }));
        // lati aperti sul corridoio: segno discreto dentro il bordo (angolo 2, penisola 3, isola 4)
        if (!sel) {
            const d = 0.45, x0 = s.x + d, x1 = s.x + s.w - d, y0 = s.y + d, y1 = s.y + s.h - d;
            const lati: Record<string, string> = { n: `M${x0 + rx} ${y0} H${x1 - rx}`, s: `M${x0 + rx} ${y1} H${x1 - rx}`, o: `M${x0} ${y0 + rx} V${y1 - rx}`, e: `M${x1} ${y0 + rx} V${y1 - rx}` };
            for (const l of s.aperti || "") {
                if (lati[l]) g.appendChild(el("path", { d: lati[l], stroke: st.fg, "stroke-opacity": 0.5, "stroke-width": 0.5, "stroke-linecap": "round", fill: "none" }));
            }
        }
        // testo: stessa misura e stessa variante per tutto il padiglione (calcolate in disegna)
        const t = this.testo;
        const pad = t.pad;
        const etichetta = t.completo ? s.codice : (s.codice.split("-")[1] || s.codice);
        const simbolo = t.simbolo ? (SIMBOLI[s.stato] || "") : "";
        const fs = t.fs;
        if (fs >= 1.3) {
            const riga1 = el("text", { x: s.x + pad, y: s.y + pad + fs * 0.95, "font-size": fs, "font-weight": 700, fill: st.fg });
            if (simbolo) {
                const ts = document.createElementNS(SVG, "tspan");
                ts.textContent = simbolo;
                riga1.appendChild(ts);
            }
            const tc = document.createElementNS(SVG, "tspan");
            if (simbolo) tc.setAttribute("dx", String(fs * 0.35));   // lo spazio nel tspan viene ignorato
            tc.textContent = etichetta;
            riga1.appendChild(tc);
            g.appendChild(riga1);
            g.appendChild(el("text", { x: s.x + pad, y: s.y + pad + fs * 2.3, "font-size": fs * 0.85, "font-weight": 600, fill: st.fg }, `${s.mq} m²`));
        }
        // pointerup + click: alcuni host (Power Apps) bloccano il click sintetico; seleziona() ignora il doppione
        const seleziona = (ev: Event) => {
            ev.stopPropagation();
            if (this.cliccato === s.codice && this.selezionato === s.codice) return;
            this.selezionato = s.codice;
            this.cliccato = s.codice;
            this.notify();
            // ridisegna dopo che l'evento e' finito (l'elemento cliccato viene sostituito)
            window.setTimeout(() => this.disegna(), 0);
        };
        g.addEventListener("pointerup", seleziona);
        g.addEventListener("click", seleziona);
        return g;
    }
}

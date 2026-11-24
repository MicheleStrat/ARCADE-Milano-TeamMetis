/*
 * Mappa3D - componente PCF per la schermata Live del back-office ARCADE (B-64, B-66). Versione 0.0.13 (24/11: padiglioni in colonna in "Tutti", apertura sul primo padiglione, comandi in una riga in basso).
 * Nata dal prototipo sandbox (0.0.11) e adattata ai dati veri:
 *   - posizione degli stand con lo STESSO calcolo della Planimetria (layout.ts della Pianta2D, disposizione indicativa)
 *   - una sola grandezza: PERSONE ALLO STAND (sensori quando ci sono, altrimenti scansioni allo stand)
 *   - niente corridoi: nel DB non ci sono passaggi nei corridoi
 * Vista guidata (niente rotazione/zoom liberi) su tre livelli: tutti i padiglioni -> un padiglione -> uno stand.
 * Comandi: schede padiglioni, ricerca stand/espositore, + / -, "Reimposta vista", 3D / Pianta, legenda,
 *          barra delle ore (tutto il giorno oppure un'ora alla volta, con il tasto play).
 * Input:   DatiJson   JSON della vista live.v_map_stand filtrata su un giorno, cioe' un elenco di righe
 *                     [{"padiglione":"P1","padiglione_nome":"Console & PC","codice":"P1-A01","mq":36,"posizione":"LINEA",
 *                       "stato":"SOLD","espositore":"...","fonte":"SENSORI","ora_inizio":9,"persone":120,"persone_ore":"10,25,40"}]
 *                     Vuoto o non valido = dati demo con l'etichetta "Dati simulati".
 *          Padiglione codice del padiglione da mostrare (P1...) oppure "tutti"
 *          Modalita   non piu' usata (resta per compatibilita' con le app che l'avevano impostata)
 * Output:  StandSelezionato, PadiglioneMostrato
 * I dettagli dello stand (contratto, ecc.) li mostra Power Apps leggendo StandSelezionato.
 */
import * as THREE from "three";
import { IInputs, IOutputs } from "./generated/ManifestTypes";
import { calcolaPianta, StandIn, Pianta, LUNGHEZZA_RHO } from "./layout";

interface Padiglione { codice: string; nome: string; x: number; z: number; lunghezza: number; larghezza: number; ingresso: { x: number; w: number } }
interface Stand { padiglione: string; codice: string; posizione: string; stato: string; mq: number; x: number; y: number; w: number; h: number; aperti: string; persone: number; espositore: string; persone_ore: number[] }
// Tratto di corridoio (B-69): calcolato dalla pianta; il valore e' la SOMMA delle persone agli stand che ci si affacciano (stima, non un conteggio nel corridoio)
interface Tratto { padiglione: string; x: number; y: number; w: number; h: number; oriz: boolean; stand: string[]; persone: number; persone_ore: number[] }
interface Blocco { padiglione: string; x: number; y: number; w: number; h: number }
interface Dati { padiglioni: Padiglione[]; stand: Stand[]; blocchi: Blocco[]; tratti: Tratto[]; ore: string[]; fonte: string }
interface Riga { padiglione?: unknown; padiglione_nome?: unknown; codice?: unknown; mq?: unknown; posizione?: unknown; stato?: unknown; espositore?: unknown; fonte?: unknown; ora_inizio?: unknown; persone?: unknown; persone_ore?: unknown }
interface Etichetta { el: HTMLDivElement; pos: THREE.Vector3; pad: string; tipo: "stand" | "fisso"; w?: number }

const DISTANZA_PADIGLIONI = 40;   // metri tra un padiglione e il successivo: padiglioni in colonna (P1 in alto), davanti a ognuno la sua corsia d'ingresso
// Stessa forma del padiglione della Planimetria: pcfPianta su scrPlanimetria e' 778 x 418, e la Pianta2D
// ricava la larghezza come ((180 + 6) * (418 - 20) / 778 - 8) = 87,2. Con la stessa larghezza calcolaPianta
// dispone gli stand esattamente come in Planimetria. Se pcfPianta cambia misure, va aggiornato questo numero.
const LARGHEZZA_PLANIMETRIA = Math.round(((LUNGHEZZA_RHO + 6) * (418 - 20) / 778 - 8) * 10) / 10;

// ---------- palette dell'app (design system BAD) ----------
const INK = "#1B2033", INK2 = "#374151", MUTED = "#5A6275", LINE = "#D9DEE8", ACCENT = "#4338CA";
const SEQ = ["#EEF2FF", "#E0E7FF", "#C7D2FE", "#A5B4FC", "#818CF8", "#6366F1", "#4F46E5", "#3730A3"];
const SFONDO = "#EEF0F5";

function scala(stops: string[], t: number): THREE.Color {
    t = Math.max(0, Math.min(1, t));
    const p = t * (stops.length - 1), i = Math.min(stops.length - 2, Math.floor(p));
    return new THREE.Color(stops[i]).lerp(new THREE.Color(stops[i + 1]), p - i);
}
const fmt = (n: number) => n.toLocaleString("it-IT");
const css = (el: HTMLElement, s: string) => { el.style.cssText = s; return el; };
function crea<K extends keyof HTMLElementTagNameMap>(tag: K, stile: string, testo?: string): HTMLElementTagNameMap[K] {
    const el = document.createElement(tag); el.style.cssText = stile; if (testo !== undefined) el.textContent = testo; return el;
}
const BTN = `min-height:44px;padding:0 12px;border:0;border-radius:9px;background:transparent;font:500 13px 'Segoe UI',system-ui,sans-serif;color:${INK2};cursor:pointer;white-space:nowrap`;
const PANEL = `background:rgba(255,255,255,.96);border:1px solid ${LINE};border-radius:12px`;
const POSIZIONI: Record<string, string> = { ANGOLO: "angolo", LINEA: "in linea", PENISOLA: "penisola", ISOLA: "isola" };

/** Righe della vista (o dati demo) -> padiglioni e stand con le posizioni calcolate come in Planimetria. */
function prepara(righe: Riga[]): Dati {
    const num = (v: unknown) => { const n = Number(v); return isFinite(n) ? n : 0; };
    const txt = (v: unknown) => (v === null || v === undefined ? "" : String(v));
    const padDi = (r: Riga) => txt(r.padiglione) || txt(r.codice).split("-")[0];
    const valide = righe.filter(r => /^P[0-9]+-[A-Z][0-9]{2}$/.test(txt(r.codice)));
    const codiciPad = Array.from(new Set(valide.map(padDi))).sort((a, b) => num(a.slice(1)) - num(b.slice(1)));
    const ora0 = valide.length ? num(valide[0].ora_inizio) : 9;
    const nOre = Math.max(0, ...valide.map(r => (txt(r.persone_ore) ? txt(r.persone_ore).split(",").length : 0)));
    const ore = Array.from({ length: nOre }, (_, i) => `${String(ora0 + i).padStart(2, "0")}:00`);
    const fonte = valide.length ? txt(valide[0].fonte) : "";
    const dati: Dati = { padiglioni: [], stand: [], blocchi: [], tratti: [], ore, fonte };
    codiciPad.forEach((cod, i) => {
        const proprie = valide.filter(r => padDi(r) === cod);
        const nome = txt(proprie[0]?.padiglione_nome);
        const elenco: StandIn[] = proprie.map(r => ({ codice: txt(r.codice), mq: num(r.mq), posizione: txt(r.posizione) || "LINEA", stato: txt(r.stato) || "AVAILABLE" }));
        const p = spezzaIsolatiLunghi(calcolaPianta(elenco, LUNGHEZZA_RHO, LARGHEZZA_PLANIMETRIA));
        dati.padiglioni.push({ codice: cod, nome: nome ? `${cod} · ${nome}` : cod, x: 0, z: i * (LARGHEZZA_PLANIMETRIA + DISTANZA_PADIGLIONI), lunghezza: p.lunghezza, larghezza: p.larghezza, ingresso: p.ingresso });
        for (const b of p.blocchi) dati.blocchi.push({ padiglione: cod, x: b.x, y: b.y, w: b.w, h: b.h });
        for (const s of p.stand) {
            const r = proprie.find(x => txt(x.codice) === s.codice) as Riga;
            const ore1 = txt(r.persone_ore) ? txt(r.persone_ore).split(",").map(num) : [];
            while (ore1.length < nOre) ore1.push(0);
            dati.stand.push({
                padiglione: cod, codice: s.codice, posizione: s.posizione, stato: s.stato, mq: s.mq,
                x: s.x, y: s.y, w: s.w, h: s.h, aperti: s.aperti || "",
                persone: num(r.persone), espositore: txt(r.espositore), persone_ore: ore1,
            });
        }
        dati.tratti.push(...corridoi(cod, p.lunghezza, p.larghezza, p.blocchi, dati.stand.filter(s => s.padiglione === cod), nOre));
    });
    return dati;
}

/**
 * Solo nella mappa 3D (B-70): un isolato piu' lungo di 120 m (oggi il P3) viene diviso da un passaggio di 4 m.
 * Il taglio cade tra due colonne di stand, il piu' vicino al passaggio della fila a parete (se c'e') o al centro dell'isolato;
 * gli stand dell'isolato si restringono un po' in larghezza per fargli spazio. Ordine e file restano quelli della Planimetria,
 * che non cambia (la Pianta2D non usa questa funzione).
 */
function spezzaIsolatiLunghi(p: Pianta): Pianta {
    const PASSAGGIO = 4, LUNGO = 120;
    const parete = p.blocchi.filter(b => b.y < 1).sort((a, b) => a.x - b.x);
    const varchi: number[] = [];
    for (let i = 0; i + 1 < parete.length; i++) varchi.push((parete[i].x + parete[i].w + parete[i + 1].x) / 2);
    const blocchi: typeof p.blocchi = [];
    for (const b of p.blocchi) {
        if (b.y < 1 || b.w <= LUNGO) { blocchi.push(b); continue; }
        const dentro = p.stand.filter(s => s.x >= b.x - 0.5 && s.x + s.w <= b.x + b.w + 0.5 && s.y >= b.y - 0.5 && s.y + s.h <= b.y + b.h + 0.5);
        const bordi = Array.from(new Set(dentro.map(s => Math.round(s.x * 100) / 100))).filter(x => x > b.x + 20 && x < b.x + b.w - 20);
        if (!bordi.length) { blocchi.push(b); continue; }
        const centro = b.x + b.w / 2;
        const mira = varchi.length ? varchi.reduce((m, v) => (Math.abs(v - centro) < Math.abs(m - centro) ? v : m)) : centro;
        const taglio = bordi.reduce((m, x) => (Math.abs(x - mira) < Math.abs(m - mira) ? x : m));
        const k = (b.w - PASSAGGIO) / b.w;
        for (const s of dentro) {
            const dopo = s.x >= taglio - 0.01;
            s.x = b.x + (s.x - b.x) * k + (dopo ? PASSAGGIO : 0);
            s.w = s.w * k;
        }
        const wSx = (taglio - b.x) * k;
        blocchi.push({ x: b.x, y: b.y, w: wSx, h: b.h });
        blocchi.push({ x: b.x + wSx + PASSAGGIO, y: b.y, w: b.w - wSx - PASSAGGIO, h: b.h });
    }
    return { ...p, blocchi };
}

/**
 * Tratti di corridoio di un padiglione, ricavati dagli isolati della pianta (B-69).
 * Orizzontali: tra una fila di isolati e la successiva, e davanti all'ultima verso l'ingresso; tagliati dove cominciano e finiscono
 * gli isolati sopra e sotto. Verticali: tra due isolati della stessa fila e ai lati.
 * Ogni stand si assegna al tratto davanti a ciascun lato aperto; il tratto somma le persone dei suoi stand.
 */
function corridoi(cod: string, lung: number, larg: number, blocchi: { x: number; y: number; w: number; h: number }[], stand: Stand[], nOre: number): Tratto[] {
    const out: Tratto[] = [];
    if (!blocchi.length) return out;
    const nuovo = (x: number, y: number, w: number, h: number, oriz: boolean) => {
        if (w > 1.5 && h > 1.5) out.push({ padiglione: cod, x, y, w, h, oriz, stand: [], persone: 0, persone_ore: new Array(nOre).fill(0) });
    };
    // file di isolati (stessa y)
    const file: { y0: number; y1: number; b: typeof blocchi }[] = [];
    for (const b of [...blocchi].sort((a, c) => a.y - c.y || a.x - c.x)) {
        const f = file.find(r => Math.abs(r.y0 - b.y) < 0.5);
        if (f) { f.b.push(b); f.y1 = Math.max(f.y1, b.y + b.h); } else file.push({ y0: b.y, y1: b.y + b.h, b: [b] });
    }
    const x0 = 1, x1 = lung - 1;
    const tagli = (bs: typeof blocchi) => bs.flatMap(b => [b.x, b.x + b.w]);
    // orizzontali
    for (let i = 0; i < file.length; i++) {
        const ya = file[i].y1, yb = i + 1 < file.length ? file[i + 1].y0 : larg - 1;
        const xs = Array.from(new Set([x0, x1, ...tagli(file[i].b), ...(i + 1 < file.length ? tagli(file[i + 1].b) : [])]))
            .filter(x => x >= x0 && x <= x1).sort((a, b) => a - b);
        const pezzi: number[] = [xs[0]];
        for (const x of xs.slice(1)) if (x - pezzi[pezzi.length - 1] >= 8) pezzi.push(x); else pezzi[pezzi.length - 1] = x;
        if (pezzi[0] > x0) pezzi.unshift(x0);
        for (let k = 0; k + 1 < pezzi.length; k++) nuovo(pezzi[k], ya, pezzi[k + 1] - pezzi[k], yb - ya, true);
    }
    // verticali: tra isolati della stessa fila e ai lati
    for (const f of file) {
        const bs = [...f.b].sort((a, b) => a.x - b.x);
        let xa = x0;
        for (const b of bs) { nuovo(xa, f.y0, b.x - xa, f.y1 - f.y0, false); xa = b.x + b.w; }
        nuovo(xa, f.y0, x1 - xa, f.y1 - f.y0, false);
    }
    // stand -> tratti davanti ai lati aperti
    const dentro = (px: number, py: number) => out.find(c => px >= c.x && px <= c.x + c.w && py >= c.y && py <= c.y + c.h);
    for (const s of stand) {
        const cx = s.x + s.w / 2, cy = s.y + s.h / 2, d = 1.5;
        const punti: Record<string, [number, number]> = { n: [cx, s.y - d], s: [cx, s.y + s.h + d], o: [s.x - d, cy], e: [s.x + s.w + d, cy] };
        const visti = new Set<Tratto>();
        for (const l of s.aperti) {
            const pt = punti[l]; if (!pt) continue;
            const c = dentro(pt[0], pt[1]);
            if (c && !visti.has(c)) {
                visti.add(c); c.stand.push(s.codice); c.persone += s.persone;
                s.persone_ore.forEach((v, i) => { c.persone_ore[i] += v; });
            }
        }
    }
    return out;
}

/** Dati demo inventati: tre padiglioni, persone dalle 9 alle 15 (usati solo con DatiJson vuoto). */
function demo(): Riga[] {
    const mq = [36, 64, 48, 144, 96, 36, 144, 144, 48, 64, 36, 48, 18, 36, 24];
    const pos = ["ANGOLO", "LINEA", "LINEA", "ISOLA", "LINEA", "LINEA", "PENISOLA", "LINEA", "LINEA", "LINEA", "LINEA", "LINEA", "LINEA", "LINEA", "ANGOLO"];
    const nomi = ["Console & PC", "Esports & Community", "Indie, Retro & Cosplay"];
    const curva = [0.35, 0.7, 1, 0.95, 0.8, 0.9];
    const out: Riga[] = [];
    let seme = 7;
    const caso = () => { seme = (seme * 9301 + 49297) % 233280; return seme / 233280; };
    nomi.forEach((nome, pi) => {
        ["A", "B", "C"].forEach((f, r) => {
            for (let i = 0; i < 15; i++) {
                const j = (i + r * 4 + pi * 2) % 15;
                const base = (20 + Math.round(caso() * 120)) * (pos[j] === "ISOLA" ? 1.6 : 1);
                const ore = curva.map(c => Math.round(base * c * (0.8 + caso() * 0.4)));
                out.push({
                    padiglione: `P${pi + 1}`, padiglione_nome: nome, codice: `P${pi + 1}-${f}${String(i + 1).padStart(2, "0")}`,
                    mq: mq[j], posizione: pos[j], stato: "SOLD", espositore: "", fonte: "SENSORI", ora_inizio: 9,
                    persone: ore.reduce((a, b) => a + b, 0), persone_ore: ore.join(","),
                });
            }
        });
    });
    return out;
}

export class Mappa3D implements ComponentFramework.StandardControl<IInputs, IOutputs> {
    private box!: HTMLDivElement;
    private labels!: HTMLDivElement;
    private top!: HTMLDivElement;
    private tabs!: HTMLDivElement;
    private search!: HTMLInputElement;
    private sugg!: HTMLDivElement;        // suggerimenti della ricerca (lista nostra: quella del browser era nera e a tutta altezza)
    private modeWrap!: HTMLDivElement;
    private modeSub!: HTMLDivElement;
    private legend!: HTMLDivElement;
    private viewCtl!: HTMLDivElement;
    private vistaBtn!: HTMLButtonElement;
    private oreBar!: HTMLDivElement;
    private playBtn!: HTMLButtonElement;
    private ora = -1;                    // -1 = tutto il giorno, altrimenti indice in dati.ore
    private haOre = false;
    private timer = 0;
    private maxTot = 1;                  // scala colori di "tutto il giorno"
    private maxOre = 1;                  // scala colori delle ore (uguale per tutte le ore)
    private maxP = 1;
    private badge!: HTMLDivElement;
    private tip!: HTMLDivElement;
    private notify!: () => void;

    private renderer!: THREE.WebGLRenderer;
    private scene!: THREE.Scene;
    private camera!: THREE.PerspectiveCamera;
    private world = new THREE.Group();
    private gruppi = new Map<string, THREE.Group>();
    private standMesh: THREE.Mesh[] = [];
    private ribbons: THREE.Mesh[] = [];      // tratti di corridoio a terra
    private curtains: THREE.Mesh[] = [];     // "tende" alte quanto il valore del tratto (solo 3D)
    private modo: "stand" | "corridoi" = "stand";
    private trattoSopra: Tratto | null = null;     // tratto sotto il mouse: evidenziato con i suoi stand
    private trattoBox: THREE.LineSegments | null = null;
    private modoBar!: HTMLDivElement;
    private maxCTot = 1; private maxCOre = 1; private maxC = 1;
    private selBox: THREE.LineSegments | null = null;
    private selPin!: HTMLDivElement;
    private selPos: THREE.Vector3 | null = null;
    private etichette: Etichetta[] = [];
    private raycaster = new THREE.Raycaster();

    private dati: Dati = { padiglioni: [], stand: [], blocchi: [], tratti: [], ore: [], fonte: "" };
    private ultimoCompatto: boolean | null = null;
    private demo = true;
    private lastJson: string | null = null;
    private lastPadInput: string | null = null;
    private pianta = false;
    private corrente = "tutti";          // "tutti" o codice padiglione
    private selezionato = "";            // codice stand o ""
    private W = 800; private H = 600;
    private target = new THREE.Vector3();
    private zona = { w: 600, d: 100 };
    private look = new THREE.Vector3();
    private anim = 0;
    private totalL = 600; private totalD = 100; private X0 = -300;
    private primo = true;                // alla prima costruzione la mappa si apre sul primo padiglione

    // ======================================================================
    public init(context: ComponentFramework.Context<IInputs>, notifyOutputChanged: () => void, _s: ComponentFramework.Dictionary, container: HTMLDivElement): void {
        this.notify = notifyOutputChanged;
        context.mode.trackContainerResize(true);
        this.box = crea("div", `position:relative;width:100%;height:100%;overflow:hidden;background:${SFONDO};font-family:'Segoe UI',system-ui,sans-serif;color:${INK}`);
        container.appendChild(this.box);

        this.renderer = new THREE.WebGLRenderer({ antialias: true });
        this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
        this.renderer.shadowMap.enabled = true;
        this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
        this.renderer.domElement.style.display = "block";
        this.box.appendChild(this.renderer.domElement);

        this.scene = new THREE.Scene();
        this.scene.background = new THREE.Color(SFONDO);
        this.scene.add(this.world);
        this.scene.add(new THREE.HemisphereLight("#ffffff", "#c9ccd3", 2.2));
        const sun = new THREE.DirectionalLight("#fff8ee", 2.2);
        sun.position.set(-220, 420, 260); sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
        Object.assign(sun.shadow.camera, { left: -420, right: 420, top: 260, bottom: -260, near: 10, far: 1400 });
        this.scene.add(sun);
        this.camera = new THREE.PerspectiveCamera(30, 1, 1, 8000);

        this.labels = crea("div", "position:absolute;inset:0;pointer-events:none;overflow:hidden");
        this.box.appendChild(this.labels);
        this.selPin = crea("div", `position:absolute;left:0;top:0;display:none;pointer-events:none;flex-direction:column;align-items:center;z-index:3`);
        this.selPin.innerHTML = `<span style="background:${INK};color:#fff;font-size:13px;font-weight:600;padding:5px 9px;border-radius:8px;white-space:nowrap"></span><svg width="14" height="9" viewBox="0 0 14 10" aria-hidden="true"><path d="M0 0h14L7 10z" fill="${INK}"></path></svg>`;
        this.box.appendChild(this.selPin);
        this.costruisciUI();

        this.renderer.domElement.addEventListener("pointermove", e => this.hover(e));
        this.renderer.domElement.addEventListener("pointerleave", () => {
            this.tip.style.display = "none";
            if (this.trattoSopra) { this.trattoSopra = null; this.applicaColori(); }
        });
        this.renderer.domElement.addEventListener("click", e => this.click(e));
    }

    public updateView(context: ComponentFramework.Context<IInputs>): void {
        const w = Math.max(120, Math.round(context.mode.allocatedWidth > 0 ? context.mode.allocatedWidth : this.box.clientWidth || 800));
        const h = Math.max(120, Math.round(context.mode.allocatedHeight > 0 ? context.mode.allocatedHeight : this.box.clientHeight || 600));
        const resized = w !== this.W || h !== this.H;
        this.W = w; this.H = h;
        this.renderer.setSize(w, h);
        this.camera.aspect = w / h;
        this.layout();

        const raw = (context.parameters.DatiJson.raw || "").trim();
        if (raw !== this.lastJson) {
            this.lastJson = raw;
            let righe: Riga[] = [];
            try { const v: unknown = raw ? JSON.parse(raw) : []; if (Array.isArray(v)) righe = v as Riga[]; }
            catch { righe = []; }
            let d = prepara(righe);
            this.demo = !d.stand.length;
            if (this.demo) d = prepara(demo());
            this.costruisci(d);
        }

        const pin = (context.parameters.Padiglione.raw || "").trim();
        if (pin !== this.lastPadInput) {
            this.lastPadInput = pin;
            if (pin === "") { if (resized) this.inquadra(); this.disegna(); return; }   // vuoto = resta dove si trova (apertura sul primo padiglione)
            const code = pin === "" || pin.toLowerCase() === "tutti" ? "tutti" : pin.toUpperCase();
            if (code === "tutti" || this.gruppi.has(code)) { this.selezionato = ""; this.vai(code, true); return; }
        }
        if (resized) this.inquadra();
        this.disegna();
    }

    public getOutputs(): IOutputs { return { StandSelezionato: this.selezionato, PadiglioneMostrato: this.corrente }; }

    public destroy(): void { cancelAnimationFrame(this.anim); this.ferma(); this.svuota(); this.renderer.dispose(); }

    // ======================================================================
    // INTERFACCIA
    private costruisciUI(): void {
        // barra in alto: schede padiglioni + ricerca
        this.top = crea("div", `position:absolute;top:10px;left:10px;right:10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;pointer-events:none`);
        this.tabs = crea("div", `${PANEL};display:flex;gap:2px;padding:3px;pointer-events:auto;overflow-x:auto;max-width:100%`);
        this.tabs.setAttribute("role", "tablist");
        const lab = crea("label", `${PANEL};display:flex;align-items:center;gap:6px;height:44px;box-sizing:border-box;padding:0 12px;margin-left:auto;pointer-events:auto`);
        lab.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${MUTED}" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"></circle><path d="m20 20-3.5-3.5"></path></svg>`;
        this.search = crea("input", `border:0;outline:none;background:transparent;font:13px 'Segoe UI',system-ui,sans-serif;color:${INK};width:190px`);
        this.search.type = "search"; this.search.placeholder = "Cerca stand";
        this.search.setAttribute("aria-label", "Cerca stand o espositore");
        this.search.setAttribute("autocomplete", "off");
        this.search.addEventListener("input", () => this.suggerisci());
        this.search.addEventListener("focus", () => this.suggerisci());
        this.search.addEventListener("blur", () => window.setTimeout(() => { this.sugg.style.display = "none"; }, 150));
        this.search.addEventListener("keydown", e => {
            if (e.key === "Enter") { this.sugg.style.display = "none"; this.cerca(this.search.value); }
            if (e.key === "Escape") this.sugg.style.display = "none";
        });
        lab.appendChild(this.search);
        this.top.appendChild(this.tabs); this.top.appendChild(lab);
        this.box.appendChild(this.top);
        this.sugg = crea("div", `${PANEL};position:absolute;display:none;z-index:7;padding:4px;box-shadow:0 8px 24px rgba(27,32,51,0.14);box-sizing:border-box;overflow:hidden`);
        this.box.appendChild(this.sugg);

        // cosa mostra la mappa (una sola grandezza) + barra delle ore
        this.modeWrap = crea("div", "position:absolute;display:flex;flex-direction:column;gap:4px;pointer-events:none");
        this.modeSub = crea("div", `font-size:12px;color:${INK2};padding-left:6px;text-shadow:0 0 4px ${SFONDO}`);
        this.modeWrap.appendChild(this.modeSub);
        this.box.appendChild(this.modeWrap);

        this.oreBar = crea("div", `${PANEL};display:none;gap:2px;padding:3px;pointer-events:auto;overflow-x:auto;scrollbar-width:none;box-sizing:border-box`);
        this.oreBar.setAttribute("role", "group"); this.oreBar.setAttribute("aria-label", "Fascia oraria");
        this.playBtn = crea("button", `${BTN};width:44px;padding:0;font-size:14px;flex:0 0 auto`, "▶") as HTMLButtonElement;
        this.playBtn.type = "button"; this.playBtn.setAttribute("aria-label", "Fai scorrere le ore");
        this.playBtn.onclick = () => { if (this.timer) this.ferma(); else this.avvia(); };

        this.badge = crea("div", "position:absolute;font-size:11px;font-weight:600;color:#92400E;background:#FEF3C7;border:1px solid #F1D491;border-radius:999px;padding:4px 10px;pointer-events:none", "Dati simulati");
        this.box.appendChild(this.badge);

        this.legend = crea("div", `${PANEL};position:absolute;left:10px;padding:8px 12px;display:flex;flex-direction:column;gap:4px;box-sizing:border-box;pointer-events:none`);
        this.box.appendChild(this.legend);
        this.modoBar = crea("div", `${PANEL};position:absolute;left:10px;display:flex;gap:2px;padding:3px;pointer-events:auto`);
        this.modoBar.setAttribute("role", "group"); this.modoBar.setAttribute("aria-label", "Cosa colorare");
        for (const [id, nome] of [["stand", "Stand"], ["corridoi", "Corridoi"]] as ["stand" | "corridoi", string][]) {
            const b = crea("button", `${BTN};min-height:34px;padding:0 12px`, nome); b.type = "button"; b.dataset.m = id;
            b.onclick = () => { this.modo = id; this.tip.style.display = "none"; this.applicaColori(); };
            this.modoBar.appendChild(b);
        }
        this.box.appendChild(this.modoBar);

        // controlli di vista
        this.viewCtl = crea("div", "position:absolute;right:10px;display:flex;gap:6px;align-items:center");
        const tipo = crea("div", `${PANEL};display:flex;gap:2px;padding:3px`);
        for (const [id, nome] of [["3d", "3D"], ["pianta", "Pianta"]]) {
            const b = crea("button", BTN, nome); b.type = "button"; b.dataset.v = id;
            b.onclick = () => { this.pianta = id === "pianta"; this.aggiornaComandi(); this.applicaColori(); this.vai(this.corrente, true); };
            tipo.appendChild(b);
        }
        const zoom = crea("div", `${PANEL};display:flex;overflow:hidden`);
        const piu = crea("button", `${BTN};width:44px;padding:0;font-size:20px;border-radius:0;border-right:1px solid ${LINE}`, "+");
        piu.type = "button"; piu.setAttribute("aria-label", "Avvicina"); piu.onclick = () => this.passo(+1);
        const meno = crea("button", `${BTN};width:44px;padding:0;font-size:20px;border-radius:0`, "−");
        meno.type = "button"; meno.setAttribute("aria-label", "Allontana"); meno.onclick = () => this.passo(-1);
        zoom.appendChild(piu); zoom.appendChild(meno);
        const reset = crea("button", `${PANEL};${BTN};width:44px;padding:0;color:${INK};display:flex;align-items:center;justify-content:center`);
        reset.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"></path><path d="M3 3v5h5"></path></svg>`;
        reset.type = "button"; reset.dataset.reset = "1"; reset.title = "Reimposta vista"; reset.setAttribute("aria-label", "Reimposta vista");
        reset.onclick = () => { this.selezionato = ""; this.search.value = ""; this.vai(this.dati.padiglioni[0]?.codice || "tutti", true); };
        // su schermi piccoli un solo pulsante che passa da 3D a Pianta e viceversa
        this.vistaBtn = crea("button", `${BTN};background:rgba(255,255,255,.96);border:1px solid ${LINE};border-radius:12px;color:${INK};font-weight:600;display:none`) as HTMLButtonElement;
        this.vistaBtn.type = "button";
        this.vistaBtn.onclick = () => { this.pianta = !this.pianta; this.aggiornaComandi(); this.applicaColori(); this.vai(this.corrente, true); };
        this.viewCtl.appendChild(tipo); this.viewCtl.appendChild(this.vistaBtn); this.viewCtl.appendChild(zoom); this.viewCtl.appendChild(reset);
        this.box.appendChild(this.viewCtl);

        this.tip = crea("div", `${PANEL};position:absolute;pointer-events:none;display:none;padding:8px 10px;font-size:12px;line-height:1.5;min-width:170px;max-width:320px;z-index:5;box-shadow:0 8px 24px rgba(27,32,51,0.14)`);
        this.box.appendChild(this.tip);
    }

    /** Schermo stretto (telefono in verticale). */
    private get stretto(): boolean { return this.W < 640; }
    /** Disposizione compatta: schermo stretto oppure basso. */
    private get compatto(): boolean { return this.W < 640 || this.H < 520; }

    /** Disposizione dei pannelli. In alto schede e ricerca. Schermo largo (Live): in basso una riga sola con legenda, ore e comandi di vista.
     *  Schermo compatto: ore sotto la barra in alto (telefono) o nella riga in alto (telefono in orizzontale). */
    private layout(): void {
        const s = this.compatto;
        const topH = this.top.offsetHeight || 50;
        const st = this.stretto;
        this.search.style.width = st ? "100%" : "120px";
        (this.search.parentElement as HTMLElement).style.flex = st ? "1 1 100%" : "0 0 auto";
        (this.search.parentElement as HTMLElement).style.marginLeft = st ? "0" : "auto";
        if (s !== this.ultimoCompatto) { this.ultimoCompatto = s; if (this.dati.padiglioni.length) { this.creaSchede(); this.creaOre(); this.aggiornaComandi(); } }
        this.top.style.flexWrap = st ? "wrap" : "nowrap";
        css(this.modeWrap, "position:absolute;display:none");
        (this.viewCtl.firstChild as HTMLElement).style.display = "none";   // 3D / Pianta: un solo pulsante che commuta
        this.vistaBtn.style.display = "block";
        this.viewCtl.style.bottom = "10px";
        const viewW = this.viewCtl.offsetWidth || 210;
        if (s && !st) {
            const lab = this.search.parentElement as HTMLElement;
            if (this.oreBar.parentElement !== this.top) this.top.insertBefore(this.oreBar, lab);
            css(this.oreBar, `${PANEL};display:${this.haOre ? "flex" : "none"};flex:1 1 0;min-width:0;gap:2px;padding:3px;pointer-events:auto;overflow-x:auto;scrollbar-width:none;box-sizing:border-box`);
        } else if (s) {
            if (this.oreBar.parentElement !== this.box) this.box.appendChild(this.oreBar);
            css(this.oreBar, `${PANEL};position:absolute;left:10px;right:10px;top:${topH + 16}px;display:${this.haOre ? "flex" : "none"};gap:2px;padding:3px;pointer-events:auto;overflow-x:auto;scrollbar-width:none;box-sizing:border-box`);
        }
        if (s) {
            (this.viewCtl.lastChild as HTMLElement).style.display = "none";
            const lw = Math.max(150, Math.min(230, this.W - Math.max(viewW, 170) - 44));
            this.legend.style.bottom = "10px"; this.legend.style.width = `${lw}px`; this.legend.style.left = "10px"; this.legend.style.right = "auto";
        } else {
            (this.viewCtl.lastChild as HTMLElement).style.display = "flex";
            const lw = 190;
            this.legend.style.bottom = "10px"; this.legend.style.width = `${lw}px`; this.legend.style.left = "10px"; this.legend.style.right = "auto";
            if (this.oreBar.parentElement !== this.box) this.box.appendChild(this.oreBar);
            css(this.oreBar, `${PANEL};position:absolute;left:${10 + lw + 10}px;right:${10 + viewW + 10}px;bottom:10px;display:${this.haOre ? "flex" : "none"};gap:2px;padding:3px;pointer-events:auto;overflow-x:auto;scrollbar-width:none;box-sizing:border-box`);
        }
        this.modoBar.style.bottom = `${10 + (this.legend.offsetHeight || 70) + 6}px`;
        this.modoBar.style.display = this.dati.tratti.length ? "flex" : "none";
        const oreH = st && this.haOre ? (this.oreBar.offsetHeight || 46) + 6 : 0;
        this.badge.style.top = s ? `${topH + 16 + oreH}px` : `${topH + 18}px`;
        this.badge.style.right = "12px";
        this.badge.style.display = this.demo ? "block" : "none";
    }

    /** Spazio occupato dai pannelli, in pixel, per tenere la mappa fuori da sotto i comandi. */
    private margini(): { top: number; bottom: number } {
        const oreH = this.stretto && this.haOre ? (this.oreBar.offsetHeight || 46) + 6 : 0;
        const topH = (this.top.offsetHeight || 50) + 10 + oreH;
        if (this.stretto) return { top: topH + 34, bottom: (this.legend.offsetHeight || 80) + (this.modoBar.offsetHeight || 40) + 26 };
        if (this.compatto) return { top: topH + 30, bottom: (this.legend.offsetHeight || 80) + (this.modoBar.offsetHeight || 40) + 26 };
        // la barra Stand/Corridoi sta nell'angolo sopra la legenda: non riduce la mappa (al massimo copre l'angolo del padiglione)
        return { top: topH + 14, bottom: Math.max(this.legend.offsetHeight || 80, this.oreBar.offsetHeight || 50) + 20 };
    }

    private creaSchede(): void {
        this.tabs.innerHTML = "";
        const voci = [{ codice: "tutti", corto: "Tutti", n: this.dati.stand.length }].concat(this.dati.padiglioni.map(p => ({
            codice: p.codice,
            corto: p.nome.replace(new RegExp("^" + p.codice + "\\s*[·:-]\\s*"), ""),
            n: this.dati.stand.filter(s => s.padiglione === p.codice).length,
        })));
        for (const v of voci) {
            const b = crea("button", `${BTN};display:flex;flex-direction:column;justify-content:center;align-items:flex-start;line-height:1.2;padding:4px 12px`);
            b.type = "button"; b.dataset.p = v.codice; b.setAttribute("role", "tab");
            const t = crea("span", "font-weight:600;font-size:13px", v.codice === "tutti" ? "Tutti" : v.codice);
            const n = crea("span", `font-size:11px;color:${MUTED}`, v.codice === "tutti" ? `${v.n} stand` : `${v.corto} · ${v.n}`);
            b.title = v.codice === "tutti" ? "Tutti i padiglioni" : `${v.codice} · ${v.corto} · ${v.n} stand`;
            b.appendChild(t); if (!this.compatto) b.appendChild(n);
            b.onclick = () => { this.selezionato = ""; this.vai(v.codice, true); };
            this.tabs.appendChild(b);
        }
    }

    /** Lista dei suggerimenti sotto la ricerca: al massimo 6 stand che contengono il testo nel codice o nell'espositore. */
    private suggerisci(): void {
        const q = this.search.value.trim().toLowerCase();
        this.sugg.innerHTML = "";
        if (!q) { this.sugg.style.display = "none"; return; }
        const trovati = this.dati.stand
            .filter(s => s.codice.toLowerCase().includes(q) || s.espositore.toLowerCase().includes(q))
            .sort((a, b) => a.codice.localeCompare(b.codice))
            .slice(0, 6);
        if (!trovati.length) {
            this.sugg.appendChild(crea("div", `padding:8px 10px;font-size:12px;color:${MUTED}`, "Nessuno stand trovato"));
        }
        for (const s of trovati) {
            const r = crea("button", `display:flex;flex-direction:column;align-items:flex-start;width:100%;min-height:44px;padding:5px 10px;border:0;border-radius:8px;background:transparent;cursor:pointer;text-align:left;font-family:'Segoe UI',system-ui,sans-serif`) as HTMLButtonElement;
            r.type = "button";
            r.appendChild(crea("span", `font-size:13px;font-weight:600;color:${INK}`, s.codice));
            r.appendChild(crea("span", `font-size:12px;color:${MUTED};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%`, s.espositore || "Nessun espositore"));
            r.onmouseenter = () => { r.style.background = "#EEF2FF"; };
            r.onmouseleave = () => { r.style.background = "transparent"; };
            r.onmousedown = e => e.preventDefault();   // non far perdere il fuoco alla ricerca prima del clic
            r.onclick = () => { this.search.value = s.codice; this.sugg.style.display = "none"; this.seleziona(s.codice); };
            this.sugg.appendChild(r);
        }
        const lab = this.search.parentElement as HTMLElement;
        const w = Math.max(240, lab.offsetWidth);
        const bx = this.box.getBoundingClientRect(), lr = lab.getBoundingClientRect();
        this.sugg.style.width = `${w}px`;
        this.sugg.style.top = `${lr.bottom - bx.top + 4}px`;
        this.sugg.style.left = `${Math.max(10, Math.min(lr.right - bx.left - w, this.W - w - 10))}px`;
        this.sugg.style.display = "block";
    }

    private aggiornaComandi(): void {
        this.tabs.querySelectorAll("button").forEach(el => {
            const b = el as HTMLButtonElement, on = b.dataset.p === this.corrente;
            b.style.background = on ? ACCENT : "transparent"; b.style.color = on ? "#ffffff" : INK2;
            b.setAttribute("aria-selected", String(on));
            const sub = b.children[1] as HTMLElement | undefined; if (sub) sub.style.color = on ? "#C7D2FE" : MUTED;
        });
        this.modeSub.textContent = this.dati.fonte === "SCANSIONI"
            ? "Persone allo stand · scansioni dei badge allo stand"
            : "Persone allo stand · sensori contapersone davanti agli stand";
        this.oreBar.querySelectorAll("button[data-o]").forEach(el => {
            const b = el as HTMLButtonElement, on = Number(b.dataset.o) === this.ora;
            b.style.background = on ? ACCENT : "transparent"; b.style.color = on ? "#ffffff" : INK2;
            b.style.fontWeight = on ? "600" : "500"; b.setAttribute("aria-pressed", String(on));
        });
        this.modoBar.querySelectorAll("button").forEach(el => {
            const b = el as HTMLButtonElement, on = b.dataset.m === this.modo;
            b.style.background = on ? ACCENT : "transparent"; b.style.color = on ? "#ffffff" : INK2;
            b.style.fontWeight = on ? "600" : "500"; b.setAttribute("aria-pressed", String(on));
        });
        this.playBtn.textContent = this.timer ? "❚❚" : "▶";
        this.playBtn.setAttribute("aria-label", this.timer ? "Ferma lo scorrimento delle ore" : "Fai scorrere le ore");
        this.vistaBtn.textContent = this.pianta ? "3D" : "Pianta";
        this.vistaBtn.setAttribute("aria-label", this.pianta ? "Passa alla vista 3D" : "Passa alla vista in pianta");
        this.viewCtl.querySelectorAll("button[data-v]").forEach(el => {
            const b = el as HTMLButtonElement, on = (b.dataset.v === "pianta") === this.pianta;
            b.style.background = on ? ACCENT : "transparent"; b.style.color = on ? "#ffffff" : INK2; b.setAttribute("aria-pressed", String(on));
        });
        this.renderLegenda();
    }

    // ---------- valori e ore ----------
    private pS(s: Stand): number { return this.ora >= 0 ? s.persone_ore[this.ora] || 0 : s.persone; }
    private pT(c: Tratto): number { return this.ora >= 0 ? c.persone_ore[this.ora] || 0 : c.persone; }

    /** "15:00" -> "15–16". */
    private fascia(i: number): string {
        const o = this.dati.ore[i] || "";
        const m = /^(\d{1,2})[:.]00$/.exec(o);
        return m ? `${Number(m[1])}–${Number(m[1]) + 1}` : o;
    }

    /** 95-esimo percentile dei valori maggiori di zero: uno stand eccezionale non schiaccia tutti gli altri sul colore chiaro. */
    private p95(a: number[]): number {
        const v = a.filter(x => x > 0).sort((x, y) => x - y);
        return v.length ? Math.max(1, v[Math.min(v.length - 1, Math.floor(v.length * 0.95))]) : 1;
    }

    private usaScala(): void { this.maxP = this.ora >= 0 ? this.maxOre : this.maxTot; this.maxC = this.ora >= 0 ? this.maxCOre : this.maxCTot; }

    private creaOre(): void {
        this.oreBar.innerHTML = "";
        if (!this.haOre) { this.oreBar.style.display = "none"; return; }
        this.oreBar.appendChild(this.playBtn);
        const altezza = this.compatto ? "min-height:38px;" : "";
        const giorno = crea("button", `${BTN};${altezza}flex:0 0 auto`, "Giorno") as HTMLButtonElement;
        giorno.title = "Tutto il giorno (stessa scala per tutte le ore)";
        giorno.type = "button"; giorno.dataset.o = "-1";
        giorno.onclick = () => { this.ferma(); this.impostaOra(-1); };
        this.oreBar.appendChild(giorno);
        this.dati.ore.forEach((o, i) => {
            const b = crea("button", `${BTN};${altezza}padding:0 9px;flex:0 0 auto;font-variant-numeric:tabular-nums`, this.fascia(i)) as HTMLButtonElement;
            b.type = "button"; b.dataset.o = String(i); b.title = `Dalle ${o}`;
            b.onclick = () => { this.ferma(); this.impostaOra(i); };
            this.oreBar.appendChild(b);
        });
        this.playBtn.style.minHeight = this.compatto ? "38px" : "44px";
        this.layout();
    }

    private impostaOra(i: number): void {
        this.ora = i;
        this.usaScala();
        this.tip.style.display = "none";
        this.applicaColori();
        const b = this.oreBar.querySelector(`button[data-o="${i}"]`) as HTMLElement | null;
        if (b) {   // tiene visibile la fascia scelta quando la barra scorre
            const l = b.offsetLeft, r = l + b.offsetWidth, bar = this.oreBar;
            if (l < bar.scrollLeft) bar.scrollLeft = l - 50; else if (r > bar.scrollLeft + bar.clientWidth) bar.scrollLeft = r - bar.clientWidth + 6;
        }
    }

    private avvia(): void {
        const n = this.dati.ore.length; if (!n) return;
        if (this.ora < 0 || this.ora >= n - 1) this.impostaOra(0);
        this.timer = window.setInterval(() => {
            if (this.ora >= this.dati.ore.length - 1) { this.ferma(); this.aggiornaComandi(); return; }
            this.impostaOra(this.ora + 1);
        }, 1400);
        this.aggiornaComandi();
    }

    private ferma(): void {
        if (this.timer) { window.clearInterval(this.timer); this.timer = 0; if (this.oreBar) this.aggiornaComandi(); }
    }

    private renderLegenda(): void {
        const grad = `<div style="display:flex;height:10px;border-radius:3px;overflow:hidden">${SEQ.map(x => `<span style="flex:1;background:${x}"></span>`).join("")}</div>`;
        const ticks = (a: string[]) => `<div style="display:flex;justify-content:space-between;font-size:11px;color:${INK2};font-variant-numeric:tabular-nums">${a.map(x => `<span>${x}</span>`).join("")}</div>`;
        const corr = this.modo === "corridoi";
        const quando = this.ora >= 0 ? this.fascia(this.ora) : "giorno";
        const titolo = corr ? `Corridoi · ${quando}` : `Persone allo stand · ${quando}`;
        const nota = `<span style="font-size:11px;color:${MUTED}">${this.dati.fonte === "SCANSIONI" ? "Fonte: scansioni allo stand" : "Fonte: sensori agli stand"}</span>`;
        const max = corr ? this.maxC : this.maxP;
        const nota2 = corr ? `<span style="font-size:11px;color:${MUTED}">Stima dagli stand affacciati · grigio = nessuno</span>` : nota;
        this.legend.innerHTML = `<strong style="font-size:12px">${titolo}</strong>` + grad + ticks(["0", fmt(Math.round(max / 2)), fmt(max) + "+"]) + nota2;
    }

    private avviso(testo: string): void {
        const a = crea("div", "position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);background:#FEF2F2;border:1px solid #FCA5A5;color:#991B1B;border-radius:8px;padding:8px 12px;font-size:12px;z-index:6", testo);
        this.box.appendChild(a); setTimeout(() => a.remove(), 6000);
    }

    // ======================================================================
    // SCENA
    /** Libera geometrie e materiali: la Live ricostruisce la scena ogni 60 secondi, senza questo la memoria cresce. */
    private svuota(): void {
        this.world.traverse(o => {
            const m = o as THREE.Mesh;
            if (m.geometry) m.geometry.dispose();
            const mat = m.material as THREE.Material | THREE.Material[] | undefined;
            if (Array.isArray(mat)) mat.forEach(x => x.dispose()); else if (mat) mat.dispose();
        });
        this.world.clear();
    }

    private costruisci(d: Dati): void {
        this.dati = d;
        this.svuota(); this.gruppi.clear();
        this.standMesh = []; this.ribbons = []; this.curtains = []; this.selBox = null; this.trattoBox = null; this.trattoSopra = null;
        this.labels.innerHTML = ""; this.etichette = [];
        const pad = new Map(d.padiglioni.map(p => [p.codice, p]));
        this.totalL = Math.max(1, ...d.padiglioni.map(p => p.x + p.lunghezza));
        this.totalD = Math.max(1, ...d.padiglioni.map(p => p.z + p.larghezza + 18));
        this.X0 = -this.totalL / 2;
        const X0 = this.X0;
        for (const p of d.padiglioni) { const g = new THREE.Group(); this.gruppi.set(p.codice, g); this.world.add(g); }
        const G = (c: string) => this.gruppi.get(c) as THREE.Group;

        const n = d.ore.length;
        this.haOre = n > 0;
        this.ferma();
        if (!this.haOre || this.ora >= n) this.ora = -1;
        this.maxTot = this.p95(d.stand.map(s => s.persone));
        this.maxOre = this.p95(([] as number[]).concat(...d.stand.map(s => s.persone_ore)));
        this.maxCTot = this.p95(d.tratti.map(c => c.persone));
        this.maxCOre = this.p95(([] as number[]).concat(...d.tratti.map(c => c.persone_ore)));
        if (!d.tratti.length) this.modo = "stand";
        this.usaScala();

        const ground = new THREE.Mesh(new THREE.PlaneGeometry(5000, 5000), new THREE.MeshStandardMaterial({ color: "#E4E7EE" }));
        ground.rotation.x = -Math.PI / 2; ground.position.y = -0.05; ground.receiveShadow = true;
        this.world.add(ground);
        // orientamento come in Planimetria: fila a parete in fondo, ingresso verso chi guarda; davanti a ogni padiglione la sua corsia
        const corsiaMat = new THREE.MeshStandardMaterial({ color: "#DDE1EA" });

        const wallMat = new THREE.MeshStandardMaterial({ color: "#C9CDD8", transparent: true, opacity: 0.55 });
        const bloccoMat = new THREE.MeshStandardMaterial({ color: "#E6E9F1" });
        for (const p of d.padiglioni) {
            const cx = X0 + p.x + p.lunghezza / 2;
            const floor = new THREE.Mesh(new THREE.BoxGeometry(p.lunghezza, 0.6, p.larghezza), new THREE.MeshStandardMaterial({ color: "#F8FAFC" }));
            floor.position.set(cx, 0.3, p.z + p.larghezza / 2); floor.receiveShadow = true; G(p.codice).add(floor);
            const corsia = new THREE.Mesh(new THREE.BoxGeometry(p.lunghezza + 20, 0.3, 16), corsiaMat);
            corsia.position.set(cx, 0.15, p.z + p.larghezza + 9); corsia.receiveShadow = true; G(p.codice).add(corsia);
            const ix = p.ingresso.x, iw = p.ingresso.w;
            const muri: [number, number, number, number, number][] = [
                [p.lunghezza, 9, 1, cx, 0],                                                   // muro di fondo (la fila a parete ci appoggia la schiena)
                [1, 9, p.larghezza, X0 + p.x, p.larghezza / 2],                               // lato sinistro
                [1, 9, p.larghezza, X0 + p.x + p.lunghezza, p.larghezza / 2],                 // lato destro
                [ix, 1.5, 1, X0 + p.x + ix / 2, p.larghezza],                                 // bordo verso il viale, interrotto dall'ingresso
                [p.lunghezza - ix - iw, 1.5, 1, X0 + p.x + ix + iw + (p.lunghezza - ix - iw) / 2, p.larghezza],
            ];
            for (const [w, h, dd, x, z] of muri) {
                if (w <= 0) continue;
                const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, dd), wallMat);
                m.position.set(x, h / 2, p.z + z); m.castShadow = h > 2; G(p.codice).add(m);
            }
            this.etichetta(p.nome, new THREE.Vector3(cx, 10, p.z - 2), p.codice, "fisso",
                `font-size:13px;font-weight:700;color:${INK};background:rgba(255,255,255,.85);padding:3px 8px;border-radius:6px`);
            this.etichette[this.etichette.length - 1].el.dataset.nome = "1";
            // ingresso
            const ex = X0 + p.x + ix + iw / 2;
            const cone = new THREE.Mesh(new THREE.ConeGeometry(2, 4.5, 16), new THREE.MeshStandardMaterial({ color: ACCENT }));
            cone.rotation.x = -Math.PI / 2; cone.position.set(ex, 2.5, p.z + p.larghezza + 2.5); G(p.codice).add(cone);
            this.etichetta("▲ Ingresso " + p.codice, new THREE.Vector3(ex, 0.5, p.z + p.larghezza + 10), p.codice, "fisso",
                `font-size:11px;font-weight:600;color:#3730A3;background:#ffffff;border:1px solid #C7D2FE;padding:2px 7px;border-radius:6px`);
            this.etichette[this.etichette.length - 1].el.dataset.ingresso = "1";
        }
        // fondo degli isolati, come nella Planimetria
        for (const b of d.blocchi) {
            const p = pad.get(b.padiglione); if (!p) continue;
            const m = new THREE.Mesh(new THREE.BoxGeometry(b.w, 0.12, b.h), bloccoMat);
            m.position.set(X0 + p.x + b.x + b.w / 2, 0.66, p.z + b.y + b.h / 2); m.receiveShadow = true;
            G(p.codice).add(m);
        }

        // tratti di corridoio: striscia a terra + "tenda" lungo il tratto (B-69)
        for (const c of d.tratti) {
            const p = pad.get(c.padiglione); if (!p) continue;
            const cx = X0 + p.x + c.x + c.w / 2, cz = p.z + c.y + c.h / 2;
            // striscia larga almeno 4,5 m anche dove il corridoio e' stretto, cosi' si legge in pianta
            const rw = c.oriz ? Math.max(0.5, c.w - 1) : Math.max(4.5, c.w), rh = c.oriz ? Math.max(4.5, c.h) : Math.max(0.5, c.h - 1);
            const rib = new THREE.Mesh(new THREE.BoxGeometry(rw, 0.3, rh), new THREE.MeshStandardMaterial({ color: SEQ[0] }));
            rib.position.set(cx, 0.95, cz); rib.userData = { tipo: "corridoio", c, p };
            G(p.codice).add(rib); this.ribbons.push(rib);
            // niente "tende" verticali (24/11): in prospettiva si sovrapponevano e il P3 sembrava rotto
        }

        const geo = new THREE.BoxGeometry(1, 1, 1);
        for (const s of d.stand) {
            const p = pad.get(s.padiglione); if (!p) continue;
            const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: SEQ[0], roughness: 0.65, transparent: true }));
            m.castShadow = true; m.receiveShadow = true;
            m.position.set(X0 + p.x + s.x + s.w / 2, 0, p.z + s.y + s.h / 2);
            m.scale.set(Math.max(0.5, s.w - 0.6), 3, Math.max(0.5, s.h - 0.6));
            m.userData = { tipo: "stand", s, p };
            G(p.codice).add(m); this.standMesh.push(m);
            this.etichetta(s.codice.replace(/^P\d+-/, ""), m.position.clone(), p.codice, "stand",
                `font-size:10px;font-weight:600;color:${INK};background:rgba(255,255,255,.8);padding:1px 4px;border-radius:4px`, s.w);
        }

        this.creaSchede();
        this.creaOre();
        if (this.primo && d.padiglioni.length) { this.corrente = d.padiglioni[0].codice; this.primo = false; }
        if (this.corrente !== "tutti" && !this.gruppi.has(this.corrente)) this.corrente = "tutti";
        if (this.selezionato && !d.stand.some(s => s.codice === this.selezionato)) this.selezionato = "";
        this.layout();
        this.applicaColori(false);
        this.vai(this.corrente, false);
    }

    private etichetta(testo: string, pos: THREE.Vector3, pad: string, tipo: "stand" | "fisso", stile: string, w?: number): void {
        const el = crea("div", `position:absolute;left:0;top:0;white-space:nowrap;transform:translate(-50%,-50%);${stile}`, testo);
        el.setAttribute("aria-hidden", "true");
        this.labels.appendChild(el);
        this.etichette.push({ el, pos, pad, tipo, w });
    }

    /** Colore e altezza degli stand in base alle persone, selezione e attenuazione. */
    private applicaColori(ridisegna = true): void {
        const sel = this.selezionato;
        const corr = this.modo === "corridoi";
        for (const m of this.standMesh) {
            const s = m.userData.s as Stand, v = Math.min(1, this.pS(s) / this.maxP);
            let hgt = corr ? 1.2 : this.pianta ? 0.8 : 2 + 14 * v;
            if (s.codice === sel && !this.pianta) hgt += 3;
            const mat = m.material as THREE.MeshStandardMaterial;
            const delTratto = corr && this.trattoSopra !== null && this.trattoSopra.stand.includes(s.codice);
            mat.color.copy(corr ? new THREE.Color(delTratto ? "#A5B4FC" : "#FFFFFF") : scala(SEQ, v));
            mat.opacity = sel && s.codice !== sel ? 0.5 : 1;
            mat.depthWrite = !(sel && s.codice !== sel);
            mat.emissive = s.codice === sel ? new THREE.Color(ACCENT).multiplyScalar(0.12) : new THREE.Color("#000");
            m.scale.y = hgt; m.position.y = 0.6 + hgt / 2;
        }
        for (const r of this.ribbons) {
            const t = Math.min(1, this.pT(r.userData.c as Tratto) / this.maxC);
            r.visible = corr;
            const val = this.pT(r.userData.c as Tratto);
            (r.material as THREE.MeshStandardMaterial).color.copy(val > 0 ? scala(SEQ, 0.15 + 0.85 * t) : new THREE.Color("#DCE0E8"));   // grigio = nessuno stand affacciato
        }
        for (const c of this.curtains) {
            const t = Math.min(1, this.pT(c.userData.c as Tratto) / this.maxC), hgt = 1 + 18 * t;
            c.visible = corr && !this.pianta;
            c.scale.y = hgt; c.position.y = hgt / 2 + 0.8;
            const mat = c.material as THREE.MeshBasicMaterial;
            mat.color.copy(scala(SEQ, 0.2 + 0.8 * t)); mat.opacity = 0.15 + 0.5 * t;
        }
        // contorno del tratto sotto il mouse
        if (this.trattoBox) {
            this.trattoBox.parent?.remove(this.trattoBox);
            this.trattoBox.geometry.dispose(); (this.trattoBox.material as THREE.Material).dispose();
            this.trattoBox = null;
        }
        const rib = corr && this.trattoSopra ? this.ribbons.find(r => r.userData.c === this.trattoSopra) : undefined;
        if (rib) {
            const g = (rib.geometry as THREE.BoxGeometry).parameters;
            const box = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(g.width + 0.6, 1.2, g.depth + 0.6)), new THREE.LineBasicMaterial({ color: INK }));
            box.position.copy(rib.position); rib.parent?.add(box); this.trattoBox = box;
        }
        this.aggiornaSelezione();
        this.aggiornaComandi();
        if (ridisegna) this.disegna();
    }

    private aggiornaSelezione(): void {
        if (this.selBox) {
            this.selBox.parent?.remove(this.selBox);
            this.selBox.geometry.dispose(); (this.selBox.material as THREE.Material).dispose();
            this.selBox = null;
        }
        this.selPos = null;
        const m = this.standMesh.find(x => (x.userData.s as Stand).codice === this.selezionato);
        if (!m) return;
        const st = m.userData.s as Stand;
        (this.selPin.firstChild as HTMLElement).textContent = `${st.codice} · ${fmt(this.pS(st))} persone`;
        this.selPos = new THREE.Vector3(m.position.x, m.position.y + m.scale.y / 2 + 1, m.position.z);
        const box = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1, 1, 1)), new THREE.LineBasicMaterial({ color: INK }));
        box.position.copy(m.position); box.scale.copy(m.scale).multiplyScalar(1.06);
        m.parent?.add(box); this.selBox = box;
    }

    // ======================================================================
    // NAVIGAZIONE
    private direzione(): THREE.Vector3 {
        if (this.pianta) return (this.camera.aspect < 0.95 ? new THREE.Vector3(0.001, 1, 0) : new THREE.Vector3(0, 1, 0.001)).normalize();
        return this.camera.aspect < 0.95 ? new THREE.Vector3(0.5, 0.866, 0).normalize() : new THREE.Vector3(0, 0.866, 0.5).normalize();
    }

    /** Distanza minima che tiene la zona dentro lo spazio libero tra i pannelli. */
    private posizioneCamera(): THREE.Vector3 {
        const dir = this.direzione();
        const hw = this.zona.w / 2, hd = this.zona.d / 2;
        const corners: THREE.Vector3[] = [];
        for (const dx of [-hw, hw]) for (const dz of [-hd, hd]) for (const y of [0, 12])
            corners.push(new THREE.Vector3(this.target.x + dx, y, this.target.z + dz));
        const mg = this.margini();
        const topLim = 1 - (2 * mg.top) / this.H, botLim = -1 + (2 * mg.bottom) / this.H;
        const xLim = 1 - (2 * 12) / this.W;
        const cam = this.camera.clone(); cam.aspect = this.camera.aspect; cam.updateProjectionMatrix();
        const sta = (d: number) => {
            cam.position.copy(this.target).addScaledVector(dir, d); cam.lookAt(this.target); cam.updateMatrixWorld();
            return corners.every(c => { const v = c.clone().project(cam); return Math.abs(v.x) <= xLim && v.y <= topLim && v.y >= botLim; });
        };
        let lo = 15, hi = 9000;
        for (let i = 0; i < 34; i++) { const mid = (lo + hi) / 2; if (sta(mid)) hi = mid; else lo = mid; }
        return this.target.clone().addScaledVector(dir, hi);
    }

    private impostaZona(): void {
        const s = this.dati.stand.find(x => x.codice === this.selezionato);
        const p = this.dati.padiglioni.find(x => x.codice === this.corrente);
        if (s && p) {
            this.zona = { w: Math.max(95, s.w * 7), d: Math.max(70, s.h * 7) };
            this.target.set(this.X0 + p.x + s.x + s.w / 2, 0, p.z + s.y + s.h / 2);
        } else if (p) {
            this.zona = { w: p.lunghezza + 16, d: p.larghezza + 30 };
            this.target.set(this.X0 + p.x + p.lunghezza / 2, 0, p.z + p.larghezza / 2 + 8);
        } else {
            this.zona = { w: this.totalL + 4, d: this.totalD + 6 };
            this.target.set(0, 0, this.totalD / 2);
        }
    }

    private inquadra(): void {
        cancelAnimationFrame(this.anim);
        this.impostaZona();
        this.camera.position.copy(this.posizioneCamera());
        this.look.copy(this.target);
        this.camera.updateProjectionMatrix();
        this.camera.lookAt(this.look);
    }

    /** Va a "tutti", a un padiglione, o (se c'e' uno stand selezionato in quel padiglione) allo stand. */
    private vai(code: string, animato: boolean): void {
        this.corrente = code;
        for (const [c, g] of this.gruppi) g.visible = code === "tutti" || c === code;
        this.applicaColori(false);
        this.tip.style.display = "none";
        this.impostaZona();
        const reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        this.notify();
        if (!animato || reduce) { this.inquadra(); this.disegna(); return; }
        cancelAnimationFrame(this.anim);
        const fromP = this.camera.position.clone(), fromL = this.look.clone();
        const toP = this.posizioneCamera(), toL = this.target.clone();
        const t0 = performance.now(), dur = 650;
        const step = (now: number) => {
            const k = Math.min(1, (now - t0) / dur), e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
            this.camera.position.lerpVectors(fromP, toP, e);
            this.look.lerpVectors(fromL, toL, e);
            this.camera.lookAt(this.look);
            this.disegna();
            if (k < 1) this.anim = requestAnimationFrame(step);
        };
        this.anim = requestAnimationFrame(step);
    }

    /** + e -: tre livelli fissi (tutti -> padiglione -> stand piu' affollato). */
    private passo(verso: number): void {
        if (verso > 0) {
            if (this.corrente === "tutti") { const p = this.dati.padiglioni[0]; if (p) { this.selezionato = ""; this.vai(p.codice, true); } }
            else if (!this.selezionato) {
                const s = this.dati.stand.filter(x => x.padiglione === this.corrente).sort((a, b) => this.pS(b) - this.pS(a))[0];
                if (s) this.seleziona(s.codice);
            }
        } else {
            if (this.selezionato) { this.selezionato = ""; this.vai(this.corrente, true); }
            else if (this.corrente !== "tutti") this.vai("tutti", true);
        }
    }

    private seleziona(codice: string): void {
        const s = this.dati.stand.find(x => x.codice === codice); if (!s) return;
        this.selezionato = codice;
        this.vai(s.padiglione, true);
    }

    private cerca(q: string): void {
        const t = q.trim().toLowerCase(); if (!t) return;
        const s = this.dati.stand.find(x => x.codice.toLowerCase() === t)
            || this.dati.stand.find(x => x.espositore.toLowerCase() === t)
            || this.dati.stand.find(x => x.codice.toLowerCase().includes(t) || x.espositore.toLowerCase().includes(t));
        if (s) this.seleziona(s.codice); else this.avviso(`Nessuno stand trovato per "${q}"`);
    }

    // ======================================================================
    // DISEGNO + ETICHETTE
    private disegna(): void {
        this.renderer.render(this.scene, this.camera);
        this.posizionaEtichette();
    }

    private posizionaEtichette(): void {
        const v = new THREE.Vector3(), v2 = new THREE.Vector3();
        if (this.selPos) {
            v.copy(this.selPos).project(this.camera);
            this.selPin.style.display = "flex";
            this.selPin.style.transform = `translate(${(v.x + 1) / 2 * this.W}px, ${(1 - v.y) / 2 * this.H}px) translate(-50%,-100%)`;
        } else this.selPin.style.display = "none";
        const livelloStand = this.corrente !== "tutti";
        for (const e of this.etichette) {
            const g = e.pad ? this.gruppi.get(e.pad) : null;
            let show = !g || g.visible;
            if (e.tipo === "fisso" && e.pad && e.el.dataset.nome === "1") show = show && this.corrente === "tutti";
            if (e.tipo === "fisso" && e.pad && e.el.dataset.ingresso === "1") show = show && this.corrente !== "tutti";
            if (e.tipo === "stand") {
                show = show && livelloStand;
                if (show && e.w) {   // solo se lo stand e' abbastanza largo sullo schermo
                    v.copy(e.pos).setX(e.pos.x - e.w / 2).project(this.camera);
                    v2.copy(e.pos).setX(e.pos.x + e.w / 2).project(this.camera);
                    // etichetta piu' piccola sugli stand stretti (P3), nascosta solo se lo stand e' sotto i 14 px
                    const pw = Math.abs(v2.x - v.x) * this.W / 2;
                    show = pw > 14;
                    const taglia = pw < 22 ? "xs" : pw < 30 ? "s" : "m";
                    if (e.el.dataset.taglia !== taglia) {
                        e.el.dataset.taglia = taglia;
                        e.el.style.fontSize = taglia === "xs" ? "7.5px" : taglia === "s" ? "8.5px" : "10px";
                        e.el.style.padding = taglia === "m" ? "1px 4px" : "0 1px";
                    }
                }
            }
            if (!show) { e.el.style.display = "none"; continue; }
            const p = e.tipo === "stand" ? v.copy(e.pos).setY(e.pos.y * 2 + 1) : v.copy(e.pos);
            p.project(this.camera);
            if (p.z > 1) { e.el.style.display = "none"; continue; }
            e.el.style.display = "block";
            e.el.style.transform = `translate(${(p.x + 1) / 2 * this.W}px, ${(1 - p.y) / 2 * this.H}px) translate(-50%,-50%)`;
            e.el.style.opacity = this.selezionato && e.tipo === "stand" ? "0.45" : "1";
        }
    }

    // ======================================================================
    // INTERAZIONE
    private pick(e: MouseEvent): THREE.Intersection | undefined {
        const r = this.renderer.domElement.getBoundingClientRect();
        const v = new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
        this.raycaster.setFromCamera(v, this.camera);
        const corr = this.modo === "corridoi";
        const targets = (this.standMesh as THREE.Object3D[]).concat(corr ? this.ribbons : [])
            .filter(o => !o.parent || o.parent.visible);
        return this.raycaster.intersectObjects(targets, false)[0];
    }

    private hover(e: MouseEvent): void {
        const hit = this.pick(e);
        const nuovo = hit && hit.object.userData.tipo === "corridoio" ? hit.object.userData.c as Tratto : null;
        if (nuovo !== this.trattoSopra) { this.trattoSopra = nuovo; this.applicaColori(); }
        if (!hit) { this.tip.style.display = "none"; return; }
        const quando = this.ora >= 0 ? ` <span style="color:${MUTED}">(${this.fascia(this.ora)})</span>` : ` <span style="color:${MUTED}">(tutto il giorno)</span>`;
        if (hit.object.userData.tipo === "corridoio") {
            const c = hit.object.userData.c as Tratto;
            this.tip.innerHTML = `<b>Corridoio · ${(hit.object.userData.p as Padiglione).codice}</b><br>persone agli stand affacciati <b>${fmt(this.pT(c))}</b>${quando}<br><span style="color:${MUTED}">${c.stand.length} stand (in azzurro sulla mappa): ${c.stand.map(x => x.replace(/^P\d+-/, "")).join(", ") || "nessuno"}</span><br><span style="color:${MUTED}">Stima, non un conteggio nel corridoio</span>`;
        } else {
        const s = hit.object.userData.s as Stand;
        const pos = POSIZIONI[s.posizione] || s.posizione.toLowerCase();
        this.tip.innerHTML = `<b>Stand ${s.codice}</b>${s.espositore ? " · " + s.espositore.replace(/</g, "&lt;") : ""}<br><span style="color:${MUTED}">${pos} · ${s.mq} m²</span><br>persone allo stand <b>${fmt(this.pS(s))}</b>${quando}`;
        }
        const r = this.box.getBoundingClientRect();
        this.tip.style.display = "block";
        if (nuovo) {   // corridoio: scheda sopra o sotto il tratto (mai sopra il tratto), cosi' si vede quale e' evidenziato
            const rib = hit.object.userData.tipo === "corridoio" ? this.ribbons.find(m => m.userData.c === nuovo) : undefined;
            if (rib) {
                const g = (rib.geometry as THREE.BoxGeometry).parameters;
                const ys: number[] = [], xs: number[] = [];
                for (const dx of [-g.width / 2, g.width / 2]) for (const dz of [-g.depth / 2, g.depth / 2]) {
                    const v = new THREE.Vector3(rib.position.x + dx, rib.position.y, rib.position.z + dz).applyMatrix4(rib.parent ? rib.parent.matrixWorld : new THREE.Matrix4()).project(this.camera);
                    xs.push((v.x + 1) / 2 * this.W); ys.push((1 - v.y) / 2 * this.H);
                }
                const alto = Math.min(...ys), basso = Math.max(...ys), cx = (Math.min(...xs) + Math.max(...xs)) / 2;
                const tw = this.tip.offsetWidth, th = this.tip.offsetHeight;
                const sotto = basso + 12 + th <= this.H - 10 && (alto + basso) / 2 < this.H / 2;
                this.tip.style.left = `${Math.max(6, Math.min(cx - tw / 2, this.W - tw - 6))}px`;
                this.tip.style.top = `${sotto ? basso + 12 : Math.max(6, alto - th - 12)}px`;
                return;
            }
        }
        this.tip.style.left = Math.max(6, Math.min(e.clientX - r.left + 12, r.width - this.tip.offsetWidth - 6)) + "px";
        this.tip.style.top = Math.max(6, Math.min(e.clientY - r.top + 12, r.height - this.tip.offsetHeight - 6)) + "px";
    }

    private click(e: MouseEvent): void {
        const hit = this.pick(e);
        if (hit && hit.object.userData.tipo === "corridoio") { this.hover(e); return; }
        if (hit) {
            const s = hit.object.userData.s as Stand;
            if (s.codice === this.selezionato) { this.selezionato = ""; this.vai(this.corrente, true); }   // secondo tocco = deseleziona
            else this.seleziona(s.codice);
            this.hover(e);
        } else if (this.selezionato) {
            this.selezionato = ""; this.vai(this.corrente, true);                                          // tocco nel vuoto = torna al padiglione
        }
    }
}

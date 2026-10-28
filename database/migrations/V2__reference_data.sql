-- =====================================================================
-- ARCADE Milano - V2: dati di riferimento (lookup)
-- Ricavati dal profiling dei file del cliente (ARCADE_Milano_dati).
-- NON contiene dati transazionali: quelli arrivano dall'ETL.
-- Le assunzioni sono marcate "ASSUNZIONE" e tracciate in docs/data-model.md.
-- =====================================================================

-- Sorgenti ---------------------------------------------------------------
INSERT INTO core.data_source (code, description, kind, source_timezone, is_demo) VALUES
 ('XLSX_COMMERCIALE','ARCADE_Commerciale.xlsx (espositori, planimetria, listino 2026, contratti)','COMMERCIAL_XLSX','Europe/Rome',false),
 ('BIGL_2024','biglietteria_2024.csv (sep ;)','TICKETING','Europe/Rome',false),
 ('BIGL_2025','biglietteria_2025.csv (sep ;)','TICKETING','Europe/Rome',false),
 ('TORN_2024','tornelli_2024.csv - data/ora locali, senza offset','TURNSTILE','Europe/Rome',false),
 ('TORN_2025','tornelli_2025.csv - timestamp_utc con suffisso Z','TURNSTILE','UTC',false),
 ('LEAD_2025','contatti_stand_2025.csv (sep ,)','STAND_LEAD','Europe/Rome',false),     -- ASSUNZIONE: ora locale
 ('VISITE_2025','visite_stand_2025.csv - aggregato orario','STAND_SCAN','Europe/Rome',false), -- ASSUNZIONE: ora locale
 ('SCAN_APP','App di scansione stand (eventi puntuali)','APP','UTC',false),
 ('MANUAL','Inserimenti manuali da back-office','MANUAL','Europe/Rome',false);

-- Edizioni e giorni ------------------------------------------------------
INSERT INTO core.edition (year, name, status) VALUES
 (2024,'ARCADE Milano 2024','CLOSED'),
 (2025,'ARCADE Milano 2025','CLOSED'),
 (2026,'ARCADE Milano 2026','SALES_OPEN');
-- Date dedotte da biglietti/tornelli (20-22/12/2024, 19-21/12/2025), orari dai tornelli (09:00-17:30).
-- Il brief indica "fine novembre": discrepanza da chiarire (domanda Q-01). 2026: date non note.
INSERT INTO core.edition_day (edition_id, day_date, day_number, opens_at, closes_at)
SELECT e.edition_id, d.day_date, d.n, '09:00', '17:30'
FROM core.edition e
JOIN (VALUES (2024, DATE '2024-12-20', 1), (2024, DATE '2024-12-21', 2), (2024, DATE '2024-12-22', 3),
             (2025, DATE '2025-12-19', 1), (2025, DATE '2025-12-20', 2), (2025, DATE '2025-12-21', 3))
     AS d(y, day_date, n) ON d.y = e.year;

-- Padiglioni e varchi ----------------------------------------------------
INSERT INTO core.pavilion (code, name) VALUES
 ('P1','Console & PC'), ('P2','Esports & Community'), ('P3','Indie, Retro & Cosplay');

-- ASSUNZIONE: ogni varco e' un accesso al padiglione indicato nel nome, solo ingresso.
INSERT INTO core.gate (gate_code, pavilion_id, name, direction_mode)
SELECT g.code, p.pavilion_id, g.name, 'ENTRY_ONLY'
FROM (VALUES ('P1-NORD','P1','P1 Nord'),('P1-SUD','P1','P1 Sud'),
             ('P2-OVEST','P2','P2 Ovest'),('P3-EST','P3','P3 Est')) AS g(code, pav, name)
JOIN core.pavilion p ON p.code = g.pav;
INSERT INTO core.gate_alias (alias_norm, gate_id)
SELECT a.alias, g.gate_id
FROM (VALUES ('P1 NORD','P1-NORD'),('P1-NORD','P1-NORD'),('P1 SUD','P1-SUD'),('P1-SUD','P1-SUD'),
             ('P2 OVEST','P2-OVEST'),('P2-OVEST','P2-OVEST'),('P3 EST','P3-EST'),('P3-EST','P3-EST'))
     AS a(alias, code)
JOIN core.gate g ON g.gate_code = a.code;

-- Canali -----------------------------------------------------------------
INSERT INTO core.sales_channel (code, name) VALUES
 ('ONLINE','Online'), ('BOX_OFFICE','Cassa'), ('PARTNER','Rivenditore partner');

-- Tipi biglietto canonici + alias 2024/2025 -------------------------------
INSERT INTO core.ticket_type (code, name, is_free, is_multi_day, default_persons) VALUES
 ('FULL','Intero',false,false,1),
 ('REDUCED','Ridotto 8-14 anni',false,false,1),
 ('FAMILY','Family (2 adulti + 2 ragazzi)',false,false,4),
 ('FREE_U8','Gratuito under 8',true,false,1),
 ('BUSINESS','Business Day',false,false,1),
 ('VIP','VIP Experience',false,false,1),
 ('PRESS','Accredito stampa',true,false,1),
 ('PASS_3D','Abbonamento 3 giorni',false,true,1);
INSERT INTO core.ticket_type_alias (alias_norm, ticket_type_id)
SELECT a.alias, t.ticket_type_id
FROM (VALUES
 ('INTERO','FULL'),('GIORNALIERO INTERO','FULL'),
 ('RIDOTTO','REDUCED'),('GIORNALIERO RIDOTTO 8-14 ANNI','REDUCED'),
 ('FAMILY','FAMILY'),('FAMILY 2 ADULTI + 2 RAGAZZI','FAMILY'),
 ('OMAGGIO U8','FREE_U8'),('GRATUITO UNDER 8','FREE_U8'),
 ('BUSINESS','BUSINESS'),('BUSINESS DAY (VENERDÌ MATTINA)','BUSINESS'),
 ('VIP','VIP'),('VIP EXPERIENCE','VIP'),
 ('STAMPA','PRESS'),('ACCREDITO STAMPA','PRESS'),
 ('ABB. 3GG','PASS_3D'),('ABBONAMENTO 3 GIORNI','PASS_3D')) AS a(alias, code)
JOIN core.ticket_type t ON t.code = a.code;

-- Codici sconto (percentuale osservata dai prezzi: da confermare, domanda Q-09)
INSERT INTO core.discount_code (code, description, observed_pct) VALUES
 ('SCUOLA','Convenzione scuole',NULL),
 ('STUDENTI','Convenzione studenti',NULL),
 ('EARLY10','Prevendita anticipata',0.10);

-- Fasce di eta' ------------------------------------------------------------
-- "famiglia" non e' una fascia di eta' ma una categoria del titolare: kind = FAMILY.
INSERT INTO core.age_band (code, kind, min_age, max_age, is_minor) VALUES
 ('0-7','AGE',0,7,true), ('8-13','AGE',8,13,true), ('14-17','AGE',14,17,true),
 ('18-24','AGE',18,24,false), ('25-34','AGE',25,34,false), ('35-44','AGE',35,44,false),
 ('45+','AGE',45,NULL,false), ('famiglia','FAMILY',NULL,NULL,false);

-- Province osservate nei file (21) + varianti grafiche ---------------------
INSERT INTO core.province (code, name) VALUES
 ('MI','Milano'),('MB','Monza e Brianza'),('BG','Bergamo'),('BS','Brescia'),('CO','Como'),
 ('CR','Cremona'),('LC','Lecco'),('LO','Lodi'),('PV','Pavia'),('VA','Varese'),('NO','Novara'),
 ('TO','Torino'),('GE','Genova'),('BO','Bologna'),('FI','Firenze'),('RM','Roma'),('NA','Napoli'),
 ('PR','Parma'),('PC','Piacenza'),('PD','Padova'),('VR','Verona');
-- alias = sigla e nome in maiuscolo (le grafie Milano/MILANO/milano collassano su UPPER())
INSERT INTO core.province_alias (alias_norm, province_id)
SELECT upper(code), province_id FROM core.province
UNION
SELECT upper(name), province_id FROM core.province;

-- Interessi dei contatti ---------------------------------------------------
INSERT INTO core.lead_interest (code) VALUES
 ('beta test'),('evento'),('lavoro/stage'),('newsletter'),('prodotto');

-- Ruoli --------------------------------------------------------------------
INSERT INTO core.app_role (code, description) VALUES
 ('ADMIN','Amministratore piattaforma'),
 ('COMMERCIAL','Staff commerciale (preventivi, contratti, pagamenti)'),
 ('OPS','Staff operativo (dashboard, anomalie, import)'),
 ('EXHIBITOR','Espositore: solo i propri dati'),
 ('SCANNER','Dispositivo/operatore di scansione stand'),
 ('BI_READER','Lettore analitico (Power BI)');

-- Regole di qualita' dei dati ----------------------------------------------
INSERT INTO dq.rule (rule_code, area, description, severity, default_action) VALUES
 ('GEN-001','generale','Conteggio righe lette <> righe caricate+scartate+quarantena','ERROR','NONE'),
 ('GEN-002','generale','File gia'' importato (stesso hash): nessuna riga duplicata','INFO','NONE'),
 ('COM-001','commerciale','Contratto senza id_espositore/P.IVA: risolto per nome','WARNING','LOADED_FLAGGED'),
 ('COM-002','commerciale','Ragione sociale non riconducibile con certezza a un espositore','ERROR','QUARANTINED'),
 ('COM-003','commerciale','Somma righe contratto <> imponibile di listino','ERROR','QUARANTINED'),
 ('COM-004','commerciale','Stand assegnato a due contratti attivi nella stessa edizione','CRITICAL','REJECTED'),
 ('COM-005','commerciale','Stand non attivo nell''edizione del contratto (attivo_dal)','ERROR','QUARANTINED'),
 ('COM-006','commerciale','Acconto o saldo non pagato','WARNING','LOADED_FLAGGED'),
 ('COM-007','commerciale','Importo pagato non fornito: assunto pari al dovuto','INFO','LOADED_FLAGGED'),
 ('COM-008','commerciale','Prezzo unitario riga <> listino dell''edizione','WARNING','LOADED_FLAGGED'),
 ('COM-009','commerciale','Flag rinnovo=1 ma nessun contratto precedente dello stesso espositore','WARNING','LOADED_FLAGGED'),
 ('COM-010','commerciale','Pagamento oltre la scadenza','INFO','NONE'),
 ('TKT-001','biglietteria','Codice biglietto duplicato','ERROR','REJECTED'),
 ('TKT-002','biglietteria','Provincia in grafia non canonica (sigla/nome/maiuscole)','INFO','AUTO_CORRECTED'),
 ('TKT-003','biglietteria','Provincia assente','INFO','LOADED_FLAGGED'),
 ('TKT-004','biglietteria','Tipo biglietto non mappato','ERROR','QUARANTINED'),
 ('TKT-005','biglietteria','Giorno valido fuori dalle date dell''edizione','ERROR','QUARANTINED'),
 ('TKT-006','biglietteria','Prezzo/persone non validi','ERROR','QUARANTINED'),
 ('TKT-007','biglietteria','Prezzo inferiore al listino del tipo (sconto applicato)','INFO','NONE'),
 ('TKT-008','biglietteria','Data acquisto successiva al giorno di validita''','WARNING','LOADED_FLAGGED'),
 ('GAT-001','tornelli','Codice biglietto della lettura inesistente in biglietteria','WARNING','LOADED_FLAGGED'),
 ('GAT-002','tornelli','Lettura fuori dall''orario di apertura','WARNING','LOADED_FLAGGED'),
 ('GAT-003','tornelli','Lettura con esito KO','INFO','LOADED_FLAGGED'),
 ('GAT-004','tornelli','Letture ripetute stesso varco/codice entro la finestra anti-doppio','WARNING','LOADED_FLAGGED'),
 ('GAT-005','tornelli','Lettura in giorno diverso da valid_day del biglietto','WARNING','LOADED_FLAGGED'),
 ('GAT-006','tornelli','Lettura precedente all''acquisto del biglietto','ERROR','LOADED_FLAGGED'),
 ('GAT-007','tornelli','Timestamp convertito da fuso sorgente a UTC','INFO','AUTO_CORRECTED'),
 ('VIS-001','visite stand','Conteggio orario anomalo (outlier statistico)','WARNING','LOADED_FLAGGED'),
 ('VIS-002','visite stand','Stand con visite ma senza contratto nell''edizione','ERROR','QUARANTINED'),
 ('VIS-003','visite stand','Visite fuori dall''orario di apertura','WARNING','LOADED_FLAGGED'),
 ('VIS-004','visite stand','Chiave (stand,data,ora) duplicata','ERROR','REJECTED'),
 ('LED-001','contatti','Stessa email (hash) ripetuta sullo stesso stand','WARNING','LOADED_FLAGGED'),
 ('LED-002','contatti','Minore (14-17) con consenso marketing registrato','CRITICAL','QUARANTINED'),
 ('LED-003','contatti','Consenso non verificabile (valore uniforme "SI", nessuna prova)','WARNING','LOADED_FLAGGED'),
 ('LED-004','contatti','Email in chiaro ridotta a hash; originale rimosso dallo staging','INFO','AUTO_CORRECTED'),
 ('LED-005','contatti','Stand e id_espositore non coerenti con il contratto dell''edizione','ERROR','QUARANTINED'),
 ('LED-006','contatti','Interesse mancante','INFO','LOADED_FLAGGED');

-- Controlli di riconciliazione ------------------------------------------------
INSERT INTO dq.reconciliation_check (check_code, description, measure) VALUES
 ('REC-01','Righe file = righe staging per batch','record importati'),
 ('REC-02','Biglietti staging = biglietti core + quarantena + scartati','biglietti venduti'),
 ('REC-03','Letture tornelli staging = core + quarantena + scartate','passaggi totali'),
 ('REC-04','Somma righe contratto = imponibile di listino','valore contrattualizzato'),
 ('REC-05','Imponibile contratti core = imponibile viste analytics = Power BI','ricavo contrattualizzato'),
 ('REC-06','Visite orarie core = foglio sorgente','visite stand'),
 ('REC-07','Stand SOLD = stand con contratto attivo','saturazione'),
 ('REC-08','Valori API KPI = viste analytics','tutti i KPI');

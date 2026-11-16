-- SOLO PER I TEST (B3a). Edizioni di prova con anni lontani, per non toccare le edizioni vere.
-- 2098: con giorni di apertura PROVVISORI DI PROVA. 2099: senza giorni (serve a provare EDITION_DATES_MISSING).
INSERT INTO core.edition (year, name, status) VALUES
 (2098, 'Edizione di prova con date', 'SALES_OPEN'),
 (2099, 'Edizione di prova senza date', 'SALES_OPEN');

INSERT INTO core.edition_day (edition_id, day_date, day_number, opens_at, closes_at)
SELECT e.edition_id, d.day_date, d.n, '09:00', '17:30'
FROM core.edition e
JOIN (VALUES (DATE '2098-12-18', 1), (DATE '2098-12-19', 2), (DATE '2098-12-20', 3)) AS d(day_date, n) ON true
WHERE e.year = 2098;

INSERT INTO core.price_list (edition_id, origin, status, deposit_pct, balance_days_before)
SELECT edition_id, 'CLIENT_LIST', 'PUBLISHED', 0.3000, 30 FROM core.edition WHERE year IN (2098, 2099);

INSERT INTO core.price_item (price_list_id, code, name, item_type, unit, unit_price, pct, pavilion_id, position_type, max_quantity)
SELECT pl.price_list_id, v.code, v.name, v.item_type, v.unit, v.unit_price, v.pct,
       (SELECT pavilion_id FROM core.pavilion WHERE code = v.pav), v.pos, v.maxq
FROM core.price_list pl
JOIN core.edition e ON e.edition_id = pl.edition_id
JOIN (VALUES
  ('SP-P1',        'Spazio padiglione 1',   'SPACE',       'SQM',          100.00, NULL::numeric, 'P1',          NULL,        NULL::int),
  ('SP-P2',        'Spazio padiglione 2',   'SPACE',       'SQM',           80.00, NULL,          'P2',          NULL,        NULL),
  ('MAG-ANGOLO',   'Maggiorazione angolo',  'SURCHARGE',   'PCT_OF_SPACE',  NULL,  0.1000,        NULL::text,    'ANGOLO',    NULL),
  ('MAG-PENISOLA', 'Maggiorazione penisola','SURCHARGE',   'PCT_OF_SPACE',  NULL,  0.1500,        NULL,          'PENISOLA',  NULL),
  ('MAG-ISOLA',    'Maggiorazione isola',   'SURCHARGE',   'PCT_OF_SPACE',  NULL,  0.2000,        NULL,          'ISOLA',     NULL),
  ('EX-EL6',       'Allaccio elettrico',    'EXTRA',       'EACH',          50.00, NULL,          NULL,          NULL,        NULL),
  ('SPN-GOLD',     'Sponsor gold',          'SPONSORSHIP', 'PACKAGE',     5000.00, NULL,          NULL,          NULL,        1)
) AS v(code, name, item_type, unit, unit_price, pct, pav, pos, maxq)
  ON (e.year = 2098 OR v.code IN ('SP-P1', 'MAG-ANGOLO'))
WHERE e.year IN (2098, 2099);

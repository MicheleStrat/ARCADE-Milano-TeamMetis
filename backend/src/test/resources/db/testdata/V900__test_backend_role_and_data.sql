-- SOLO PER I TEST: account di login del backend e due espositori di prova.
-- NOINHERIT: senza SET ROLE l'account non ha nessun permesso sui dati.
CREATE ROLE arcade_backend LOGIN NOINHERIT PASSWORD 'test' IN ROLE arcade_app, arcade_portal;

INSERT INTO core.exhibitor_category (name) VALUES ('Categoria di prova');

INSERT INTO core.exhibitor (exhibitor_code, legal_name, legal_name_norm, vat_number, category_id)
SELECT v.code, v.legal_name, upper(v.legal_name), v.vat, c.category_id
FROM (VALUES ('ESP901', 'Alfa Srl', 'IT00000000901'),
             ('ESP902', 'Beta Spa', 'IT00000000902')) AS v(code, legal_name, vat)
CROSS JOIN core.exhibitor_category c
WHERE c.name = 'Categoria di prova';

-- Crea (o aggiorna la password di) l'account di login del backend sul database locale.
-- NOINHERIT: senza SET ROLE l'account non ha permessi sui dati; il backend passa ad arcade_app o
-- arcade_portal solo dentro la transazione di ogni richiesta.
-- La password NON e' in questo file: si passa con -v pwd=... (vedi backend/README.md).
SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'arcade_backend') AS mancante \gset
\if :mancante
  CREATE ROLE arcade_backend LOGIN NOINHERIT PASSWORD :'pwd' IN ROLE arcade_app, arcade_portal;
\else
  ALTER ROLE arcade_backend LOGIN NOINHERIT PASSWORD :'pwd';
\endif

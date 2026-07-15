-- Init-script voor de self-hosted Postgres (component `mgzpg`) van de magazijn-a-peer op ZAD.
--
-- Waarom self-hosted i.p.v. ZAD's managed Postgres: die laat ons de init/schema's niet naar eigen
-- inzicht inrichten. Deze Postgres beheren we volledig; dit script draait ÉÉNMALIG bij een lege
-- PGDATA (postgres-image: alles in /docker-entrypoint-initdb.d/*.sql wordt dan als POSTGRES_USER
-- tegen POSTGRES_DB uitgevoerd).
--
-- Doel: drie GEÏSOLEERDE schema's binnen één database (POSTGRES_DB=fsc), zodat de golang-migrate
-- `schema_migrations`-tellers van manager/controller/txlog elkaar niet in de weg zitten. Delen ze
-- één `public.schema_migrations`, dan ziet de controller-migratie de reeds door de manager gezette
-- versie, denkt "al gemigreerd" en slaat zijn eigen migraties over -> `controller.services` ontstaat
-- nooit -> `ERROR: relation "controller.services" does not exist (SQLSTATE 42P01)`.
--
-- Elke FSC-component verbindt met `...?search_path=<eigen schema>` (zie deploy/zad/upsert-peer.sh,
-- de _pg_dsn-helper). De namen hieronder MOETEN sporen met ZAD_MGR_SCHEMA / ZAD_CTL_SCHEMA /
-- ZAD_TXLOG_SCHEMA (defaults: manager / controller / txlog).
--
-- Attachment-pad in de ZAD-UI: /docker-entrypoint-initdb.d/10-schemas.sql (zie cert-manifest.md).
-- Let op: het script draait alleen bij een VERSE datamap. Zonder persistent volume is de DB
-- ephemeral (schema's + migraties worden bij elke nieuwe pod opnieuw opgebouwd) — akkoord voor test;
-- voor een blijvende peer een persistent volume koppelen.

CREATE SCHEMA IF NOT EXISTS manager;
CREATE SCHEMA IF NOT EXISTS controller;
CREATE SCHEMA IF NOT EXISTS txlog;

-- POSTGRES_USER (=fsc) is eigenaar van de database en van de zojuist aangemaakte schema's, dus heeft
-- al volledige rechten. Expliciete GRANT's voor de duidelijkheid / mocht je later een aparte app-rol
-- introduceren:
GRANT ALL ON SCHEMA manager, controller, txlog TO CURRENT_USER;

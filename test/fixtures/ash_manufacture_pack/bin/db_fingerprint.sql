-- Structural fingerprint of the manufactured database, for the idempotency
-- oracle in bin/qualify.sh.
--
-- WHY THIS EXISTS
-- The tree oracle (T1/T2/T3 sha256 manifests) compares FILES. It says
-- nothing about what `mix ash.setup` / `mix ash.migrate` did to Postgres.
-- A migration that is generated once but applied twice, or a second
-- `ash.codegen` that emits a fresh migration for an unchanged resource,
-- leaves the tree byte-identical and the DATABASE different. This file is
-- the second oracle: run it after each lifecycle step and diff the output.
--
-- WHY EACH PROJECTION
--  * information_schema.columns  -- the table shape itself.
--  * table_constraints + key_column_usage -- primary/foreign/unique keys and
--    the columns they cover. LEFT JOIN, not JOIN: a CHECK constraint has no
--    key_column_usage row and an inner join would silently drop it.
--  * pg_indexes -- Ash `identities` land as unique INDEXes, not as
--    constraints, so information_schema alone does not see them.
--  * schema_migrations -- which migration versions are actually applied.
--
-- WHAT IS DELIBERATELY EXCLUDED, AND WHY
--  * Constraint names matching '^[0-9]+_[0-9]+_[0-9]+_not_null$' embed the
--    namespace OID and the table OID (observed: `2200_69000_1_not_null` on
--    `books`). Those are assigned by Postgres, are database-local, and are
--    not part of the manufactured schema. The NOT NULL fact they encode is
--    already captured by `is_nullable` in the COLUMN rows above, so
--    dropping them loses no information.
--  * `schema_migrations` is excluded from the COLUMN rows because it is
--    Ecto's bookkeeping table, not a manufactured surface. Its CONTENT is
--    still projected, as MIGRATION rows.
--  * `schema_migrations.inserted_at` is not projected: it is wall-clock
--    time, so it would differ on every capture and make the diff useless.
--
-- SCOPE: output is comparable only BETWEEN CAPTURES OF THE SAME DATABASE.
-- Index and constraint names are database-local, so D-files from two
-- different qualification runs are expected to differ.
--
-- Usage: psql -d <db> -f db_fingerprint.sql

-- A SQL error must fail the capture loudly rather than write a short file
-- that a later diff would compare successfully against another short file.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

SELECT 'COLUMN|'
       || table_name || '|'
       || column_name || '|'
       || data_type || '|'
       || is_nullable || '|'
       || coalesce(column_default, '~')
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name <> 'schema_migrations'
ORDER BY table_name, column_name;

SELECT 'CONSTRAINT|'
       || tc.table_name || '|'
       || tc.constraint_name || '|'
       || tc.constraint_type || '|'
       || coalesce(kcu.column_name, '~')
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
       ON kcu.constraint_schema = tc.constraint_schema
      AND kcu.constraint_name = tc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.constraint_name::text !~ '^[0-9]+_[0-9]+_[0-9]+_not_null$'
ORDER BY tc.table_name, tc.constraint_name, kcu.column_name;

SELECT 'INDEX|'
       || tablename || '|'
       || indexname || '|'
       || indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

SELECT 'MIGRATION|' || version::text
FROM schema_migrations
ORDER BY version;

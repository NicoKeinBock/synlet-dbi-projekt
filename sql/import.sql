-- SynLet – Datenimport (PostgreSQL, psql)
-- Voraussetzung: sql/schema.sql wurde ausgeführt und scripts/prepare_import.py hat build/ erzeugt.
-- Aufruf aus dem Repo-Ordner:
--   psql -d synlet -f sql/schema.sql -f sql/import.sql -f sql/procedures.sql
-- \copy liest die Dateien auf dem Client, die Pfade sind relativ zum aktuellen Ordner.

\set ON_ERROR_STOP on
BEGIN;

TRUNCATE essentiality_evidence, essentiality, orthology, oma_protein,
         interaction_phenotype, ontology_term, interaction, data_source, publication,
         experimental_system, gene_accession, gene_synonym, gene CASCADE;

\copy data_source           FROM 'build/data_source.csv'           WITH (FORMAT csv, HEADER true)
\copy gene                  FROM 'build/gene.csv'                  WITH (FORMAT csv, HEADER true)
\copy gene_synonym          FROM 'build/gene_synonym.csv'          WITH (FORMAT csv, HEADER true)
\copy gene_accession        FROM 'build/gene_accession.csv'        WITH (FORMAT csv, HEADER true)
\copy experimental_system   FROM 'build/experimental_system.csv'   WITH (FORMAT csv, HEADER true)
\copy publication           FROM 'build/publication.csv'           WITH (FORMAT csv, HEADER true)
\copy interaction           FROM 'build/interaction.csv'           WITH (FORMAT csv, HEADER true)
\copy ontology_term         FROM 'build/ontology_term.csv'         WITH (FORMAT csv, HEADER true)
\copy interaction_phenotype FROM 'build/interaction_phenotype.csv' WITH (FORMAT csv, HEADER true)
\copy oma_protein           FROM 'build/oma_protein.csv'           WITH (FORMAT csv, HEADER true)
\copy orthology             FROM 'build/orthology.csv'             WITH (FORMAT csv, HEADER true)
\copy essentiality          FROM 'build/essentiality.csv'          WITH (FORMAT csv, HEADER true)
\copy essentiality_evidence FROM 'build/essentiality_evidence.csv' WITH (FORMAT csv, HEADER true)

-- SERIAL-Sequenzen auf die importierten IDs nachziehen
SELECT setval(pg_get_serial_sequence('data_source', 'source_id'), (SELECT max(source_id) FROM data_source));
SELECT setval(pg_get_serial_sequence('experimental_system', 'system_id'), (SELECT max(system_id) FROM experimental_system));

COMMIT;
ANALYZE;

-- Kontrolle: Zeilen pro Tabelle
SELECT 'organism' AS tabelle, count(*) AS zeilen FROM organism
UNION ALL SELECT 'gene', count(*) FROM gene
UNION ALL SELECT 'gene_synonym', count(*) FROM gene_synonym
UNION ALL SELECT 'gene_accession', count(*) FROM gene_accession
UNION ALL SELECT 'experimental_system', count(*) FROM experimental_system
UNION ALL SELECT 'publication', count(*) FROM publication
UNION ALL SELECT 'data_source', count(*) FROM data_source
UNION ALL SELECT 'interaction', count(*) FROM interaction
UNION ALL SELECT 'ontology_term', count(*) FROM ontology_term
UNION ALL SELECT 'interaction_phenotype', count(*) FROM interaction_phenotype
UNION ALL SELECT 'oma_protein', count(*) FROM oma_protein
UNION ALL SELECT 'orthology', count(*) FROM orthology
UNION ALL SELECT 'essentiality', count(*) FROM essentiality
UNION ALL SELECT 'essentiality_evidence', count(*) FROM essentiality_evidence;

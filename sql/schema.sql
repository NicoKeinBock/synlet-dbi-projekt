-- SynLet – Datenbankschema (Entwurf, PostgreSQL)
-- Entspricht docs/ERD.md. Bei Oracle: BOOLEAN -> NUMBER(1), TEXT -> CLOB, VARCHAR -> VARCHAR2.

DROP TABLE IF EXISTS essentiality_evidence, essentiality, orthology, oma_protein,
    interaction_phenotype, ontology_term, interaction, data_source, publication,
    experimental_system, gene_accession, gene_synonym, gene, organism CASCADE;

CREATE TABLE organism (
    tax_id          INTEGER      PRIMARY KEY,          -- 9606, 10090, 559292
    scientific_name VARCHAR(200) NOT NULL,
    common_name     VARCHAR(100),
    oma_code        VARCHAR(10)  UNIQUE                -- HUMAN, MOUSE, YEAST
);

CREATE TABLE gene (
    entrez_id       INTEGER      PRIMARY KEY,
    tax_id          INTEGER      NOT NULL REFERENCES organism (tax_id),
    biogrid_id      INTEGER      UNIQUE,
    official_symbol VARCHAR(100),
    systematic_name VARCHAR(100)                       -- z. B. YNL271C (Hefe-ORF)
);

CREATE TABLE gene_synonym (
    entrez_id INTEGER      NOT NULL REFERENCES gene (entrez_id) ON DELETE CASCADE,
    synonym   VARCHAR(255) NOT NULL,
    PRIMARY KEY (entrez_id, synonym)
);

CREATE TABLE gene_accession (
    entrez_id INTEGER     NOT NULL REFERENCES gene (entrez_id) ON DELETE CASCADE,
    accession VARCHAR(50) NOT NULL,
    acc_type  VARCHAR(20) NOT NULL CHECK (acc_type IN ('SWISS-PROT', 'TREMBL', 'REFSEQ')),
    PRIMARY KEY (entrez_id, accession)
);

CREATE TABLE experimental_system (
    system_id   SERIAL       PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,                 -- z. B. Synthetic Lethality
    system_type VARCHAR(20)  NOT NULL,                 -- genetic / physical
    psi_mi_code VARCHAR(20)  UNIQUE                    -- z. B. MI:2370
);

CREATE TABLE publication (
    pubmed_id    INTEGER PRIMARY KEY,
    first_author VARCHAR(200),
    pub_year     INTEGER
);

CREATE TABLE data_source (
    source_id     SERIAL       PRIMARY KEY,
    name          VARCHAR(50)  NOT NULL,               -- BioGRID
    release       VARCHAR(20)  NOT NULL,               -- 5.0.263 / 4.4.225
    file_name     VARCHAR(255) NOT NULL,
    download_date DATE
);

CREATE TABLE interaction (
    interaction_id  INTEGER      PRIMARY KEY,          -- BioGRID Interaction ID
    gene_a_id       INTEGER      NOT NULL REFERENCES gene (entrez_id),
    gene_b_id       INTEGER      NOT NULL REFERENCES gene (entrez_id),
    system_id       INTEGER      NOT NULL REFERENCES experimental_system (system_id),
    pubmed_id       INTEGER      REFERENCES publication (pubmed_id),
    source_id       INTEGER      NOT NULL REFERENCES data_source (source_id),
    throughput      VARCHAR(50),                       -- High/Low Throughput
    score           DECIMAL,
    qualifications  TEXT,
    source_database VARCHAR(20)                        -- BIOGRID / POMBASE
);

CREATE TABLE ontology_term (
    term_id  VARCHAR(30)  PRIMARY KEY,                 -- z. B. APO:0000112
    name     VARCHAR(200) NOT NULL,
    category VARCHAR(50)
);

CREATE TABLE interaction_phenotype (
    interaction_id INTEGER     NOT NULL REFERENCES interaction (interaction_id) ON DELETE CASCADE,
    term_id        VARCHAR(30) NOT NULL REFERENCES ontology_term (term_id),
    PRIMARY KEY (interaction_id, term_id)
);

CREATE TABLE oma_protein (
    oma_id    VARCHAR(20) PRIMARY KEY,                 -- z. B. HUMAN01436
    tax_id    INTEGER     NOT NULL REFERENCES organism (tax_id),
    entrez_id INTEGER     REFERENCES gene (entrez_id)  -- NULL erlaubt
);

CREATE TABLE orthology (
    oma_id_1  VARCHAR(20) NOT NULL REFERENCES oma_protein (oma_id),   -- immer Mensch
    oma_id_2  VARCHAR(20) NOT NULL REFERENCES oma_protein (oma_id),   -- Maus oder Hefe
    rel_type  VARCHAR(3)  NOT NULL CHECK (rel_type IN ('1:1', '1:n', 'm:1', 'm:n')),
    oma_group INTEGER,
    PRIMARY KEY (oma_id_1, oma_id_2)
);

CREATE TABLE essentiality (
    entrez_id    INTEGER PRIMARY KEY REFERENCES gene (entrez_id),
    is_essential BOOLEAN NOT NULL
);

CREATE TABLE essentiality_evidence (
    entrez_id INTEGER NOT NULL REFERENCES essentiality (entrez_id) ON DELETE CASCADE,
    pubmed_id INTEGER NOT NULL REFERENCES publication (pubmed_id),
    PRIMARY KEY (entrez_id, pubmed_id)
);

CREATE INDEX idx_interaction_gene_a ON interaction (gene_a_id);
CREATE INDEX idx_interaction_gene_b ON interaction (gene_b_id);
CREATE INDEX idx_oma_protein_entrez ON oma_protein (entrez_id);
CREATE INDEX idx_orthology_oma_2    ON orthology (oma_id_2);

INSERT INTO organism (tax_id, scientific_name, common_name, oma_code) VALUES
    (9606,   'Homo sapiens',                   'Mensch',   'HUMAN'),
    (10090,  'Mus musculus',                   'Hausmaus', 'MOUSE'),
    (559292, 'Saccharomyces cerevisiae S288c', 'Bierhefe', 'YEAST');

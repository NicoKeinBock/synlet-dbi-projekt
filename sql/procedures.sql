-- SynLet – Views und Funktionen (PostgreSQL)
-- Kernfrage der Wissenschaftlerin: Eine Patientin hat ein mutiertes Gen X.
-- Welche menschlichen Gene sind mit X synthetisch letal? Wenn man diese Partner
-- hemmt, sterben nur die Krebszellen (X defekt), gesunde Zellen (X intakt) überleben.
--
-- Evidenz kommt aus zwei Wegen:
--   1. direkt:  SL-Paar X–P im Menschen (BioGRID)
--   2. über Orthologe:  X ~ X' (Maus/Hefe),  X'–P' ist SL im Modellorganismus,
--      P' ~ P (Mensch)  =>  P ist ein Kandidat für den Menschen
-- Essentielle Partner (SNAP) sind schlechte Ziele, weil ihre Hemmung auch gesunde
-- Zellen tötet.

-- ------------------------------------------------------------------ Views

-- Jedes SL-Paar in beide Richtungen, damit man nur nach gene_id filtern muss.
CREATE OR REPLACE VIEW v_sl_pair AS
SELECT i.interaction_id, i.gene_a_id AS gene_id, i.gene_b_id AS partner_id, i.pubmed_id, i.source_id
FROM interaction i
UNION ALL
SELECT i.interaction_id, i.gene_b_id, i.gene_a_id, i.pubmed_id, i.source_id
FROM interaction i
WHERE i.gene_a_id <> i.gene_b_id;

-- Orthologie auf Gen-Ebene: menschliches Gen <-> Gen in Maus/Hefe.
CREATE OR REPLACE VIEW v_human_ortholog AS
SELECT DISTINCT ph.entrez_id AS human_id,
                pm.entrez_id AS model_id,
                pm.tax_id    AS model_tax,
                o.rel_type
FROM orthology o
JOIN oma_protein ph ON ph.oma_id = o.oma_id_1
JOIN oma_protein pm ON pm.oma_id = o.oma_id_2
WHERE ph.entrez_id IS NOT NULL
  AND pm.entrez_id IS NOT NULL;

-- Lesbare Liste aller SL-Paare mit Symbolen und Organismus.
CREATE OR REPLACE VIEW v_sl_pair_readable AS
SELECT i.interaction_id,
       oa.scientific_name AS organism_a, ga.official_symbol AS gene_a,
       ob.scientific_name AS organism_b, gb.official_symbol AS gene_b,
       i.throughput, i.pubmed_id, p.first_author, p.pub_year
FROM interaction i
JOIN gene ga ON ga.entrez_id = i.gene_a_id
JOIN gene gb ON gb.entrez_id = i.gene_b_id
JOIN organism oa ON oa.tax_id = ga.tax_id
JOIN organism ob ON ob.tax_id = gb.tax_id
LEFT JOIN publication p ON p.pubmed_id = i.pubmed_id;

-- ------------------------------------------------------------------ Funktionen

-- Sucht ein menschliches Gen über Entrez-ID, offizielles Symbol oder Synonym.
CREATE OR REPLACE FUNCTION find_human_gene(p_gene TEXT)
RETURNS INTEGER
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_id INTEGER;
BEGIN
    IF p_gene ~ '^\d+$' THEN
        SELECT entrez_id INTO v_id FROM gene
        WHERE entrez_id = p_gene::INTEGER AND tax_id = 9606;
    ELSE
        SELECT entrez_id INTO v_id FROM gene
        WHERE tax_id = 9606 AND upper(official_symbol) = upper(p_gene)
        ORDER BY entrez_id LIMIT 1;

        IF v_id IS NULL THEN
            SELECT s.entrez_id INTO v_id
            FROM gene_synonym s JOIN gene g ON g.entrez_id = s.entrez_id
            WHERE g.tax_id = 9606 AND upper(s.synonym) = upper(p_gene)
            ORDER BY s.entrez_id LIMIT 1;
        END IF;
    END IF;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Menschliches Gen "%" nicht gefunden', p_gene;
    END IF;
    RETURN v_id;
END;
$$;

-- Alle SL-Partner von Gen X mit Evidenz, eine Zeile pro Partner und Evidenzweg.
CREATE OR REPLACE FUNCTION sl_partners(p_gene TEXT)
RETURNS TABLE (
    partner_entrez    INTEGER,
    partner_symbol    VARCHAR,
    evidence_organism VARCHAR,
    model_gene_x      VARCHAR,
    model_partner     VARCHAR,
    orthology_types   TEXT,
    n_interactions    BIGINT,
    n_publications    BIGINT,
    is_essential      BOOLEAN
)
LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT find_human_gene(p_gene) AS id
    ),
    direct AS (                       -- Weg 1: SL-Paar direkt im Menschen
        SELECT p.partner_id      AS human_partner,
               9606              AS tax,
               NULL::INTEGER     AS model_x,
               NULL::INTEGER     AS model_p,
               NULL::TEXT        AS rel,
               p.interaction_id,
               p.pubmed_id
        FROM x
        JOIN v_sl_pair p ON p.gene_id = x.id
        JOIN gene g      ON g.entrez_id = p.partner_id AND g.tax_id = 9606
        WHERE p.partner_id <> x.id
    ),
    via AS (                          -- Weg 2: über Orthologe in Maus/Hefe
        SELECT hp.human_id,
               ox.model_tax,
               ox.model_id,
               p.partner_id,
               ox.rel_type || ' / ' || hp.rel_type,
               p.interaction_id,
               p.pubmed_id
        FROM x
        JOIN v_human_ortholog ox ON ox.human_id = x.id
        JOIN v_sl_pair p         ON p.gene_id = ox.model_id
        JOIN gene gp             ON gp.entrez_id = p.partner_id AND gp.tax_id = ox.model_tax
        JOIN v_human_ortholog hp ON hp.model_id = p.partner_id AND hp.model_tax = ox.model_tax
        WHERE hp.human_id <> x.id
    ),
    evidence AS (
        SELECT * FROM direct
        UNION ALL
        SELECT * FROM via
    )
    SELECT e.human_partner,
           gh.official_symbol,
           o.scientific_name,
           gx.official_symbol,
           gp.official_symbol,
           string_agg(DISTINCT e.rel, ', '),
           count(DISTINCT e.interaction_id),
           count(DISTINCT e.pubmed_id),
           es.is_essential
    FROM evidence e
    JOIN gene gh          ON gh.entrez_id = e.human_partner
    JOIN organism o       ON o.tax_id = e.tax
    LEFT JOIN gene gx     ON gx.entrez_id = e.model_x
    LEFT JOIN gene gp     ON gp.entrez_id = e.model_p
    LEFT JOIN essentiality es ON es.entrez_id = e.human_partner
    GROUP BY e.human_partner, gh.official_symbol, o.scientific_name,
             gx.official_symbol, gp.official_symbol, es.is_essential
    ORDER BY gh.official_symbol, o.scientific_name;
$$;

-- Zusammenfassung pro Partner: Wie viele Organismen stützen das SL-Paar, ist der
-- Partner als Ziel geeignet? Sortiert nach Eignung.
CREATE OR REPLACE FUNCTION sl_candidates(p_gene TEXT)
RETURNS TABLE (
    partner_entrez  INTEGER,
    partner_symbol  VARCHAR,
    n_organisms     BIGINT,
    organisms       TEXT,
    n_interactions  NUMERIC,
    n_publications  NUMERIC,
    is_essential    BOOLEAN,
    bewertung       TEXT
)
LANGUAGE sql STABLE AS $$
    SELECT s.partner_entrez,
           s.partner_symbol,
           count(DISTINCT s.evidence_organism),
           string_agg(DISTINCT s.evidence_organism, ', '),
           sum(s.n_interactions),
           sum(s.n_publications),
           s.is_essential,
           CASE
               WHEN s.is_essential IS FALSE THEN 'Kandidat (nicht essentiell)'
               WHEN s.is_essential IS TRUE  THEN 'Vorsicht: essentiell, Hemmung schadet auch gesunden Zellen'
               ELSE 'Essentiality unbekannt'
           END
    FROM sl_partners(p_gene) s
    GROUP BY s.partner_entrez, s.partner_symbol, s.is_essential
    ORDER BY count(DISTINCT s.evidence_organism) DESC,
             (s.is_essential IS FALSE) DESC,
             sum(s.n_interactions) DESC,
             s.partner_symbol;
$$;

-- Orthologe eines menschlichen Gens in Maus und Hefe.
CREATE OR REPLACE FUNCTION orthologs_of(p_gene TEXT)
RETURNS TABLE (
    organism      VARCHAR,
    model_entrez  INTEGER,
    model_symbol  VARCHAR,
    rel_type      VARCHAR
)
LANGUAGE sql STABLE AS $$
    SELECT o.scientific_name, g.entrez_id, g.official_symbol, v.rel_type
    FROM v_human_ortholog v
    JOIN gene g     ON g.entrez_id = v.model_id
    JOIN organism o ON o.tax_id = v.model_tax
    WHERE v.human_id = find_human_gene(p_gene)
    ORDER BY o.scientific_name, g.official_symbol;
$$;

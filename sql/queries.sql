-- SynLet – Abfragen (PostgreSQL)
-- Voraussetzung: schema.sql, import.sql und procedures.sql wurden ausgeführt.
-- Gen X für die Abfragen 1–4 hier ändern:
\set gen_x 'BRCA1'

-- 1. Kernfrage: SL-Kandidaten für Gen X, nach Eignung sortiert
SELECT * FROM sl_candidates(:'gen_x');

-- 2. Nur geeignete Ziele: nicht essentiell, nach Anzahl stützender Organismen
SELECT partner_symbol, organisms, n_interactions, n_publications
FROM sl_candidates(:'gen_x')
WHERE is_essential IS FALSE
ORDER BY n_organisms DESC, n_interactions DESC;

-- 3. Detail: jede Evidenz einzeln (direkt oder über welches Orthologenpaar)
SELECT * FROM sl_partners(:'gen_x');

-- 4. Orthologe von Gen X in Maus und Hefe
SELECT * FROM orthologs_of(:'gen_x');

-- 5. Anzahl SL-Interaktionen pro Organismus(-paar)
SELECT oa.scientific_name AS organism_a, ob.scientific_name AS organism_b, count(*) AS sl_interaktionen
FROM interaction i
JOIN gene ga ON ga.entrez_id = i.gene_a_id
JOIN gene gb ON gb.entrez_id = i.gene_b_id
JOIN organism oa ON oa.tax_id = ga.tax_id
JOIN organism ob ON ob.tax_id = gb.tax_id
GROUP BY oa.scientific_name, ob.scientific_name
ORDER BY sl_interaktionen DESC;

-- 6. Gene mit den meisten SL-Partnern pro Organismus (Top 5)
SELECT organism, symbol, partner
FROM (
    SELECT o.scientific_name AS organism, g.official_symbol AS symbol,
           count(DISTINCT p.partner_id) AS partner,
           rank() OVER (PARTITION BY o.scientific_name ORDER BY count(DISTINCT p.partner_id) DESC) AS rang
    FROM v_sl_pair p
    JOIN gene g     ON g.entrez_id = p.gene_id
    JOIN organism o ON o.tax_id = g.tax_id
    GROUP BY o.scientific_name, g.official_symbol
) t
WHERE rang <= 5
ORDER BY organism, partner DESC;

-- 7. Konservierte SL-Paare: im Menschen SL UND über Orthologe auch in Maus oder Hefe SL
SELECT DISTINCT gh1.official_symbol AS gen_1, gh2.official_symbol AS gen_2,
       o.scientific_name AS bestaetigt_in,
       gm1.official_symbol AS ortholog_1, gm2.official_symbol AS ortholog_2
FROM v_sl_pair h
JOIN gene gh1 ON gh1.entrez_id = h.gene_id    AND gh1.tax_id = 9606
JOIN gene gh2 ON gh2.entrez_id = h.partner_id AND gh2.tax_id = 9606
JOIN v_human_ortholog o1 ON o1.human_id = h.gene_id
JOIN v_human_ortholog o2 ON o2.human_id = h.partner_id AND o2.model_tax = o1.model_tax
JOIN v_sl_pair m ON m.gene_id = o1.model_id AND m.partner_id = o2.model_id
JOIN gene gm1 ON gm1.entrez_id = o1.model_id
JOIN gene gm2 ON gm2.entrez_id = o2.model_id
JOIN organism o ON o.tax_id = o1.model_tax
WHERE gh1.official_symbol < gh2.official_symbol
ORDER BY gen_1, gen_2;

-- 8. Wie viele SL-Gene aus Maus/Hefe lassen sich auf den Menschen übertragen?
SELECT o.scientific_name,
       count(DISTINCT g.entrez_id) AS sl_gene,
       count(DISTINCT g.entrez_id) FILTER (WHERE v.human_id IS NOT NULL) AS mit_menschlichem_ortholog
FROM gene g
JOIN organism o ON o.tax_id = g.tax_id
LEFT JOIN v_human_ortholog v ON v.model_id = g.entrez_id
WHERE g.tax_id <> 9606
  AND EXISTS (SELECT 1 FROM v_sl_pair p WHERE p.gene_id = g.entrez_id)
GROUP BY o.scientific_name;

-- 9. Anteil essentieller Gene unter den menschlichen SL-Genen
SELECT CASE e.is_essential WHEN TRUE THEN 'essentiell' WHEN FALSE THEN 'nicht essentiell'
            ELSE 'unbekannt' END AS essentiality,
       count(DISTINCT g.entrez_id) AS gene
FROM gene g
LEFT JOIN essentiality e ON e.entrez_id = g.entrez_id
WHERE g.tax_id = 9606
  AND EXISTS (SELECT 1 FROM v_sl_pair p WHERE p.gene_id = g.entrez_id)
GROUP BY 1
ORDER BY gene DESC;

-- 10. Verteilung der Orthologie-Typen pro Modellorganismus
SELECT o.scientific_name, v.rel_type, count(*) AS paare
FROM v_human_ortholog v
JOIN organism o ON o.tax_id = v.model_tax
GROUP BY o.scientific_name, v.rel_type
ORDER BY o.scientific_name, v.rel_type;

-- 11. Häufigste Phänotypen der SL-Interaktionen
SELECT t.term_id, t.name, count(*) AS interaktionen
FROM interaction_phenotype ip
JOIN ontology_term t ON t.term_id = ip.term_id
GROUP BY t.term_id, t.name
ORDER BY interaktionen DESC
LIMIT 10;

-- 12. Publikationen mit den meisten SL-Interaktionen
SELECT p.pubmed_id, p.first_author, p.pub_year, count(*) AS interaktionen
FROM interaction i
JOIN publication p ON p.pubmed_id = i.pubmed_id
GROUP BY p.pubmed_id, p.first_author, p.pub_year
ORDER BY interaktionen DESC
LIMIT 10;

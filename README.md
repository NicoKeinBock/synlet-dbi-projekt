# SynLet – DBI-Projekt

Gruppe: Klug, Kranebitter, Scheuringer
Organismen: *Mus musculus* (Hausmaus) und *Saccharomyces cerevisiae* (Bierhefe), dazu *Homo sapiens*

Ziel: synthetisch letale (SL) Genpaare aus Modellorganismen über Orthologie auf den Menschen übertragen und mit Essentiality-Daten anreichern.

**ERD (Whiteboard):** https://claude.ai/artifact/PZif19EJMd9ke5vmfKWYuL

## Schnellstart

```bash
python3 scripts/prepare_import.py          # Rohdaten -> build/*.csv (ca. 40 s)
createdb synlet
psql -d synlet -f sql/schema.sql -f sql/import.sql -f sql/procedures.sql
psql -d synlet -c "SELECT * FROM sl_candidates('BRCA1');"
```

Ergebnis: **PARP1**, gestützt durch Mensch und Maus, nicht essentiell. Das ist das klassische SL-Paar hinter den PARP-Hemmern.

## Repo-Inhalt

| Pfad | Inhalt |
|---|---|
| `docs/Dokumentation.pdf` / `.md` | Projektdokumentation (Annahmen, Entscheidungen, Import, Abfragen, Einschränkungen) |
| `docs/erd.png` / `.svg` / `.dot` | ER-Diagramm in Crow's-Foot-Notation (Graphviz) |
| `docs/ERD.md` | ER-Diagramm als Mermaid (wird auf GitHub gerendert) und offene Fragen |
| `sql/schema.sql` | Tabellen, Schlüssel, Constraints, Indizes |
| `sql/import.sql` | Lädt `build/*.csv` mit `\copy` |
| `sql/procedures.sql` | Views und Funktionen: `sl_candidates`, `sl_partners`, `orthologs_of`, `find_human_gene` |
| `sql/queries.sql` | 12 Analyse-Abfragen |
| `scripts/prepare_import.py` | Bereitet die Rohdaten auf (nur Python-Standardbibliothek) |
| `scripts/check_coverage.py` | Prüft die ID-Abdeckung zwischen den Datensätzen |
| `data/` | Rohdaten von BioGRID, OMA und SNAP |

## Daten (`data/`)

Die großen BioGRID-Dateien liegen gzip-komprimiert im Repo, weil GitHub Dateien über 100 MB ablehnt. Entpacken mit:

```bash
gunzip -k data/synlethality/*.gz
```

| Ordner | Datei | Quelle | Version / Stand |
|---|---|---|---|
| `synlethality/` | `BIOGRID-SYSTEM-Synthetic_Lethality-5.0.263.tab3.txt.gz` | [BioGRID Latest Release](https://downloads.thebiogrid.org/File/BioGRID/Latest-Release/BIOGRID-SYSTEM-LATEST.tab3.zip) | 5.0.263 |
| `synlethality/` | `BIOGRID-ORGANISM-Homo_sapiens-4.4.225.mitab.txt.gz` | [BioGRID 4.4.225 Archiv](https://downloads.thebiogrid.org/File/BioGRID/Release-Archive/BIOGRID-4.4.225/BIOGRID-ORGANISM-4.4.225.mitab.zip) | 4.4.225 |
| `synlethality/` | `BIOGRID-ORGANISM-Mus_musculus-4.4.225.mitab.txt.gz` | BioGRID 4.4.225 Archiv | 4.4.225 |
| `synlethality/` | `BIOGRID-ORGANISM-Saccharomyces_cerevisiae_S288c-4.4.225.mitab.txt.gz` | BioGRID 4.4.225 Archiv | 4.4.225 |
| `orthology/` | `OMA-Pairs_HUMAN-MOUSE_EntrezGene.csv` | [OMA Genome Pair View](https://omabrowser.org/oma/genomePW/) | Download 27.11.2026 |
| `orthology/` | `OMA-Pairs_HUMAN-YEAST_EntrezGene.csv` | OMA Genome Pair View | Download 27.11.2026 |
| `essentiality/` | `G-HumanEssential.tsv` | [SNAP Stanford](https://snap.stanford.edu/biodata/datasets/10033/10033-G-HumanEssential.html) | Download 27.11.2026 |

Die OMA-Paare stammen von der API hinter dem Formular:
`https://omabrowser.org/api/pairs/HUMAN/MOUSE/?format=csv&xrefs=EntrezGene&per_page=200000` (bzw. `HUMAN/YEAST`).

## ID-Wahl: Entrez Gene

Alle drei Quellen lassen sich über **NCBI Entrez Gene IDs** verknüpfen:

- BioGRID tab3: Spalten `Entrez Gene Interactor A/B`
- BioGRID MITAB: `entrez gene/locuslink:<id>` in Spalte 1/2
- SNAP: Spalte `Gene ID`
- OMA: Preferred ID „Entrez Gene IDs“ (`EntrezGene_1`, `EntrezGene_2`)

Abdeckung (geprüft):

| Prüfung | Ergebnis |
|---|---|
| Menschliche SL-Gene mit Essentiality-Eintrag | 1.831 / 1.956 |
| Maus-SL-Gene mit OMA-Ortholog | 46 / 50 |
| Hefe-SL-Gene mit OMA-Ortholog | 1.387 / 3.661 |
| OMA Mensch–Maus-Paare ohne Entrez-ID (Mensch / Maus) | 3.271 / 2.593 von 22.292 |
| OMA Mensch–Hefe-Paare ohne Entrez-ID (Mensch / Hefe) | 238 / 1 von 3.124 |

## Wichtige Beobachtungen

- **Wenig Maus-Daten:** Synthetic-Lethality-Paare in BioGRID 5.0.263: Hefe 17.777, Mensch 2.255, Maus nur 38 (+3 Mensch–Maus).
- **MITAB-Filter:** In Spalte 7 (Detection Method) steht bei allen genetischen Interaktionen `MI:0254 (genetic interference)`. Synthetic Lethality erkennt man nur an Spalte 12: `psi-mi:"MI:2370"(synthetic lethality (sensu biogrid))`.
- **tab3-Spalten:** `Throughput` kann `High Throughput|Low Throughput` enthalten; `Modification` und `Tags` sind immer `-`; `Source Database` ist `BIOGRID` oder `POMBASE`.
- **Ontology Terms** (z. B. `APO:0000112 inviable`, `HP:0001507`) sind mehrwertig, durch `|` getrennt.
- **Essentiality:** 1.511 essentiell, 17.017 nicht essentiell.

## Prüfsummen (SHA-256)

```
5bb68f664fc15cca374c7817e1cf7ab9f29ab51f43c25404fb773320dd76df7d  synlethality/BIOGRID-ORGANISM-Homo_sapiens-4.4.225.mitab.txt.gz
ded6dc079bf0aafbc897a731d8edadc35dca6449f116f49c9453a551027f321e  synlethality/BIOGRID-ORGANISM-Mus_musculus-4.4.225.mitab.txt.gz
657497d7f4478b3f6694812d4b31f01125361938ffea869b68acccab1a4ee478  synlethality/BIOGRID-ORGANISM-Saccharomyces_cerevisiae_S288c-4.4.225.mitab.txt.gz
918805eeaa1c0f6064d645bb87c511930415c7a1883b3b2cfb665d1aad1cf260  synlethality/BIOGRID-SYSTEM-Synthetic_Lethality-5.0.263.tab3.txt.gz
3f9e25014fca39e78a52bfb70c74394500291d8e34738bd7141d95e7689ed291  orthology/OMA-Pairs_HUMAN-MOUSE_EntrezGene.csv
e7fb7579420d3572a8846daf5f105f4d9725b4c3d3e149a35ea380d0212ea9fd  orthology/OMA-Pairs_HUMAN-YEAST_EntrezGene.csv
8cf83aca538a0d8e23978dee9e07d845ae6084c4ab23b26ef6f00327ca31be63  essentiality/G-HumanEssential.tsv
```

## Lizenzen der Daten

- BioGRID: MIT License – bitte Stark C et al., *Nucleic Acids Res.* 2006;34:D535-9 zitieren
- OMA Browser: siehe https://omabrowser.org
- SNAP BioData: siehe https://snap.stanford.edu/biodata/

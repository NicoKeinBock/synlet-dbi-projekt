# ER-Diagramm

Interaktive Version (Whiteboard, zum gemeinsamen Bearbeiten): https://claude.ai/artifact/PZif19EJMd9ke5vmfKWYuL

Die Mermaid-Version unten wird von GitHub direkt als Diagramm angezeigt.

```mermaid
erDiagram
    ORGANISM ||--o{ GENE : "hat"
    ORGANISM ||--o{ OMA_PROTEIN : "hat"
    GENE ||--o{ GENE_SYNONYM : "hat"
    GENE ||--o{ GENE_ACCESSION : "hat"
    GENE ||--o{ INTERACTION : "Gen A"
    GENE ||--o{ INTERACTION : "Gen B"
    GENE |o--o{ OMA_PROTEIN : "kodiert"
    GENE ||--o| ESSENTIALITY : "hat"
    EXPERIMENTAL_SYSTEM ||--o{ INTERACTION : "klassifiziert"
    PUBLICATION ||--o{ INTERACTION : "belegt"
    DATA_SOURCE ||--o{ INTERACTION : "stammt aus"
    INTERACTION ||--o{ INTERACTION_PHENOTYPE : "hat"
    ONTOLOGY_TERM ||--o{ INTERACTION_PHENOTYPE : "beschreibt"
    OMA_PROTEIN ||--o{ ORTHOLOGY : "Protein 1 (Mensch)"
    OMA_PROTEIN ||--o{ ORTHOLOGY : "Protein 2 (Maus/Hefe)"
    ESSENTIALITY ||--o{ ESSENTIALITY_EVIDENCE : "belegt durch"
    PUBLICATION ||--o{ ESSENTIALITY_EVIDENCE : "belegt"

    ORGANISM {
        INTEGER tax_id PK
        VARCHAR scientific_name
        VARCHAR common_name
        VARCHAR oma_code UK
    }
    GENE {
        INTEGER entrez_id PK
        INTEGER tax_id FK
        INTEGER biogrid_id UK
        VARCHAR official_symbol
        VARCHAR systematic_name
    }
    GENE_SYNONYM {
        INTEGER entrez_id PK, FK
        VARCHAR synonym PK
    }
    GENE_ACCESSION {
        INTEGER entrez_id PK, FK
        VARCHAR accession PK
        VARCHAR acc_type
    }
    INTERACTION {
        INTEGER interaction_id PK
        INTEGER gene_a_id FK
        INTEGER gene_b_id FK
        INTEGER system_id FK
        INTEGER pubmed_id FK
        INTEGER source_id FK
        VARCHAR throughput
        DECIMAL score
        TEXT qualifications
        VARCHAR source_database
    }
    EXPERIMENTAL_SYSTEM {
        INTEGER system_id PK
        VARCHAR name
        VARCHAR system_type
        VARCHAR psi_mi_code UK
    }
    PUBLICATION {
        INTEGER pubmed_id PK
        VARCHAR first_author
        INTEGER pub_year
    }
    DATA_SOURCE {
        INTEGER source_id PK
        VARCHAR name
        VARCHAR release
        VARCHAR file_name
        DATE download_date
    }
    ONTOLOGY_TERM {
        VARCHAR term_id PK
        VARCHAR name
        VARCHAR category
    }
    INTERACTION_PHENOTYPE {
        INTEGER interaction_id PK, FK
        VARCHAR term_id PK, FK
    }
    OMA_PROTEIN {
        VARCHAR oma_id PK
        INTEGER tax_id FK
        INTEGER entrez_id FK
    }
    ORTHOLOGY {
        VARCHAR oma_id_1 PK, FK
        VARCHAR oma_id_2 PK, FK
        VARCHAR rel_type
        INTEGER oma_group
    }
    ESSENTIALITY {
        INTEGER entrez_id PK, FK
        BOOLEAN is_essential
    }
    ESSENTIALITY_EVIDENCE {
        INTEGER entrez_id PK, FK
        INTEGER pubmed_id PK, FK
    }
```

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| Entrez Gene ID als PK von `GENE` | Gemeinsamer Schlüssel von BioGRID, OMA und SNAP |
| Zwei FKs `gene_a_id` / `gene_b_id` in `INTERACTION` | Eine Interaktion verbindet immer zwei Gene; beide können aus verschiedenen Organismen stammen (z. B. Mensch–Hefe) |
| `OMA_PROTEIN` als eigene Tabelle | OMA arbeitet auf Protein-Ebene; ca. 15 % der Mensch–Maus-Paare haben keine Entrez-ID, daher ist `entrez_id` optional |
| `oma_id_1` = immer Mensch | So exportiert OMA die Paare (Species 1 = Homo sapiens) |
| `GENE_SYNONYM`, `GENE_ACCESSION`, `INTERACTION_PHENOTYPE` | Mehrwertige, durch `\|` getrennte Felder in BioGRID → 1. Normalform |
| `ESSENTIALITY` getrennt von `GENE` | Nur für menschliche Gene vorhanden (1 : 0..1) |
| `DATA_SOURCE` | Unterscheidet BioGRID 5.0.263 (tab3) und 4.4.225 (MITAB) |

## Offene Fragen an die Auftraggeberin

| Frage | Unser Vorschlag |
|---|---|
| Nur Synthetic Lethality oder alle genetischen Interaktionen aus MITAB? | Nur Synthetic Lethality (`MI:2370`) |
| Speichern wir Patient:innen und die Mutation von Gen X? | Nein, Gen X ist nur Abfrage-Parameter |
| Welches DBMS? | PostgreSQL (bei Oracle: `BOOLEAN` → `NUMBER(1)`) |
| Nur 1:1-Orthologe oder alle Typen? | Alle, `rel_type` dient als Filter |

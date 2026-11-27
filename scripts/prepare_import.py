"""Bereitet die Rohdaten aus data/ für den Import in die SynLet-Datenbank auf.

Liest die BioGRID-, OMA- und SNAP-Dateien (die .gz-Dateien direkt, ohne Entpacken),
normalisiert mehrwertige Felder und schreibt pro Tabelle eine CSV nach build/.
Danach lädt sql/import.sql diese CSVs mit \\copy in PostgreSQL.

Aufruf aus dem Repo-Ordner (nur Python-Standardbibliothek, Python >= 3.8):
    python3 scripts/prepare_import.py
"""
import csv
import gzip
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "build"

HUMAN, MOUSE, YEAST = 9606, 10090, 559292
ORGANISMS = {HUMAN, MOUSE, YEAST}
OMA_PREFIX = {"HUMAN": HUMAN, "MOUSE": MOUSE, "YEAST": YEAST}
SL_PSI_MI = "MI:2370"
DOWNLOAD_DATE = "2026-11-27"

TAB3 = "BIOGRID-SYSTEM-Synthetic_Lethality-5.0.263.tab3.txt.gz"
MITAB = {
    2: ("BIOGRID-ORGANISM-Homo_sapiens-4.4.225.mitab.txt.gz", HUMAN),
    3: ("BIOGRID-ORGANISM-Mus_musculus-4.4.225.mitab.txt.gz", MOUSE),
    4: ("BIOGRID-ORGANISM-Saccharomyces_cerevisiae_S288c-4.4.225.mitab.txt.gz", YEAST),
}
OMA_FILES = {
    5: "OMA-Pairs_HUMAN-MOUSE_EntrezGene.csv",
    6: "OMA-Pairs_HUMAN-YEAST_EntrezGene.csv",
}
ESS_FILE = "G-HumanEssential.tsv"

DATA_SOURCES = [
    (1, "BioGRID", "5.0.263", TAB3[:-3]),
    (2, "BioGRID", "4.4.225", MITAB[2][0][:-3]),
    (3, "BioGRID", "4.4.225", MITAB[3][0][:-3]),
    (4, "BioGRID", "4.4.225", MITAB[4][0][:-3]),
    (5, "OMA", DOWNLOAD_DATE, OMA_FILES[5]),
    (6, "OMA", DOWNLOAD_DATE, OMA_FILES[6]),
    (7, "SNAP BioData", DOWNLOAD_DATE, ESS_FILE),
]

AUTHOR_RE = re.compile(r"^(.*?)\s*\((\d{4})[a-z]?\)$")
MITAB_ACC = {"uniprot/swiss-prot": "SWISS-PROT", "uniprot/trembl": "TREMBL", "refseq": "REFSEQ"}

# ---------------------------------------------------------------- Sammelstrukturen
genes = {}          # entrez_id -> {"tax", "biogrid", "symbol", "systematic"}
synonyms = set()    # (entrez_id, synonym)
accessions = {}     # (entrez_id, accession) -> acc_type
systems = {}        # name -> (system_id, system_type, psi_mi_code)
publications = {}   # pubmed_id -> (first_author, pub_year)
interactions = {}   # interaction_id -> Zeile
terms = {}          # term_id -> (name, category)
phenotypes = set()  # (interaction_id, term_id)
oma_proteins = {}   # oma_id -> (tax_id, entrez_id)
orthology = {}      # (oma_id_1, oma_id_2) -> (rel_type, oma_group)
essentiality = {}   # entrez_id -> bool
evidence = set()    # (entrez_id, pubmed_id)
warnings = []


def val(x):
    """BioGRID schreibt '-' für fehlende Werte."""
    x = (x or "").strip()
    return None if x in ("", "-") else x


def split(x):
    x = val(x)
    return [] if x is None else [p for p in x.split("|") if p and p != "-"]


def add_gene(entrez, tax, biogrid=None, symbol=None, systematic=None):
    """Legt ein Gen an oder ergänzt fehlende Felder (frühere Quelle gewinnt)."""
    entrez, tax = int(entrez), int(tax)
    g = genes.get(entrez)
    if g is None:
        genes[entrez] = {"tax": tax, "biogrid": biogrid, "symbol": symbol, "systematic": systematic}
        return
    if g["tax"] != tax:
        warnings.append(f"Gen {entrez}: Organismus {g['tax']} vs. {tax}, behalte {g['tax']}")
    for key, v in (("biogrid", biogrid), ("symbol", symbol), ("systematic", systematic)):
        if g[key] is None and v is not None:
            g[key] = v


def add_publication(pmid, author=None, year=None):
    pmid = int(pmid)
    old = publications.get(pmid)
    if old is None or (old[0] is None and author is not None):
        publications[pmid] = (author, year)
    return pmid


def parse_author(text):
    text = val(text)
    if text is None:
        return None, None
    text = text.strip('"')
    m = AUTHOR_RE.match(text)
    return (m.group(1), int(m.group(2))) if m else (text, None)


def system_id(name, system_type, psi=None):
    if name not in systems:
        systems[name] = (len(systems) + 1, system_type, psi)
    elif psi and systems[name][2] is None:
        sid, st, _ = systems[name]
        systems[name] = (sid, st, psi)
    return systems[name][0]


# ---------------------------------------------------------------- BioGRID tab3 (5.0.263)
def read_tab3():
    path = DATA / "synlethality" / TAB3
    skipped = 0
    with gzip.open(path, "rt", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
        next(reader)
        for c in reader:
            tax_a, tax_b = int(c[15]), int(c[16])
            if tax_a not in ORGANISMS or tax_b not in ORGANISMS:
                skipped += 1
                continue
            for i, tax in ((0, tax_a), (1, tax_b)):
                entrez = int(c[1 + i])
                add_gene(entrez, tax, int(c[3 + i]), val(c[7 + i]), val(c[5 + i]))
                for s in split(c[9 + i]):
                    synonyms.add((entrez, s))
                for col, acc_type in ((23 + 3 * i, "SWISS-PROT"), (24 + 3 * i, "TREMBL"), (25 + 3 * i, "REFSEQ")):
                    for acc in split(c[col]):
                        accessions.setdefault((entrez, acc), acc_type)

            sid = system_id(c[11], c[12], SL_PSI_MI if c[11] == "Synthetic Lethality" else None)
            pmid = None
            src = val(c[14])
            if src and src.upper().startswith("PUBMED:"):
                author, year = parse_author(c[13])
                pmid = add_publication(src.split(":", 1)[1], author, year)
            iid = int(c[0])
            interactions[iid] = {
                "interaction_id": iid, "gene_a_id": int(c[1]), "gene_b_id": int(c[2]),
                "system_id": sid, "pubmed_id": pmid, "source_id": 1,
                "throughput": val(c[17]), "score": val(c[18]),
                "qualifications": val(c[20]), "source_database": val(c[22]),
            }
            ids, names, cats = split(c[29]), split(c[30]), split(c[31])
            for k, term in enumerate(ids):
                name = names[k] if k < len(names) else term
                cat = cats[k] if k < len(cats) else None
                terms.setdefault(term, (name, cat))
                phenotypes.add((iid, term))
    print(f"tab3: {len(interactions)} SL-Interaktionen übernommen, {skipped} anderer Organismen übersprungen")


# ---------------------------------------------------------------- BioGRID MITAB (4.4.225)
def mitab_entrez(field):
    v = val(field)
    if v and v.startswith("entrez gene/locuslink:"):
        tail = v.split(":", 1)[1]
        return int(tail) if tail.isdigit() else None
    return None


def mitab_alt_ids(field):
    """biogrid-ID, offizielles Symbol und Accessions aus der Alt-IDs-Spalte."""
    biogrid = symbol = None
    accs = []
    for part in split(field):
        db, _, ident = part.partition(":")
        if db == "biogrid" and ident.isdigit():
            biogrid = int(ident)
        elif db == "entrez gene/locuslink" and symbol is None:
            symbol = ident
        elif db in MITAB_ACC:
            accs.append((ident, MITAB_ACC[db]))
    return biogrid, symbol, accs


def read_mitab(source_id, filename):
    path = DATA / "synlethality" / filename
    new_sl = rows = 0
    with gzip.open(path, "rt", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
        next(reader)
        for c in reader:
            rows += 1
            taxes = []
            for i in (0, 1):
                tax = val(c[9 + i])
                taxes.append(int(tax.split(":", 1)[1]) if tax and tax.startswith("taxid:") else None)
            entrez = [mitab_entrez(c[0]), mitab_entrez(c[1])]
            # Geninfos aller Interaktoren unserer Organismen (liefert Symbole für Orthologe)
            for i in (0, 1):
                if entrez[i] is None or taxes[i] not in ORGANISMS:
                    continue
                biogrid, symbol, accs = mitab_alt_ids(c[2 + i])
                add_gene(entrez[i], taxes[i], biogrid, symbol)
                for acc, acc_type in accs:
                    accessions.setdefault((entrez[i], acc), acc_type)

            if SL_PSI_MI not in c[11] or None in entrez or not all(t in ORGANISMS for t in taxes):
                continue
            iid_field = val(c[13]) or ""
            if not iid_field.startswith("biogrid:"):
                continue
            iid = int(iid_field.split(":", 1)[1])
            if iid in interactions:          # tab3 (neuer, vollständiger) hat Vorrang
                continue
            pmid = None
            for pub in split(c[8]):
                if pub.startswith("pubmed:") and pub[7:].isdigit():
                    author, year = parse_author(c[7])
                    pmid = add_publication(pub[7:], author, year)
                    break
            score = None
            conf = val(c[14])
            if conf and conf.startswith("score:"):
                score = conf[6:]
            interactions[iid] = {
                "interaction_id": iid, "gene_a_id": entrez[0], "gene_b_id": entrez[1],
                "system_id": system_id("Synthetic Lethality", "genetic", SL_PSI_MI),
                "pubmed_id": pmid, "source_id": source_id, "throughput": None,
                "score": score, "qualifications": None, "source_database": "BIOGRID",
            }
            new_sl += 1
    print(f"MITAB {filename}: {rows} Zeilen gelesen, {new_sl} zusätzliche SL-Interaktionen")


# ---------------------------------------------------------------- OMA
def read_oma(filename):
    path = DATA / "orthology" / filename
    n = 0
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            for side in ("1", "2"):
                oma_id = r[f"OMAid_{side}"].strip()
                tax = OMA_PREFIX[oma_id[:5]]
                ez = r[f"EntrezGene_{side}"].strip()
                entrez = int(ez) if ez else None
                if entrez is not None:
                    add_gene(entrez, tax)
                old = oma_proteins.get(oma_id)
                if old is None or old[1] is None:
                    oma_proteins[oma_id] = (tax, entrez)
            group = r["OmaGroup"].strip()
            orthology[(r["OMAid_1"].strip(), r["OMAid_2"].strip())] = (
                r["RelType"].strip(), int(group) if group else None)
            n += 1
    print(f"OMA {filename}: {n} Orthologie-Paare")


# ---------------------------------------------------------------- SNAP Essentiality
def read_essentiality():
    path = DATA / "essentiality" / ESS_FILE
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        next(reader)
        for c in reader:
            if not c or not c[0].strip().isdigit():
                continue
            entrez = int(c[0])
            add_gene(entrez, HUMAN)
            essentiality[entrez] = c[1].strip().lower() == "essential"
            for src in c[2].split(","):
                src = src.strip()
                if src.upper().startswith("PMID:") and src[5:].isdigit():
                    evidence.add((entrez, add_publication(src[5:])))
    print(f"SNAP: {len(essentiality)} Gene, davon {sum(essentiality.values())} essentiell")


# ---------------------------------------------------------------- CSV-Ausgabe
def write(name, header, rows):
    OUT.mkdir(exist_ok=True)
    with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        count = 0
        for row in rows:
            w.writerow(["" if v is None else v for v in row])
            count += 1
    print(f"  build/{name}.csv: {count} Zeilen")


def main():
    read_tab3()
    for sid, (filename, _) in MITAB.items():
        read_mitab(sid, filename)
    for filename in OMA_FILES.values():
        read_oma(filename)
    read_essentiality()

    print("Schreibe CSVs:")
    write("data_source", ["source_id", "name", "release", "file_name", "download_date"],
          ((sid, n, rel, fn, DOWNLOAD_DATE) for sid, n, rel, fn in DATA_SOURCES))
    write("gene", ["entrez_id", "tax_id", "biogrid_id", "official_symbol", "systematic_name"],
          ((e, g["tax"], g["biogrid"], g["symbol"], g["systematic"]) for e, g in sorted(genes.items())))
    write("gene_synonym", ["entrez_id", "synonym"], sorted(synonyms))
    write("gene_accession", ["entrez_id", "accession", "acc_type"],
          ((e, a, t) for (e, a), t in sorted(accessions.items())))
    write("experimental_system", ["system_id", "name", "system_type", "psi_mi_code"],
          ((sid, name, st, psi) for name, (sid, st, psi) in sorted(systems.items(), key=lambda x: x[1][0])))
    write("publication", ["pubmed_id", "first_author", "pub_year"],
          ((p, a, y) for p, (a, y) in sorted(publications.items())))
    cols = ["interaction_id", "gene_a_id", "gene_b_id", "system_id", "pubmed_id", "source_id",
            "throughput", "score", "qualifications", "source_database"]
    write("interaction", cols, ([r[k] for k in cols] for _, r in sorted(interactions.items())))
    write("ontology_term", ["term_id", "name", "category"],
          ((t, n, c) for t, (n, c) in sorted(terms.items())))
    write("interaction_phenotype", ["interaction_id", "term_id"], sorted(phenotypes))
    write("oma_protein", ["oma_id", "tax_id", "entrez_id"],
          ((o, t, e) for o, (t, e) in sorted(oma_proteins.items())))
    write("orthology", ["oma_id_1", "oma_id_2", "rel_type", "oma_group"],
          ((a, b, r, g) for (a, b), (r, g) in sorted(orthology.items())))
    write("essentiality", ["entrez_id", "is_essential"],
          ((e, "true" if v else "false") for e, v in sorted(essentiality.items())))
    write("essentiality_evidence", ["entrez_id", "pubmed_id"], sorted(evidence))

    if warnings:
        print(f"{len(warnings)} Warnungen, z. B.:", *warnings[:5], sep="\n  ")
    return 0


if __name__ == "__main__":
    sys.exit(main())

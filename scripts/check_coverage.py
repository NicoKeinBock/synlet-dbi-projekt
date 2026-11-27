"""Prüft, wie gut sich die Datensätze über Entrez Gene IDs verknüpfen lassen.

Aufruf (aus dem Repo-Ordner):
    python3 scripts/check_coverage.py
Die .gz-Dateien werden direkt gelesen, Entpacken ist nicht nötig.
"""
import collections
import csv
import gzip
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
SL = DATA / "synlethality" / "BIOGRID-SYSTEM-Synthetic_Lethality-5.0.263.tab3.txt.gz"
ESS = DATA / "essentiality" / "G-HumanEssential.tsv"
OMA = {
    "10090": ("Maus", DATA / "orthology" / "OMA-Pairs_HUMAN-MOUSE_EntrezGene.csv"),
    "559292": ("Hefe", DATA / "orthology" / "OMA-Pairs_HUMAN-YEAST_EntrezGene.csv"),
}


def main():
    with open(ESS, newline="") as f:
        essential = {r["Gene ID"] for r in csv.DictReader(f, delimiter="\t")}

    genes = collections.defaultdict(set)
    pairs = collections.Counter()
    with gzip.open(SL, "rt", newline="") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            org_a, org_b = r["Organism ID Interactor A"], r["Organism ID Interactor B"]
            pairs[(org_a, org_b)] += 1
            genes[org_a].add(r["Entrez Gene Interactor A"])
            genes[org_b].add(r["Entrez Gene Interactor B"])

    print("SL-Paare nach Organismus (A, B):")
    for (a, b), n in pairs.most_common(10):
        print(f"  {a:>7} {b:>7}  {n}")

    human = genes["9606"]
    print(f"\nMenschliche SL-Gene mit Essentiality-Eintrag: {len(human & essential)} / {len(human)}")

    for tax, (name, path) in OMA.items():
        with open(path, newline="") as f:
            rows = list(csv.DictReader(f))
        orth = {r["EntrezGene_2"] for r in rows if r["EntrezGene_2"]}
        print(f"{name}-SL-Gene mit OMA-Ortholog: {len(genes[tax] & orth)} / {len(genes[tax])}"
              f"  (OMA-Paare: {len(rows)})")


if __name__ == "__main__":
    main()

"""Judge nets on seeds no training run uses (900 and up), across the farm.

    python harness/holdout.py fixtures/bot0.net out/farm/evolve/champion.net --seeds 8

Every net plays every map on every seed, as all four bots on Nightmare, frozen.
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "harness"))
import evolve  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("nets", nargs="+", type=Path)
    ap.add_argument("--maps", default="2,3,4,9")
    ap.add_argument("--seeds", type=int, default=8)
    a = ap.parse_args()
    maps = [int(m) for m in a.maps.split(",")]
    seeds = [900 + k for k in range(a.seeds)]
    nets = {"n{}".format(i): p.read_bytes() for i, p in enumerate(a.nets)}
    rows = evolve.play(nets, maps, seeds, 0)
    for i, p in enumerate(a.nets):
        rs = rows.get("n{}".format(i), [])
        print("{:<40} games {:>3}  finished {:>3}  score {:>6}  deaths {:>5.1f}".format(str(p), len(rs), sum(bool(r["finished"]) for r in rs), sum(evolve.score(r) for r in rs), sum(int(r["deaths"]) for r in rs) / max(len(rs), 1)))
        for m in maps:
            mr = [r for r in rs if r["map"] == m]
            print("    E1M{}  finished {}/{}".format(m, sum(bool(r["finished"]) for r in mr), len(mr)))


if __name__ == "__main__":
    main()

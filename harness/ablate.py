"""Which net outputs change the game: play the same Nightmare levels with each
output silenced in turn and compare against the net playing in full.

    python harness/ablate.py --net fixtures/bot0.net --maps 2,4,9 --seeds 0,1,2,3

Each game is a coopmatch with COOP_ABLATE set (see root.mach); games run in
parallel. An output whose silencing changes nothing is one the controller
overrides, and training it cannot help; one whose silencing costs levels or
lives is one worth training.
"""
import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "harness"))
import pathbench  # noqa: E402
OUTPUTS = [("full", 0), ("forward", 1), ("side", 2), ("turn", 4), ("fire", 8), ("use", 16), ("switch", 32), ("all moving", 7), ("dodge", 64)]


def play(exe, net, m, seed, mask, tics):
    env = dict(os.environ)
    env["COOP_ABLATE"] = str(mask)
    r = subprocess.run([str(exe), "coopmatch", str(ROOT / "data/DOOM1.WAD"), str(m), str(tics), str(net), str(seed)],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="replace", env=env, timeout=900)
    row = pathbench.parse(r.stdout)
    return {"finished": bool(row["finished"]), "nearest": int(row["nearest"]), "deaths": int(row["deaths"]), "tics": int(row["tics"])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", type=Path, default=ROOT / "out/windows-x86_64/release/bin/doom.exe")
    ap.add_argument("--net", type=Path, default=ROOT / "fixtures/bot0.net")
    ap.add_argument("--maps", default="2,4,9")
    ap.add_argument("--seeds", default="0,1,2,3")
    ap.add_argument("--tics", type=int, default=16800)
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--report", type=Path)
    ap.add_argument("--only", default=None, help="comma-separated names from the table, e.g. full,dodge")
    a = ap.parse_args()
    global OUTPUTS
    if a.only:
        OUTPUTS = [o for o in OUTPUTS if o[0] in a.only.split(",")]
    maps = [int(x) for x in a.maps.split(",")]
    seeds = [int(x) for x in a.seeds.split(",")]
    work = [(name, mask, m, s) for name, mask in OUTPUTS for m in maps for s in seeds]
    rows = []
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as pool:
        futs = {pool.submit(play, a.exe, a.net, m, s, mask, a.tics): (name, mask, m, s) for name, mask, m, s in work}
        for f in concurrent.futures.as_completed(futs):
            name, mask, m, s = futs[f]
            rows.append(dict(f.result(), silenced=name, map=m, seed=s))
    if a.report:
        a.report.write_text(json.dumps(rows, indent=1))
    n = len(maps) * len(seeds)
    print("{:<11} {:>8} {:>8} {:>8}".format("silenced", "finished", "nearest", "deaths"))
    for name, _ in OUTPUTS:
        rs = [r for r in rows if r["silenced"] == name]
        print("{:<11} {:>5}/{:<2} {:>8.1f} {:>8.1f}".format(name, sum(r["finished"] for r in rs), n, sum(r["nearest"] for r in rs) / n, sum(r["deaths"] for r in rs) / n))


if __name__ == "__main__":
    main()

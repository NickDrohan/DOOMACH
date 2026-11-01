"""Where the evolution run stands, in one look.

    python harness/evolve-status.py

The last generations (champion's and best mutant's levels finished, whether a
mutant took over and its confirmation), every validation against the anchor,
how many games each machine was given and returned lately, and whether the
run and the champion are what they should be.
"""
import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out/farm/evolve"


def lines(name):
    p = OUT / name
    return [json.loads(l) for l in p.read_text().splitlines() if l.strip().startswith("{")] if p.exists() else []


def main():
    run = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "(Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -match 'evolve.py' }).ProcessId"],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, encoding="utf-8").stdout.split()
    print("run:", "running, pid " + ", ".join(run) if run else "NOT RUNNING")
    for name in ("champion.net", "anchor.net"):
        p = OUT / name
        if p.exists():
            print("{}: {} ({} bytes, {:.0f} min old)".format(name, hashlib.sha256(p.read_bytes()).hexdigest()[:12], p.stat().st_size, (time.time() - p.stat().st_mtime) / 60))
    gens = lines("log.jsonl")[-12:]
    print("\nlast generations (levels finished: champion / best mutant; * took over):")
    print("  " + "  ".join("{}:{}/{}{}".format(g["gen"], g["champion"][1], g["best_score"][1], "*" if g["took"] else "") for g in gens))
    for v in lines("validate.jsonl")[-6:]:
        print("validate at {}: champion {} anchor {} levels -> {}".format(v["validate"], v["finished"][0], v["finished"][1], "kept" if v["kept"] else "REVERTED to anchor"))
    recent = lines("machines.jsonl")[-10:]
    if recent:
        print("\ngames given / returned over the last {} plays:".format(len(recent)))
        tot = {}
        for r in recent:
            for m, (given, got) in r["games"].items():
                t = tot.setdefault(m, [0, 0])
                t[0] += given
                t[1] += got
        for m, (given, got) in tot.items():
            print("  {:<7} {:>5} / {:<5} {}".format(m, given, got, "" if got == given else "<- {} lost".format(given - got)))
        late = [r for r in recent if r["stillwaiting"]]
        if late:
            print("  timed out waiting on:", sorted({m for r in late for m in r["stillwaiting"]}))


if __name__ == "__main__":
    main()

"""Collect and consolidate co-op cohort training from the home farm.

    python harness/farm-collect.py collect          # fetch every run's coop.bin / coop.json
    python harness/farm-collect.py summary          # what each run has done so far
    python harness/farm-collect.py consolidate      # benchmark every run's learners, keep the best four

Runs live on the farm in ~/work/doomach/runN (started by harness/farm-train.sh).
Fetched copies go to out/farm/results/<machine>/runN/. `consolidate` plays each
candidate net as all four bots on the same seeded Nightmare levels and writes
out/farm/consolidated/coop.bin: the seed league with the four best nets in the
cohort's places. Nothing is installed anywhere; publishing is a separate step.
"""
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FARM = Path.home() / ".claude/skills/farm-machines/farm.sh"
RESULTS = ROOT / "out/farm/results"
SEED = ROOT / "out/farm/seed/coop.bin"
OUT = ROOT / "out/farm/consolidated"
MACHINES = {"pi-01": 3, "pi-02": 3, "mac": 5}
COHORT = [5, 23, 41, 64]
HEAD, MEMBER, AT_NET, NET = 16, 1932, 48, 942
BASH = r"C:\Program Files\Git\bin\bash.exe"


def farm(*args):
    return subprocess.run([BASH, str(FARM).replace("\\", "/"), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", timeout=300)


def collect():
    for machine, runs in MACHINES.items():
        for i in range(1, runs + 1):
            here = RESULTS / machine / "run{}".format(i)
            here.mkdir(parents=True, exist_ok=True)
            for name in ("coop.bin", "coop.json"):
                got = farm("get", machine, "work/doomach/run{}/{}".format(i, name), str(here / name).replace("\\", "/"))
                print(machine, "run{}".format(i), name, "ok" if got.returncode == 0 else "missing")


def runs():
    for path in sorted(RESULTS.glob("*/run*/coop.bin")):
        data = path.read_bytes()
        if len(data) == HEAD + 100 * MEMBER and data[:4] == b"MDL1":
            yield path.parent, data


def summary():
    for where, data in runs():
        board = json.loads((where / "coop.json").read_text(encoding="utf-8")) if (where / "coop.json").exists() else {}
        active = [b for b in board.get("bots", []) if b.get("active")]
        print("{}: {} campaigns, {} levels finished; {}".format(
            where.relative_to(RESULTS), board.get("matches"), board.get("finished"),
            ", ".join("{} gen {} rating {}".format(b["name"], b["generation"], b["rating"]) for b in active)))


def net_of(data, who):
    at = HEAD + who * MEMBER + AT_NET
    return data[at:at + NET]


def score(exe, net, maps=(1, 2, 3, 4, 5, 7, 9), seeds=(0, 1)):
    tmp = ROOT / "out/farm/candidate.net"
    tmp.write_bytes(net)
    finished, nearest = 0, 0
    for m in maps:
        for seed in seeds:
            run = subprocess.run([str(exe), "coopmatch", str(ROOT / "data/DOOM1.WAD"), str(m), "16800", str(tmp), str(seed)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", timeout=600)
            finished += " finished 1 " in run.stdout
            near = [int(n) for n in re.findall(r"nearest (\d+)", run.stdout)]
            nearest += min([n for n in near if n > 0] or [200])
    # finishing first; then how close to the exits it got
    return finished * 10000 - nearest


def consolidate():
    exe = ROOT / "out/windows-x86_64/release/bin/doom.exe"
    seed = SEED.read_bytes()
    candidates = [("seed", who, net_of(seed, who)) for who in COHORT]
    for where, data in runs():
        candidates += [(str(where.relative_to(RESULTS)), who, net_of(data, who)) for who in COHORT]
    scored = []
    for origin, who, net in candidates:
        s = score(exe, net)
        scored.append((s, origin, who, net))
        print("{:>8} {} member {}".format(s, origin, who), flush=True)
    scored.sort(key=lambda r: -r[0])
    best = bytearray(seed)
    for slot, (s, origin, who, net) in zip(COHORT, scored[:4]):
        at = HEAD + slot * MEMBER + AT_NET
        best[at:at + NET] = net
        print("slot {} <- {} member {} ({})".format(slot, origin, who, s))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "coop.bin").write_bytes(bytes(best))
    print("wrote", OUT / "coop.bin")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "collect":
        collect()
    elif command == "summary":
        summary()
    elif command == "consolidate":
        consolidate()
    else:
        raise SystemExit(__doc__)

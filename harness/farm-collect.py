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
MACHINES = {"pi-01": 4, "pi-02": 4, "mac": 6, "laptop": 8}
# the Windows laptop is not in the farm helper: plain scp, as nick, with the
# farm key, into C:/Users/nick/work/doomach (harness/farm-train.cmd)
LAPTOP = "nick@192.168.1.233"
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
                if machine == "laptop":
                    got = subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", str(Path.home() / ".ssh/machete_farm"),
                                          "{}:C:/Users/nick/work/doomach/run{}/{}".format(LAPTOP, i, name), str(here / name)],
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
                else:
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


# ---- a consolidation cycle, benchmarked on the laptop rather than this PC
#   prepare      every run's four learners and the seed's, as nets, to the laptop; start
#                harness/farm-eval.ps1 there
#   score        fetch its games, rank the candidates, write out/farm/consolidated/coop.bin
#   redistribute that file becomes every machine's seed; each run is kept as
#                gen<k>-runN and training restarts from the consolidated cohort
KIT = ROOT / "out/farm/evalkit"
SSHKEY = str(Path.home() / ".ssh/machete_farm")
REMOTE_KIT = "C:/Users/nick/work/doomeval"


def laptop(command):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", SSHKEY, LAPTOP, command],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", timeout=600)


def scp(*args):
    return subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", SSHKEY, *args],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900)


def launch_on_laptop(command_line, cwd, priority=32):
    ps = ("$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{{PriorityClass = [uint32]{}; ShowWindow = [uint16]0}}; "
          "$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{{CommandLine = '{}'; CurrentDirectory = '{}'; ProcessStartupInformation = $si}}; $r.ReturnValue").format(priority, command_line, cwd)
    import base64
    return laptop("powershell -NoProfile -EncodedCommand " + base64.b64encode(ps.encode("utf-16-le")).decode())


def prepare():
    cand = KIT / "candidates"
    cand.mkdir(parents=True, exist_ok=True)
    for old in cand.glob("*.net"):
        old.unlink()
    seed = SEED.read_bytes()
    for who in COHORT:
        (cand / "seed_m{}.net".format(who)).write_bytes(net_of(seed, who))
    for where, data in runs():
        tag = str(where.relative_to(RESULTS)).replace("\\", "_").replace("/", "_")
        for who in COHORT:
            (cand / "{}_m{}.net".format(tag, who)).write_bytes(net_of(data, who))
    laptop("if exist C:\\Users\\nick\\work\\doomeval\\games rmdir /s /q C:\\Users\\nick\\work\\doomeval\\games")
    laptop("if exist C:\\Users\\nick\\work\\doomeval\\candidates rmdir /s /q C:\\Users\\nick\\work\\doomeval\\candidates")
    laptop("if not exist C:\\Users\\nick\\work\\doomeval mkdir C:\\Users\\nick\\work\\doomeval")
    for local, remote in [(ROOT / "out/windows-x86_64/release/bin/doom.exe", "doom.exe"), (ROOT / "data/DOOM1.WAD", "DOOM1.WAD"),
                          (ROOT / "harness/farm-eval.ps1", "farm-eval.ps1")]:
        scp(str(local), "{}:{}/{}".format(LAPTOP, REMOTE_KIT, remote))
    scp("-r", str(cand), "{}:{}/".format(LAPTOP, REMOTE_KIT))
    got = launch_on_laptop("powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\nick\\work\\doomeval\\farm-eval.ps1 -Parallel 6",
                           "C:\\Users\\nick\\work\\doomeval")
    print(len(list(cand.glob("*.net"))), "candidates sent; evaluator started:", got.stdout.strip()[-20:])


def score_games():
    games = KIT / "games"
    if games.exists():
        for old in games.glob("*"):
            old.unlink()
    scp("-r", "{}:{}/games".format(LAPTOP, REMOTE_KIT), str(KIT))
    done = (games / "DONE").exists()
    table = {}
    for g in games.glob("*.txt"):
        name = g.stem.rsplit("_", 2)[0]
        text = g.read_text(encoding="utf-8", errors="replace")
        fin = " finished 1 " in text
        near = [int(n) for n in re.findall(r"nearest (\d+)", text) if int(n) > 0]
        row = table.setdefault(name, [0, 0, 0])
        row[0] += fin
        row[1] += min(near or [200])
        row[2] += 1
    return table, done


def score():
    table, done = score_games()
    full = max((r[2] for r in table.values()), default=0)
    ranked = sorted(((r[0] * 10000 - r[1], n, r) for n, r in table.items() if r[2] == full), reverse=True)
    print("evaluator", "done" if done else "still running", "-", len(table), "candidates,", full, "games each")
    for s, n, r in ranked[:12]:
        print("{:>7} {:<22} finished {} nearest-sum {}".format(s, n, r[0], r[1]))
    seedrows = [x for x in ranked if x[1].startswith("seed_")]
    if seedrows:
        print("seed learners:", ", ".join("{} {}".format(n, s) for s, n, r in seedrows))
    if not done:
        return
    seed = SEED.read_bytes()
    best = bytearray(seed)
    cand = KIT / "candidates"
    for slot, (s, n, r) in zip(COHORT, ranked[:4]):
        at = HEAD + slot * MEMBER + AT_NET
        best[at:at + NET] = (cand / (n + ".net")).read_bytes()
        print("slot {} <- {} ({})".format(slot, n, s))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "coop.bin").write_bytes(bytes(best))
    print("wrote", OUT / "coop.bin")


def redistribute(gen):
    new = (OUT / "coop.bin").read_bytes()
    (SEED.parent / "coop.gen{}.bin".format(gen)).write_bytes(SEED.read_bytes())
    SEED.write_bytes(new)
    bases = {"pi-01": 10000 * gen + 1000, "pi-02": 10000 * gen + 2000, "mac": 10000 * gen + 3000}
    for machine, n in MACHINES.items():
        if machine == "laptop":
            laptop("powershell -NoProfile -Command \"Stop-Process -Name arena -Force -ErrorAction SilentlyContinue\"")
            scp(str(SEED), "{}:C:/Users/nick/work/doomach/seed/coop.bin".format(LAPTOP))
            for i in range(1, n + 1):
                laptop("cd /d C:\\Users\\nick\\work\\doomach && if exist run{0} move run{0} gen{1}-run{0}".format(i, gen))
                launch_on_laptop("cmd.exe /c C:\\Users\\nick\\work\\doomach\\farm-train.cmd {} {}".format(i, 10000 * gen + 4001 + 2 * i),
                                 "C:\\Users\\nick\\work\\doomach", priority=16384)
        else:
            farm("stop", machine, "farm-train.sh")
            farm("stop", machine, "arena")
            farm("put", machine, str(SEED).replace("\\", "/"), "work/doomach/seed/coop.bin")
            farm("run", machine, "cd work/doomach && for d in run*; do mv $d gen{}-$d; done".format(gen))
            farm("start", machine, "work/doomach/launcher.log", "cd work/doomach && ./farm-train.sh {} {}".format(n, bases[machine]))
        print(machine, "restarted from the consolidated cohort")
    for old in RESULTS.glob("*/run*"):
        old.rename(old.parent / "gen{}-{}".format(gen, old.name))


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "prepare":
        prepare()
        sys.exit(0)
    if command == "score":
        score()
        sys.exit(0)
    if command == "redistribute":
        redistribute(int(sys.argv[2]))
        sys.exit(0)
    if command == "collect":
        collect()
    elif command == "summary":
        summary()
    elif command == "consolidate":
        consolidate()
    else:
        raise SystemExit(__doc__)

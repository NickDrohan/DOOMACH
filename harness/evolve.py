"""Evolve one co-op net on the laptop: the layers that matter, judged by levels.

    python harness/evolve.py --net fixtures/bot0.net --gens 40

Each generation the champion and POP mutants of it play every map of MAPS on
that generation's seeds (two fresh ones a generation, so nothing is learned
of one seed), as all four bots, frozen, on Nightmare, through
harness/farm-eval.ps1 on the laptop. A mutant takes over only if it beats the
champion on the very same games by MARGIN. Only the weights named by --layers
are mutated:

    out     the hidden-to-output weights of the outputs in --outputs
    hidden  the input-to-hidden weights and biases
    all     both

Score per game: 1000 for finishing (and up to 168 more for finishing fast),
two a step of the closest approach to the exit (200 steps is none), less three
a death. The champion, its score history and every generation's table go to
out/farm/evolve/. Run it detached; it picks up from champion.net if stopped.
"""
import argparse
import base64
import json
import random
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "harness"))
import pathbench  # noqa: E402

INPUTS, HIDDEN, OUTPUTS = 32, 24, 6
W2 = INPUTS * HIDDEN + HIDDEN
NET = W2 + HIDDEN * OUTPUTS + OUTPUTS
LAPTOP = "nick@192.168.1.233"
KEY = str(Path.home() / ".ssh/machete_farm")
REMOTE = "C:/Users/nick/work/doomevolve"
REMOTE_W = REMOTE.replace("/", "\\")
OUT = ROOT / "out/farm/evolve"
OUTPUT_BITS = {"forward": 0, "side": 1, "turn": 2, "fire": 3, "use": 4, "switch": 5}


def ssh(command, timeout=900):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", KEY, LAPTOP, command],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="replace", timeout=timeout)


def scp(*args):
    return subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", KEY, *args],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900)


def ps(script):
    return ssh("powershell -NoProfile -EncodedCommand " + base64.b64encode(script.encode("utf-16-le")).decode())


def mutable(layers, outputs):
    at = []
    if layers in ("hidden", "all"):
        at += range(W2)
    if layers in ("out", "all"):
        for k in outputs:
            at += range(W2 + k * HIDDEN, W2 + (k + 1) * HIDDEN)
            at.append(W2 + HIDDEN * OUTPUTS + k)
    return at


def mutate(net, at, rng, rate, sigma):
    out = bytearray(net)
    for i in at:
        if rng.random() < rate:
            v = int.from_bytes(out[i:i + 1], "little", signed=True) + int(round(rng.gauss(0, sigma)))
            out[i] = max(-127, min(127, v)) & 0xff
    return bytes(out)


def score(row):
    # (no bot that ever set out for the exit reports 0: as far as can be)
    near = int(row["nearest"]) or 200
    s = 2 * (200 - min(near, 200)) - 3 * int(row["deaths"])
    if row["finished"]:
        s += 1000 + (16800 - int(row["tics"])) // 100
    return s


# every machine of the farm judges: games at once on each, and its share of
# the candidates in proportion. The arena's eval plays the very game doom's
# coopmatch does, on any of them.
WORKERS = {"laptop": 12, "mac": 5, "pi-01": 3, "pi-02": 3}
BASH = r"C:\Program Files\Git\bin\bash.exe"
FARM = str(Path.home() / ".claude/skills/farm-machines/farm.sh").replace("\\", "/")


def farm(*args, timeout=600):
    return subprocess.run([BASH, FARM, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="replace", timeout=timeout)


def unixpath(p):
    return str(p).replace("\\", "/")


def share(names):
    """the candidates each machine plays, in proportion to how many games it runs at once"""
    total = sum(WORKERS.values())
    out, at = {}, 0
    for k, (m, w) in enumerate(WORKERS.items()):
        n = len(names) - at if k == len(WORKERS) - 1 else round(len(names) * w / total)
        out[m] = names[at:at + n]
        at += n
    return out


def unix_start(machine, names, nets, maps, seeds):
    import tarfile
    kit = OUT / "kit" / machine
    if kit.exists():
        for old in kit.rglob("*"):
            if old.is_file():
                old.unlink()
    (kit / "candidates").mkdir(parents=True, exist_ok=True)
    jobs = []
    for name in names:
        (kit / "candidates" / (name + ".net")).write_bytes(nets[name])
        jobs += ["{} {} {}".format(name, m, s) for m in maps for s in seeds]
    (kit / "jobs.txt").write_bytes(("\n".join(jobs) + "\n").encode())
    tar = OUT / "kit" / (machine + ".tar")
    with tarfile.open(tar, "w") as t:
        t.add(kit / "jobs.txt", "jobs.txt")
        t.add(kit / "candidates", "candidates")
    farm("put", machine, unixpath(ROOT / "harness/eval-batch.sh"), "work/doomach/eval-batch.sh")
    farm("put", machine, unixpath(tar), "work/doomach/evolve.tar")
    farm("run", machine, "cd work/doomach && rm -rf evolve && mkdir evolve && tar -xf evolve.tar -C evolve")
    farm("start", machine, "work/doomach/evolve.log", "cd work/doomach && sh eval-batch.sh evolve {}".format(WORKERS[machine]))


def unix_done(machine):
    return "yes" in farm("run", machine, "test -f work/doomach/evolve/games/DONE && echo yes", timeout=120).stdout


def unix_fetch(machine, games):
    import tarfile
    farm("run", machine, "cd work/doomach/evolve && tar -cf ../games.tar games")
    local = OUT / "kit" / (machine + "-games.tar")
    farm("get", machine, "work/doomach/games.tar", unixpath(local))
    with tarfile.open(local) as t:
        for member in t.getmembers():
            if member.isfile() and member.name.endswith(".txt"):
                (games / Path(member.name).name).write_bytes(t.extractfile(member).read())


def play(nets, maps, seeds, parallel):
    """every net on every map and seed, across the farm; {name: [rows]}"""
    shares = share(sorted(nets))
    for machine in WORKERS:
        if machine != "laptop" and shares[machine]:
            unix_start(machine, shares[machine], nets, maps, seeds)
    kit = OUT / "kit"
    cand = kit / "candidates"
    cand.mkdir(parents=True, exist_ok=True)
    for old in cand.glob("*.net"):
        old.unlink()
    for name in shares["laptop"]:
        (cand / (name + ".net")).write_bytes(nets[name])
    parallel = WORKERS["laptop"]
    # (one command each: cmd takes what follows an `if` and an & as the if's)
    ssh("if not exist {0} mkdir {0}".format(REMOTE_W))
    ssh("if exist {0}\\games rmdir /s /q {0}\\games".format(REMOTE_W))
    ssh("if exist {0}\\candidates rmdir /s /q {0}\\candidates".format(REMOTE_W))
    for local in (ROOT / "out/windows-x86_64/release/bin/doom.exe", ROOT / "data/DOOM1.WAD", ROOT / "harness/farm-eval.ps1"):
        scp(str(local), "{}:{}/{}".format(LAPTOP, REMOTE, local.name))
    scp("-r", str(cand), "{}:{}/".format(LAPTOP, REMOTE))
    # run it there and wait: in its own process, so a dropped ssh does not stop it
    ps("$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{{PriorityClass = [uint32]32; ShowWindow = [uint16]0}}; "
       "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{{CommandLine = 'powershell -NoProfile -ExecutionPolicy Bypass -File {0}\\farm-eval.ps1 -Kit {0} -Parallel {1} -Maps {2} -Seeds {3}'; "
       "CurrentDirectory = '{0}'; ProcessStartupInformation = $si}} | Out-Null".format(REMOTE_W, parallel, ",".join(map(str, maps)), ",".join(map(str, seeds))))
    waiting = {m for m in WORKERS if shares[m]}
    for _ in range(720):
        time.sleep(10)
        if "laptop" in waiting and "True" in ssh('powershell -NoProfile -Command "Test-Path {}\\games\\DONE"'.format(REMOTE_W), 60).stdout:
            waiting.discard("laptop")
        for m in [m for m in waiting if m != "laptop"]:
            if unix_done(m):
                waiting.discard(m)
        if not waiting:
            break
    games = kit / "games"
    if games.exists():
        for old in games.glob("*"):
            old.unlink()
    if shares["laptop"]:
        scp("-r", "{}:{}/games".format(LAPTOP, REMOTE), str(kit))
    games.mkdir(parents=True, exist_ok=True)
    for machine in WORKERS:
        if machine != "laptop" and shares[machine]:
            unix_fetch(machine, games)
    rows = {}
    for g in games.glob("*.txt"):
        name, m, s = g.stem.rsplit("_", 2)
        row = pathbench.parse(g.read_text(encoding="utf-8", errors="replace"))
        rows.setdefault(name, []).append(dict(row, map=int(m), seed=int(s)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--net", type=Path, default=ROOT / "fixtures/bot0.net")
    ap.add_argument("--gens", type=int, default=40)
    ap.add_argument("--pop", type=int, default=23)
    ap.add_argument("--maps", default="2,3,4,9")
    ap.add_argument("--seeds-per-gen", type=int, default=2)
    ap.add_argument("--layers", default="out", choices=["out", "hidden", "all"])
    ap.add_argument("--outputs", default="forward,side,turn,fire,use,switch")
    ap.add_argument("--rate", type=float, default=0.15)
    ap.add_argument("--sigma", type=float, default=6.0)
    ap.add_argument("--margin", type=float, default=0.03, help="a mutant must beat the champion by this share of its score")
    ap.add_argument("--parallel", type=int, default=6)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    champ_path = OUT / "champion.net"
    champion = champ_path.read_bytes() if champ_path.exists() else a.net.read_bytes()
    assert len(champion) == NET
    log = OUT / "log.jsonl"
    start = sum(1 for _ in log.open()) if log.exists() else 0
    maps = [int(m) for m in a.maps.split(",")]
    at = mutable(a.layers, [OUTPUT_BITS[o] for o in a.outputs.split(",")])
    rng = random.Random(1234 + start)
    for gen in range(start, start + a.gens):
        seeds = [100 + gen * a.seeds_per_gen + k for k in range(a.seeds_per_gen)]
        nets = {"champion": champion}
        for i in range(a.pop):
            nets["m{}".format(i)] = mutate(champion, at, rng, a.rate, a.sigma)
        began = time.time()
        rows = play(nets, maps, seeds, a.parallel)
        full = len(maps) * len(seeds)
        table = {n: (sum(score(r) for r in rs), sum(bool(r["finished"]) for r in rs)) for n, rs in rows.items() if len(rs) == full}
        if "champion" not in table:
            print("gen", gen, "champion's games missing; again", flush=True)
            continue
        best = max(table, key=lambda n: table[n][0])
        cs = table["champion"][0]
        took = best != "champion" and table[best][0] > cs + abs(cs) * a.margin + 10
        if took:
            champion = nets[best]
            champ_path.write_bytes(champion)
            (OUT / "champion-gen{}.net".format(gen)).write_bytes(champion)
        entry = {"gen": gen, "seeds": seeds, "champion": table["champion"], "best": best, "best_score": table[best],
                 "took": took, "minutes": round((time.time() - began) / 60, 1), "layers": a.layers, "outputs": a.outputs}
        with log.open("a") as f:
            f.write(json.dumps(entry) + "\n")
        print(json.dumps(entry), flush=True)
    if not champ_path.exists():
        champ_path.write_bytes(champion)


if __name__ == "__main__":
    main()

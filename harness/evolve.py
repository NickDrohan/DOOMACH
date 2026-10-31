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
    s = 2 * (200 - min(int(row["nearest"]), 200)) - 3 * int(row["deaths"])
    if row["finished"]:
        s += 1000 + (16800 - int(row["tics"])) // 100
    return s


def play(nets, maps, seeds, parallel):
    """every net on every map and seed, on the laptop; {name: [rows]}"""
    kit = OUT / "kit"
    cand = kit / "candidates"
    cand.mkdir(parents=True, exist_ok=True)
    for old in cand.glob("*.net"):
        old.unlink()
    for name, net in nets.items():
        (cand / (name + ".net")).write_bytes(net)
    ssh('if exist {0}\\games rmdir /s /q {0}\\games & if exist {0}\\candidates rmdir /s /q {0}\\candidates & if not exist {0} mkdir {0}'.format(REMOTE_W))
    for local in (ROOT / "out/windows-x86_64/release/bin/doom.exe", ROOT / "data/DOOM1.WAD", ROOT / "harness/farm-eval.ps1"):
        scp(str(local), "{}:{}/{}".format(LAPTOP, REMOTE, local.name))
    scp("-r", str(cand), "{}:{}/".format(LAPTOP, REMOTE))
    # run it there and wait: in its own process, so a dropped ssh does not stop it
    ps("$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{{PriorityClass = [uint32]32; ShowWindow = [uint16]0}}; "
       "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{{CommandLine = 'powershell -NoProfile -ExecutionPolicy Bypass -File {0}\\farm-eval.ps1 -Kit {0} -Parallel {1} -Maps {2} -Seeds {3}'; "
       "CurrentDirectory = '{0}'; ProcessStartupInformation = $si}} | Out-Null".format(REMOTE_W, parallel, ",".join(map(str, maps)), ",".join(map(str, seeds))))
    for _ in range(720):
        time.sleep(10)
        if "True" in ssh('powershell -NoProfile -Command "Test-Path {}\\games\\DONE"'.format(REMOTE_W), 60).stdout:
            break
    games = kit / "games"
    if games.exists():
        for old in games.glob("*"):
            old.unlink()
    scp("-r", "{}:{}/games".format(LAPTOP, REMOTE), str(kit))
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
    ap.add_argument("--pop", type=int, default=11)
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

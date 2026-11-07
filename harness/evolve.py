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
import os
import random
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "harness"))
import pathbench  # noqa: E402

INPUTS, HIDDEN, OUTPUTS = 48, 24, 6
W2 = INPUTS * HIDDEN + HIDDEN
NET = W2 + HIDDEN * OUTPUTS + OUTPUTS
# the first shape of net: 32 senses
INPUTS_V1 = 32
NET_V1 = INPUTS_V1 * HIDDEN + HIDDEN + HIDDEN * OUTPUTS + OUTPUTS


def widen(old):
    """a first-shape net as this shape, deciding as it did (bot.widen)"""
    if len(old) == NET:
        return old
    assert len(old) == NET_V1
    new = bytearray(NET)
    for j in range(HIDDEN):
        new[j * INPUTS:j * INPUTS + INPUTS_V1] = old[j * INPUTS_V1:(j + 1) * INPUTS_V1]
        new[INPUTS * HIDDEN + j] = old[INPUTS_V1 * HIDDEN + j]
    rest = HIDDEN * OUTPUTS + OUTPUTS
    new[W2:W2 + rest] = old[INPUTS_V1 * HIDDEN + HIDDEN:INPUTS_V1 * HIDDEN + HIDDEN + rest]
    return bytes(new)
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


# the input a net reads the enemy's kind from (see F_FOEKIND in bot.mach)
F_FOEKIND = 29


def mutable(layers, outputs):
    at = []
    if layers in ("hidden", "all"):
        at += range(W2)
    # out+foe: the outputs, and how every hidden unit takes the enemy's kind
    if layers == "out+foe":
        at += [j * INPUTS + F_FOEKIND for j in range(HIDDEN)]
    # out+senses: the outputs, and how every hidden unit takes the senses the
    # second shape added (32 to 47) and the enemy's kind
    if layers == "out+senses":
        at += [j * INPUTS + i for j in range(HIDDEN) for i in [F_FOEKIND] + list(range(INPUTS_V1, INPUTS))]
    if layers in ("out", "all", "out+foe", "out+senses"):
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


# How long a game may run. Eight minutes, but twenty for E1M6: with its
# long walk and its door that shuts for thirty seconds, the round-204 net
# finished it 5 of 6 times in twenty minutes and 1 of 6 in eight, so at
# eight it taught nothing. And twenty for E1M7: three keys, each lost to a
# death, and teams cut off at eight minutes on their way to its exit. The
# league allows thirty.
LONG_MAPS = {6: 42000, 7: 42000}


def tics_for(m):
    return LONG_MAPS.get(m, 16800)


def score(row):
    # (no bot that ever set out for the exit reports 0: as far as can be)
    near = int(row["nearest"]) or 200
    s = 2 * (200 - min(near, 200)) - 3 * int(row["deaths"])
    # and up to 168 more the sooner it finished, in proportion to the time
    # the map is given, so a long map's teams are still pressed to be quick
    if row["finished"]:
        limit = tics_for(int(row.get("map", 0)))
        s += 1000 + 168 * max(0, limit - int(row["tics"])) // limit
    return s


# every machine of the farm judges: games at once on each, and its share of
# the candidates in proportion. The arena's eval plays the very game doom's
# coopmatch does, on any of them.
# (the laptop at 12 got half of every round and finished last, the Pis and
# the Mac waiting on it; at 9 the shares end nearer together)
WORKERS = {"laptop": 9, "mac": 5, "pi-01": 3, "pi-02": 3}
# EVOLVE_MACHINES=pi-01,pi-02: only those (the owner wants the others back)
if os.environ.get("EVOLVE_MACHINES"):
    WORKERS = {m: n for m, n in WORKERS.items() if m in os.environ["EVOLVE_MACHINES"].split(",")}
BASH = r"C:\Program Files\Git\bin\bash.exe"
FARM = str(next((p for p in (Path.home() / d / "skills/farm-machines/farm.sh" for d in (".agents", ".claude")) if p.exists()),
                Path.home() / ".claude/skills/farm-machines/farm.sh")).replace("\\", "/")


def farm(*args, timeout=600):
    return subprocess.run([BASH, FARM, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="replace", timeout=timeout)


def unixpath(p):
    return str(p).replace("\\", "/")


def reachable(machine):
    """whether a machine answers now and is ours to use (the laptop, on Wi-Fi, drops
    off, and is someone's while Steam is open on it: the owner's rule)"""
    try:
        if machine == "laptop":
            got = ssh('powershell -NoProfile -Command "if (Get-Process steam -ErrorAction SilentlyContinue) { \'steam\' } else { \'free\' }"', 30)
            return got.returncode == 0 and "free" in got.stdout
        return "ok" in farm("run", machine, "echo ok", timeout=60).stdout
    except subprocess.TimeoutExpired:
        return False


def share(names, live):
    """the candidates each machine that answered plays, in proportion to how many games it runs at once"""
    total = sum(WORKERS[m] for m in live)
    # the share rounding leaves over goes to the machine that runs the most
    # at once: given to the last-listed Pi, it kept pi-02 at work while every
    # other machine waited idle for it
    live = sorted(live, key=lambda m: WORKERS[m])
    out, at = {m: [] for m in WORKERS}, 0
    for k, m in enumerate(live):
        n = len(names) - at if k == len(live) - 1 else round(len(names) * WORKERS[m] / total)
        out[m] = names[at:at + n]
        at += n
    return out


def quietly(fn, *args):
    """a step that may meet a machine gone away: its games are then missing, not the run"""
    try:
        return fn(*args)
    except (subprocess.TimeoutExpired, OSError) as e:
        print("  ({} failed: {})".format(fn.__name__, e), flush=True)
        return None


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
        jobs += ["{} {} {} {}".format(name, m, s, tics_for(m)) for m in maps for s in seeds]
    # the longest games first, so no machine ends a round on one long game
    jobs.sort(key=lambda j: -int(j.split()[3]))
    (kit / "jobs.txt").write_bytes(("\n".join(jobs) + "\n").encode())
    tar = OUT / "kit" / (machine + ".tar")
    with tarfile.open(tar, "w") as t:
        t.add(kit / "jobs.txt", "jobs.txt")
        t.add(kit / "candidates", "candidates")
    # a batch left running by a stopped controller would write into this
    # one's folder and lose its games: stop it first (ours alone run there)
    farm("stop", machine, "xargs")
    farm("stop", machine, "arena")
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
    live = [m for m in WORKERS if reachable(m)]
    if not live:
        print("  no machine answers; waiting a minute", flush=True)
        time.sleep(60)
        return {}
    shares = share(sorted(nets), live)
    for machine in WORKERS:
        if machine != "laptop" and shares[machine]:
            quietly(unix_start, machine, shares[machine], nets, maps, seeds)
    if shares.get("laptop") and quietly(laptop_start, shares["laptop"], nets, maps, seeds) is None:
        shares["laptop"] = []
    kit = OUT / "kit"
    # at most half an hour: a machine that has gone away leaves its games missing
    waiting = {m for m in WORKERS if shares[m]}
    for _ in range(180):
        time.sleep(10)
        for m in list(waiting):
            done = quietly(laptop_done) if m == "laptop" else quietly(unix_done, m)
            if done:
                waiting.discard(m)
        if not waiting:
            break
    games = kit / "games"
    games.mkdir(parents=True, exist_ok=True)
    for old in games.glob("*"):
        old.unlink()
    if shares.get("laptop"):
        quietly(scp, "-r", "{}:{}/games".format(LAPTOP, REMOTE), str(kit))
    for machine in WORKERS:
        if machine != "laptop" and shares[machine]:
            quietly(unix_fetch, machine, games)
    rows = {}
    broken = 0
    for g in games.glob("*.txt"):
        name, m, s = g.stem.rsplit("_", 2)
        try:
            row = pathbench.parse(g.read_text(encoding="utf-8", errors="replace"))
        except ValueError:
            broken += 1
            continue
        rows.setdefault(name, []).append(dict(row, map=int(m), seed=int(s)))
    # what each machine was given and what came back, for evolve-status.py:
    # games go missing, and which machine loses them says why
    per = {m: [len(shares[m]) * len(maps) * len(seeds), sum(len(rows.get(n, [])) for n in shares[m])] for m in WORKERS if shares[m]}
    with (OUT / "machines.jsonl").open("a") as f:
        f.write(json.dumps({"t": int(time.time()), "seeds": seeds, "games": per, "unreadable": broken, "stillwaiting": sorted(waiting)}) + "\n")
    return rows


def laptop_done():
    return "True" in ssh('powershell -NoProfile -Command "Test-Path {}\\games\\DONE"'.format(REMOTE_W), 60).stdout


def laptop_stop():
    """the evaluator and its games, if a stopped controller left them running there"""
    return ps("Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'doomevolve' } | "
              "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }")


def laptop_start(names, nets, maps, seeds):
    laptop_stop()
    kit = OUT / "kit"
    cand = kit / "candidates"
    cand.mkdir(parents=True, exist_ok=True)
    for old in cand.glob("*.net"):
        old.unlink()
    for name in names:
        (cand / (name + ".net")).write_bytes(nets[name])
    parallel = WORKERS["laptop"]
    # (one command each: cmd takes what follows an `if` and an & as the if's)
    ssh("if not exist {0} mkdir {0}".format(REMOTE_W))
    ssh("if exist {0}\\games rmdir /s /q {0}\\games".format(REMOTE_W))
    ssh("if exist {0}\\candidates rmdir /s /q {0}\\candidates".format(REMOTE_W))
    # (DOOM_EVAL_EXE: another build of doom to judge with, as to compare)
    exe = Path(os.environ.get("DOOM_EVAL_EXE", str(ROOT / "out/windows-x86_64/release/bin/doom.exe")))
    scp(str(exe), "{}:{}/doom.exe".format(LAPTOP, REMOTE))
    for local in (ROOT / "data/DOOM1.WAD", ROOT / "harness/farm-eval.ps1"):
        scp(str(local), "{}:{}/{}".format(LAPTOP, REMOTE, local.name))
    scp("-r", str(cand), "{}:{}/".format(LAPTOP, REMOTE))
    # run it there and wait: in its own process, so a dropped ssh does not stop it
    ps("$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{{PriorityClass = [uint32]32; ShowWindow = [uint16]0}}; "
       "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{{CommandLine = 'powershell -NoProfile -ExecutionPolicy Bypass -File {0}\\farm-eval.ps1 -Kit {0} -Parallel {1} -Maps {2} -Seeds {3} -LongMaps {4} -LongTics {5}'; "
       "CurrentDirectory = '{0}'; ProcessStartupInformation = $si}} | Out-Null".format(REMOTE_W, parallel, ",".join(map(str, maps)), ",".join(map(str, seeds)),
                                                                                 ",".join(map(str, LONG_MAPS)) or "0", max(LONG_MAPS.values(), default=16800)))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--net", type=Path, default=ROOT / "fixtures/bot0.net")
    ap.add_argument("--gens", type=int, default=40)
    ap.add_argument("--pop", type=int, default=23)
    ap.add_argument("--maps", default="2,3,4,9")
    ap.add_argument("--seeds-per-gen", type=int, default=2)
    ap.add_argument("--layers", default="out", choices=["out", "hidden", "all", "out+foe", "out+senses"])
    ap.add_argument("--outputs", default="forward,side,turn,fire,use,switch")
    ap.add_argument("--rate", type=float, default=0.15)
    ap.add_argument("--sigma", type=float, default=6.0)
    ap.add_argument("--margin", type=float, default=0.03, help="a mutant must beat the champion by this share of its score")
    # the first-layer weights a layer setting opens are mutated more gently: a
    # weight on a sense of 127 moves a hidden unit twice as far as one on the
    # hidden layer's output, and with the outputs' own rate and size the
    # 2026-11-01 run (out+senses) ran from 7 of 12 levels to none in 30
    # generations
    ap.add_argument("--in-rate", type=float, default=0.04)
    ap.add_argument("--in-sigma", type=float, default=2.0)
    # and the generation's winner must win again, on two seeds of its own,
    # before it takes over: among 23 mutants on 12 games the best is often
    # only the luckiest, and luck accepted every generation is a slide
    ap.add_argument("--confirm-seeds", type=int, default=2)
    # and every so many generations the champion meets the last champion that
    # passed this check (anchor.net) on seeds of their own (700 up, never
    # trained on, apart from the final test's 900 up); losing, it is replaced
    # by the anchor. On 2026-11-02 the out+senses run, confirmations and all,
    # finished 8 of 36 unseen levels where the net it began from finished 16.
    ap.add_argument("--validate-every", type=int, default=5)
    ap.add_argument("--validate-seeds", type=int, default=4)
    ap.add_argument("--parallel", type=int, default=6)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    champ_path = OUT / "champion.net"
    champion = widen(champ_path.read_bytes() if champ_path.exists() else a.net.read_bytes())
    assert len(champion) == NET
    log = OUT / "log.jsonl"
    start = sum(1 for _ in log.open()) if log.exists() else 0
    maps = [int(m) for m in a.maps.split(",")]
    outs = [OUTPUT_BITS[o] for o in a.outputs.split(",")]
    at = mutable(a.layers, outs)
    at_out = sorted(set(at) & set(mutable("out", outs)))
    at_in = sorted(set(at) - set(at_out))
    rng = random.Random(1234 + start)
    anchor_path = OUT / "anchor.net"
    anchor = widen(anchor_path.read_bytes()) if anchor_path.exists() else champion
    if not anchor_path.exists():
        anchor_path.write_bytes(anchor)
    for gen in range(start, start + a.gens):
        if a.validate_every > 0 and gen > start and (gen - start) % a.validate_every == 0 and champion != anchor:
            vseeds = [700 + k for k in range(a.validate_seeds)]
            vrows = play({"champion": champion, "anchor": anchor}, maps, vseeds, a.parallel)
            want = len(maps) * len(vseeds)
            if len(vrows.get("champion", [])) == want and len(vrows.get("anchor", [])) == want:
                vc = sum(score(r) for r in vrows["champion"])
                va = sum(score(r) for r in vrows["anchor"])
                kept = vc >= va
                if kept:
                    anchor = champion
                    anchor_path.write_bytes(anchor)
                else:
                    champion = anchor
                    champ_path.write_bytes(champion)
                entry = {"validate": gen, "champion": vc, "anchor": va, "kept": kept,
                         "finished": [sum(bool(r["finished"]) for r in vrows["champion"]), sum(bool(r["finished"]) for r in vrows["anchor"])]}
                print(json.dumps(entry), flush=True)
                with (OUT / "validate.jsonl").open("a") as f:
                    f.write(json.dumps(entry) + "\n")
        seeds = [100 + gen * a.seeds_per_gen + k for k in range(a.seeds_per_gen)]
        nets = {"champion": champion}
        for i in range(a.pop):
            nets["m{}".format(i)] = mutate(mutate(champion, at_out, rng, a.rate, a.sigma), at_in, rng, a.in_rate, a.in_sigma)
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
        confirm = None
        if took and a.confirm_seeds > 0:
            again = [5000 + gen * a.confirm_seeds + k for k in range(a.confirm_seeds)]
            rerows = play({"champion": champion, best: nets[best]}, maps, again, a.parallel)
            want = len(maps) * len(again)
            if len(rerows.get("champion", [])) == want and len(rerows.get(best, [])) == want:
                confirm = [sum(score(r) for r in rerows["champion"]), sum(score(r) for r in rerows[best])]
                took = confirm[1] > confirm[0]
            else:
                took = False
        if took:
            champion = nets[best]
            champ_path.write_bytes(champion)
            (OUT / "champion-gen{}.net".format(gen)).write_bytes(champion)
        entry = {"gen": gen, "seeds": seeds, "champion": table["champion"], "best": best, "best_score": table[best],
                 "took": took, "confirm": confirm, "minutes": round((time.time() - began) / 60, 1), "layers": a.layers, "outputs": a.outputs}
        with log.open("a") as f:
            f.write(json.dumps(entry) + "\n")
        print(json.dumps(entry), flush=True)
    if not champ_path.exists():
        champ_path.write_bytes(champion)


if __name__ == "__main__":
    main()

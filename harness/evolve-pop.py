"""Evolve a population of co-op nets: several distinct good ones at once.

    python harness/evolve-pop.py --gens 1000

harness/evolve.py keeps one champion and forgets every mutant that narrowly
lost, so everything descends from one parent at one fixed step and the run
stalls. This keeps ELITES nets alive instead, each with a step size of its
own, and every generation:

- every elite plays again on the generation's fresh seeds (its score is the
  mean of its last WINDOW generations, so one lucky game does not make it,
  and one unlucky game does not undo it);
- CHILDREN mutants are made, each of a parent drawn from the elites (the
  better, the likelier), with the parent's step size nudged at random
  (self-adaptive: steps that make good children survive with them);
- the next elites are the best by mean score, but a net must differ from
  every better one kept by at least DIVERSE weight units, so the archive
  cannot collapse into copies of one net.

Every VALIDATE generations the best elite meets the anchor (the last net
that passed this check, out/farm/evolve/anchor.net) on seeds 700 up; only a
net that beats it becomes the anchor, and only the anchor is ever a
candidate for the live league (after harness/holdout.py on seeds 900 up).
State is kept in out/farm/evolve/pop/; a stopped run picks up from it.
"""
import argparse
import json
import math
import random
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "harness"))
import evolve as ev  # noqa: E402

POP = ev.OUT / "pop"


def distance(a, b, at):
    return sum(abs(int.from_bytes(a[i:i + 1], "little", signed=True) - int.from_bytes(b[i:i + 1], "little", signed=True)) for i in at)


def load():
    state = POP / "state.json"
    if not state.exists():
        return None
    s = json.loads(state.read_text())
    for e in s["elites"]:
        e["net"] = (POP / (e["name"] + ".net")).read_bytes()
    return s


def save(s):
    POP.mkdir(parents=True, exist_ok=True)
    for e in s["elites"]:
        (POP / (e["name"] + ".net")).write_bytes(e["net"])
    keep = {e["name"] for e in s["elites"]}
    for old in POP.glob("*.net"):
        if old.stem not in keep:
            old.unlink()
    (POP / "state.json").write_text(json.dumps({**s, "elites": [{k: v for k, v in e.items() if k != "net"} for e in s["elites"]]}, indent=1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gens", type=int, default=1000)
    ap.add_argument("--elites", type=int, default=6)
    ap.add_argument("--children", type=int, default=10)
    ap.add_argument("--window", type=int, default=4)
    ap.add_argument("--diverse", type=int, default=60)
    ap.add_argument("--maps", default="3,4,5,6,7,9")
    ap.add_argument("--seeds-per-gen", type=int, default=2)
    ap.add_argument("--layers", default="out+senses")
    ap.add_argument("--outputs", default="turn,fire,side,switch")
    ap.add_argument("--rate", type=float, default=0.15)
    ap.add_argument("--validate-every", type=int, default=5)
    # sixteen seeds a check (96 games), and eight more levels finished to win
    # it. Three on 48 games was under one standard deviation of luck: the net
    # that won 39 to 26 (round 529) then lost the unseen-seed test 20 to 27.
    ap.add_argument("--validate-seeds", type=int, default=16)
    ap.add_argument("--validate-margin", type=int, default=8)
    a = ap.parse_args()
    maps = [int(m) for m in a.maps.split(",")]
    outs = [ev.OUTPUT_BITS[o] for o in a.outputs.split(",")]
    at = ev.mutable(a.layers, outs)
    at_out = sorted(set(at) & set(ev.mutable("out", outs)))
    at_in = sorted(set(at) - set(at_out))
    anchor_path = ev.OUT / "anchor.net"
    anchor = ev.widen(anchor_path.read_bytes())
    s = load()
    if s is None:
        # a first population: the anchor, and spread-out mutants of it
        rng = random.Random(42)
        elites = [{"name": "e0", "net": anchor, "sigma": 4.0, "scores": [], "born": 0, "parent": "anchor"}]
        for k in range(1, a.elites):
            elites.append({"name": "e{}".format(k), "net": ev.mutate(anchor, at, rng, a.rate, 6.0), "sigma": 2.0 + k, "scores": [], "born": 0, "parent": "e0"})
        s = {"gen": 0, "next": a.elites, "elites": elites}
        save(s)
    rng = random.Random(9000 + s["gen"])
    log = POP / "log.jsonl"
    for _ in range(a.gens):
        gen = s["gen"]
        elites = s["elites"]
        mean = lambda e: sum(e["scores"]) / len(e["scores"]) if e["scores"] else -1e9
        # parents by rank: the better, the likelier
        ranked = sorted(elites, key=mean, reverse=True)
        weights = [len(ranked) - i for i in range(len(ranked))]
        children = []
        for c in range(a.children):
            parent = rng.choices(ranked, weights)[0]
            sigma = min(12.0, max(0.75, parent["sigma"] * math.exp(rng.gauss(0, 0.3))))
            net = ev.mutate(ev.mutate(parent["net"], at_out, rng, a.rate, sigma), at_in, rng, a.rate / 4, sigma / 3)
            children.append({"name": "c{}".format(s["next"] + c), "net": net, "sigma": sigma, "scores": [], "born": gen, "parent": parent["name"]})
        s["next"] += a.children
        everyone = elites + children
        seeds = [20000 + gen * a.seeds_per_gen + k for k in range(a.seeds_per_gen)]
        began = time.time()
        rows = ev.play({e["name"]: e["net"] for e in everyone}, maps, seeds, 0)
        full = len(maps) * len(seeds)
        for e in everyone:
            rs = rows.get(e["name"], [])
            if len(rs) == full:
                e["scores"] = (e["scores"] + [sum(ev.score(r) for r in rs) / full])[-a.window:]
                e["last"] = sum(bool(r["finished"]) for r in rs)
        # the next elites: best mean first, none too like one kept before it.
        # A child judged on one generation is ranked by that one, and is
        # judged again next time as an elite; an elite judged on none (its
        # games lost) keeps its old scores
        kept = []
        for e in sorted(everyone, key=mean, reverse=True):
            if not e["scores"]:
                continue
            if all(distance(e["net"], k["net"], at) >= a.diverse for k in kept):
                kept.append(e)
            if len(kept) == a.elites:
                break
        s["elites"] = kept
        s["gen"] = gen + 1
        entry = {"gen": gen, "minutes": round((time.time() - began) / 60, 1),
                 "elites": [{"name": e["name"], "mean": round(mean(e)), "n": len(e["scores"]), "last": e.get("last"), "sigma": round(e["sigma"], 2), "parent": e["parent"]} for e in kept],
                 "children_kept": sum(1 for e in kept if e in children)}
        # the best elite that has been judged at least twice, against the anchor
        if a.validate_every > 0 and (gen + 1) % a.validate_every == 0:
            proven = [e for e in kept if len(e["scores"]) >= 2]
            if proven and proven[0]["net"] != anchor:
                best = proven[0]
                # fresh seeds every check: the same four, night after night,
                # were learned (2026-11-03: an anchor that won four checks on
                # seeds 700-703 finished 22 of 36 unseen levels to the live
                # net's 27)
                vseeds = [50000 + gen * a.validate_seeds + k for k in range(a.validate_seeds)]
                vrows = ev.play({"best": best["net"], "anchor": anchor}, maps, vseeds, 0)
                want = len(maps) * len(vseeds)
                if len(vrows.get("best", [])) == want and len(vrows.get("anchor", [])) == want:
                    vb = sum(ev.score(r) for r in vrows["best"])
                    va = sum(ev.score(r) for r in vrows["anchor"])
                    fb = sum(bool(r["finished"]) for r in vrows["best"])
                    fa = sum(bool(r["finished"]) for r in vrows["anchor"])
                    # a new anchor must finish clearly more levels, not merely
                    # score higher: on 2026-11-03 twenty of forty checks moved
                    # the anchor, many on ties in levels (16 to 16) won by a
                    # few hundred points, which on 24 games is luck
                    better = fb >= fa + a.validate_margin and vb > va
                    entry["validate"] = {"elite": best["name"], "finished": [fb, fa], "score": [vb, va], "new_anchor": better}
                    if better:
                        anchor = best["net"]
                        anchor_path.write_bytes(anchor)
                        (ev.OUT / "anchor-pop-gen{}.net".format(gen)).write_bytes(anchor)
        save(s)
        with log.open("a") as f:
            f.write(json.dumps(entry) + "\n")
        print(json.dumps(entry), flush=True)


if __name__ == "__main__":
    main()

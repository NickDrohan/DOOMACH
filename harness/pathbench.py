import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("stuck", "wedges", "acid", "floordeaths")


def parse(text):
    path = re.search(r"^pathing stuck (\d+) wedges (\d+) acid (\d+) floordeaths (\d+)$", text, re.M)
    end = re.search(r"^end tic (\d+) finished ([01]) ", text, re.M)
    deaths = sum(int(d) for d in re.findall(r"^bot \d+ kills \d+ deaths (\d+)", text, re.M))
    if path is None or end is None:
        raise ValueError("missing pathing summary")
    result = dict(zip(FIELDS, map(int, path.groups())))
    result.update(tics=int(end.group(1)), finished=end.group(2) == "1", deaths=deaths)
    return result


def main():
    parser = argparse.ArgumentParser(description="Measure bot wedging and hazardous-floor exposure.")
    parser.add_argument("--exe", type=Path, default=ROOT / "out/windows-x86_64/release/bin/doom.exe")
    parser.add_argument("--mode", default=str(ROOT / "fixtures/bot0.net"))
    parser.add_argument("--maps", default="1,2,3,4,5,6,7,9")
    parser.add_argument("--seeds", default="0,1")
    parser.add_argument("--tics", type=int, default=16800)
    parser.add_argument("--timeout", type=float, default=40)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    rows, totals = [], dict.fromkeys(FIELDS + ("deaths", "finished"), 0)
    for m in [int(v) for v in args.maps.split(",")]:
        for seed in [int(v) for v in args.seeds.split(",")]:
            run = subprocess.run([str(args.exe), "coopmatch", str(ROOT / "data/DOOM1.WAD"), str(m), str(args.tics), args.mode, str(seed)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", timeout=args.timeout)
            if run.returncode != 0:
                raise SystemExit("E1M{} seed {} exited {}".format(m, seed, run.returncode))
            row = dict(map="E1M{}".format(m), seed=seed, **parse(run.stdout))
            rows.append(row)
            for key in totals:
                totals[key] += int(row[key])
            print(json.dumps(row, sort_keys=True), flush=True)
    print(json.dumps({"totals": totals, "runs": len(rows)}, sort_keys=True), flush=True)
    if args.report:
        args.report.write_text(json.dumps({"rows": rows, "totals": totals}, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

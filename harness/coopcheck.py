import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def parse_result(text, map_number, cap):
    end = re.search(r"^end tic (\d+) finished ([01]) secrets (\d+) of (\d+) sum (\d+) map E1M(\d+)$", text, re.M)
    bots = re.findall(r"^bot (\d+) kills (\d+) deaths (\d+)", text, re.M)
    if end is None or len(bots) != 4 or {int(b[0]) for b in bots} != {1, 2, 3, 4}:
        raise ValueError("missing or incomplete co-op result")
    tic, finished, secrets, total, checksum, actual_map = map(int, end.groups())
    if actual_map != map_number or not 0 < tic <= cap:
        raise ValueError("result does not match the requested map or tic limit")
    cutoff = re.search(r"^league cutoff ([01])$", text, re.M)
    gaveup = bool(cutoff and cutoff.group(1) == "1")
    if gaveup and finished:
        raise ValueError("abandonment was reported as completion")
    return {
        "gaveup": gaveup,
        "finished": bool(finished), "tics": tic, "seconds": round(tic / 35, 3),
        "secrets": secrets, "total_secrets": total, "checksum": checksum,
        "kills": sum(int(b[1]) for b in bots), "deaths": sum(int(b[2]) for b in bots),
    }


def numbers(text, low, high):
    values = [int(value) for value in text.split(",")]
    if not values or any(value < low or value > high for value in values):
        raise ValueError("number outside permitted range")
    return list(dict.fromkeys(values))


def main():
    parser = argparse.ArgumentParser(description="Require actual co-op exits across maps and seeds.")
    parser.add_argument("--exe", type=Path, default=ROOT / "out/windows-x86_64/release/bin/doom.exe")
    parser.add_argument("--wad", type=Path, default=ROOT / "data/DOOM1.WAD")
    parser.add_argument("--net", type=Path, default=ROOT / "fixtures/bot0.net")
    parser.add_argument("--mode", choices=["net", "script", "calm"], default="net")
    parser.add_argument("--maps", default="1,2,3,4,5,6,7,8,9")
    parser.add_argument("--seeds", default="0,1,2,3,4")
    parser.add_argument("--tics", type=int, default=16800)
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--league", action="store_true")
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    args = parser.parse_args()
    try:
        maps = numbers(args.maps, 1, 9)
        seeds = numbers(args.seeds, 0, 0xffffffff)
    except ValueError as error:
        parser.error(str(error))
    if args.tics < 1 or args.timeout <= 0:
        parser.error("tic and wall-time limits must be positive")
    for path in [args.exe, args.wad] + ([args.net] if args.mode == "net" else []):
        if not path.is_file():
            parser.error("missing input: " + str(path))
    if args.report and not args.report.parent.is_dir():
        parser.error("report directory must already exist")
    mode = str(args.net.resolve()) if args.mode == "net" else args.mode
    report = {
        "mode": args.mode, "maps": maps, "seeds": seeds, "tic_limit": args.tics,
        "exe_sha256": hashlib.sha256(args.exe.read_bytes()).hexdigest(),
        "wad_sha256": hashlib.sha256(args.wad.read_bytes()).hexdigest(),
        "league": args.league, "cases": [],
    }
    if args.mode == "net":
        report["net_sha256"] = hashlib.sha256(args.net.read_bytes()).hexdigest()
    stop = False
    for map_number in maps:
        for seed in seeds:
            record = {"map": "E1M" + str(map_number), "seed": seed, "finished": False}
            began = time.monotonic()
            try:
                result = subprocess.run(
                    [str(args.exe.resolve()), "coopmatch", str(args.wad.resolve()),
                     str(map_number), str(args.tics), mode, str(seed)] +
                    (["leaguetrace" if args.trace else "league"] if args.league else (["trace"] if args.trace else [])),
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    encoding="utf-8", errors="replace", timeout=args.timeout,
                )
                record["exit_code"] = result.returncode
                if args.trace:
                    record["trace"] = result.stderr.splitlines()
                    record["players"] = result.stdout.splitlines()
                if result.returncode != 0:
                    record["error"] = result.stderr[-2000:]
                else:
                    record.update(parse_result(result.stdout, map_number, args.tics))
            except subprocess.TimeoutExpired as error:
                record["error"] = "wall-time limit exceeded"
                if args.trace:
                    partial = error.stderr or ""
                    if isinstance(partial, bytes):
                        partial = partial.decode("utf-8", "replace")
                    record["trace"] = partial.splitlines()
            except ValueError as error:
                record["error"] = str(error)
            record["wall_seconds"] = round(time.monotonic() - began, 3)
            report["cases"].append(record)
            print(json.dumps({key: value for key, value in record.items() if key not in ["trace", "players"]}, sort_keys=True), flush=True)
            if args.fail_fast and not record["finished"]:
                stop = True
                break
        if stop:
            break
    report["finished"] = sum(record["finished"] for record in report["cases"])
    report["attempted"] = len(report["cases"])
    report["expected"] = len(maps) * len(seeds)
    report["passed"] = report["finished"] == report["attempted"] == report["expected"] and report["expected"] > 0
    inputs = [(args.exe, "exe_sha256"), (args.wad, "wad_sha256")]
    if args.mode == "net":
        inputs.append((args.net, "net_sha256"))
    if any(hashlib.sha256(path.read_bytes()).hexdigest() != report[key] for path, key in inputs):
        report["passed"] = False
        report["error"] = "an input changed during qualification"
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ["finished", "attempted", "expected", "passed"]}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())

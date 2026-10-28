#!/usr/bin/env bash
# Build the download: one zip with the game, the shareware WAD, a page on how
# to play, the licence, and the complete source the GPL asks to go with it.
#
#   bash package.sh          writes out/package/doom-in-mach.zip
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$here"

(cd "$here" && sha256sum -c --status fixtures/DOOM1.WAD.sha256) || {
    echo "package: data/DOOM1.WAD is missing or not shareware 1.9; run bootstrap.sh" >&2
    exit 1
}
"$root/scripts/mach" build "$here" --profile release --jobs 2 --quiet

python=""
for candidate in "${PYTHON:-}" python python3; do
    if [[ -n "$candidate" ]] && "$candidate" -c 'import zipfile' 2>/dev/null; then
        python="$candidate"
        break
    fi
done
[[ -n "$python" ]] || { echo "package: python is needed to write the zip" >&2; exit 1; }

mkdir -p "$here/out/package"
"$python" - "$root" "$here" "$here/out/package/doom-in-mach.zip" <<'EOF'
import os, subprocess, sys, zipfile

root, here, target = sys.argv[1:4]
top = "doom-in-mach/"

# the source: tracked repository files, never local captures or tool metadata,
# the WAD, id's code, the compiler, dependencies, or build output
skip = {"data", "ref", "out", "dep", "tools", ".git", ".qark", ".devin", ".claude", ".cursor", ".vscode", ".idea"}
new = subprocess.check_output(["git", "-C", here, "ls-files", "--others", "--exclude-standard", "-z", "--", "src", "harness", "site", "scripts", "package"]).decode("utf-8").split("\0")
if any(new):
    raise SystemExit("package: untracked source files must be added before publishing: " + ", ".join(path for path in new if path))
tracked = subprocess.check_output(["git", "-C", here, "ls-files", "-z"]).decode("utf-8").split("\0")
source = os.path.join(os.path.dirname(target), "source.zip")
with zipfile.ZipFile(source, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for rel in sorted(path for path in tracked if path):
        if rel.split("/", 1)[0] in skip:
            continue
        path = os.path.join(here, rel)
        if os.path.islink(path) or not os.path.isfile(path):
            raise SystemExit("package: source is not a regular file: " + rel)
        z.write(path, "DOOMACH/" + rel)

with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(os.path.join(here, "out/windows-x86_64/release/bin/doom.exe"), top + "doom.exe")
    z.write(os.path.join(here, "data/DOOM1.WAD"), top + "DOOM1.WAD")
    z.write(os.path.join(here, "package/README.txt"), top + "README.txt")
    # the Linux launcher keeps its execute bit through unzip
    info = zipfile.ZipInfo(top + "doom.sh")
    info.external_attr = 0o100755 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, open(os.path.join(here, "package/doom.sh"), "rb").read().replace(b"\r\n", b"\n"))
    z.write(os.path.join(here, "LICENSE"), top + "COPYING.txt")
    z.write(source, top + "source.zip")
# source.zip stays beside the download too, for the page to offer on its own
print("%s  %d bytes" % (target, os.path.getsize(target)))
EOF

#!/usr/bin/env python3
# The weekly size watch's comparison (ci/sizes.sh gathers its data; ci/status.sh puts the result in the Friday issue):
# what goes on the ISO and on a new install against last week's, and whether the files AgrOS never unpacks are still
# there under those names.
#   ci/sizes.py <data dir> <last week's baseline, or ""> <out dir>
# The data dir (each set: iso, the live ISO's packages; inst, a new install's):
#   <set>.si        pacman -Si of the set's packages (all that's installed, dependencies too)
#   <set>.files     pacman -Fl of them: "package path" lines
#   <set>.unknown   names the set's list asks for that no repo has (each fails the build or the install)
#   iso.leftout     what agros-trim.sh leaves out of the ISO
#   live.pats, inst.pats, agros.pats   NoExtract patterns, one a line: agros-trim.sh's for the live ISO and for
#                   installed systems, and agros-system's agros-noextract.conf (installed systems' too)
# Writes <out>/report (a line for each thing that needs a look), <out>/table (rows for the issue's table) and
# <out>/baseline ("<set> <package> <KiB>" lines: next week's to compare with).
import os
import re
import sys

NEW_MIB = 20  # a package new this week this big or bigger is said
GREW_MIB = 50  # a set grown this much this week is said
UNITS = {"B": 1 / 1024, "KiB": 1, "MiB": 1024, "GiB": 1024 * 1024}
SETS = (("iso", "The ISO"), ("inst", "A new install"))

data, prev_path, out = sys.argv[1:4]


def read(name):
    try:
        with open(os.path.join(data, name), encoding="utf-8") as f:
            return [line.rstrip("\n") for line in f if line.strip()]
    except FileNotFoundError:
        return []


def bare(dep):
    # (a dependency's name: no version, no description)
    return re.split(r"[<>=:]", dep, maxsplit=1)[0].strip()


def si(name):
    # pacman -Si: "Field : value" lines, a blank line between packages; a long value may go on over indented lines
    pkgs, cur, key = {}, {}, None

    def done():
        if "Name" in cur:
            num, unit = cur.get("Installed Size", "0 B").split()
            pkgs[cur["Name"]] = {
                "kib": float(num.replace(",", "")) * UNITS[unit],
                "deps": {bare(d) for d in cur.get("Depends On", "").split() if d != "None"},
                "provides": {bare(d) for d in cur.get("Provides", "").split() if d != "None"},
            }

    with open(os.path.join(data, name), encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                done()
                cur, key = {}, None
            elif line[0].isspace() and key:
                cur[key] += " " + line.strip()
            elif " : " in line:
                key, value = (s.strip() for s in line.split(" : ", 1))
                cur[key] = value
    done()
    return pkgs


def mib(kib):
    return f"{kib / 1024:.0f} MiB"


def size(kib):
    return f"{kib / 1024 / 1024:.2f} GiB" if kib >= 1024 * 1024 else mib(kib)


def pulled_in_by(pkgs, name):
    # (the packages of the set that depend on it, or on something it provides)
    names = {name} | pkgs[name]["provides"]
    by = sorted(n for n, p in pkgs.items() if n != name and p["deps"] & names)
    return ", ".join(by[:3]) + (f" and {len(by) - 3} more" if len(by) > 3 else "") if by else "the list itself"


prev = {}
if prev_path and os.path.exists(prev_path):
    with open(prev_path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3:
                prev.setdefault(parts[0], {})[parts[1]] = float(parts[2])

report, table, baseline = [], [], []
sets = {}
for key, label in SETS:
    pkgs = sets[key] = si(f"{key}.si")
    total = sum(p["kib"] for p in pkgs.values())
    old = prev.get(key)
    row = f"| {label}: its packages | {len(pkgs)}, {size(total)} installed"
    if old:
        old_total = sum(old.values())
        row += f" (last week {len(old)}, {size(old_total)})"
        new = sorted((n for n in pkgs if n not in old), key=lambda n: -pkgs[n]["kib"])
        for n in new:
            if pkgs[n]["kib"] >= NEW_MIB * 1024:
                report.append(f"{label}: {n} ({mib(pkgs[n]['kib'])}) is new this week, pulled in by {pulled_in_by(pkgs, n)}")
        if total - old_total >= GREW_MIB * 1024:
            grew = sorted(pkgs, key=lambda n: -(pkgs[n]["kib"] - old.get(n, 0)))[:3]
            report.append(f"{label} grew by {mib(total - old_total)} this week ({size(old_total)} → {size(total)}), "
                          "most in " + ", ".join(f"{n} (+{mib(pkgs[n]['kib'] - old.get(n, 0))})" for n in grew))
    table.append(row + " |")
    baseline += [f"{key} {n} {p['kib']:.0f}" for n, p in sorted(pkgs.items())]
    for n in read(f"{key}.unknown"):
        report.append(f"{label}: its list asks for {n}, which no repo has (the build or the install fails on it)")

for n in read("iso.leftout"):
    if n in sets["iso"]:
        report.append(f"The ISO: {n} is back (agros-trim.sh leaves it out), pulled in by {pulled_in_by(sets['iso'], n)}")


def glob_re(pattern):
    # pacman's NoExtract: fnmatch with no flags, * matching / too; one line per file, so * stops at a line's end
    return re.compile("^" + re.escape(pattern).replace(r"\*", ".*").replace(r"\?", ".") + "$", re.M)


files = {key: "\n".join(line.split(" ", 1)[1] for line in read(f"{key}.files") if " " in line) for key, _ in SETS}
for pats, key, where in (("live.pats", "iso", "agros-trim.sh, the live ISO's"),
                         ("inst.pats", "inst", "agros-trim.sh, installed systems'"),
                         ("agros.pats", "inst", "agros-noextract.conf")):
    for p in read(pats):
        if not p.startswith("!") and not glob_re(p).search(files[key]):
            report.append(f"{where} NoExtract pattern {p} matches no file any more (renamed?): those files are unpacked again")
if read("inst.pats") != read("agros.pats"):
    report.append("agros-iso's agros-trim.sh (installed systems' NoExtract) and agros's agros-noextract.conf differ: "
                  "keep them the same")

os.makedirs(out, exist_ok=True)
for name, lines in (("report", report), ("table", table), ("baseline", baseline)):
    with open(os.path.join(out, name), "w", encoding="utf-8") as f:
        f.writelines(line + "\n" for line in lines)

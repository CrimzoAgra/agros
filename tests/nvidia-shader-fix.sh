#!/usr/bin/env bash
# nvidia-shader-fix's edit of Steam's localconfig.vdf: added once, an existing %command% option kept, a game with no
# entry yet gets one, taken out again leaving the rest as it was. Only on the GPUs it's for (none on AMD/Intel)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
python3 -I - "$here/.local/bin/nvidia-shader-fix" "$t" <<'P'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("fix", sys.argv[1])
fix = importlib.util.module_from_spec(importlib.util.spec_from_loader("fix", loader))
loader.exec_module(fix)
S = fix.SELF
vdf = '"UserLocalConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"apps"\n\t\t\t\t{\n' \
      '\t\t\t\t\t"100"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LaunchOptions"\t\t"gamemoderun %command% -dx11"\n\t\t\t\t\t\t"Playtime"\t\t"5"\n\t\t\t\t\t}\n' \
      '\t\t\t\t\t"200"\n\t\t\t\t\t{\n\t\t\t\t\t\t"Playtime"\t\t"9"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n'
on = fix.set_wrapper(vdf, "100", True)
assert f'"gamemoderun {S} %command% -dx11"' in on, on
assert fix.set_wrapper(on, "100", True) == on, "added twice"
assert fix.set_wrapper(on, "100", False) == vdf, "not taken out cleanly"
plain = fix.set_wrapper(vdf, "200", True)
assert f'"LaunchOptions"\t\t"{S} %command%"' in plain and '"Playtime"\t\t"9"' in plain, plain
new = fix.set_wrapper(vdf, "300", True)
assert '"300"' in new and f"{S} %command%" in new.split('"300"')[1], "no entry added for a game never started"
assert fix.set_wrapper(vdf, "300", False) == vdf, "an entry added for a game the fix doesn't want"
# The same id as a key outside the apps block (after it, elsewhere in the file): not taken for the game's entry; its
# entry added in the apps block, the other one left as it was
other = vdf.replace('\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n', '\t\t\t\t}\n\t\t\t\t"cloud"\n\t\t\t\t{\n\t\t\t\t\t"400"\n\t\t\t\t\t{\n'
                    '\t\t\t\t\t\t"LaunchOptions"\t\t"keep {me}"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n')
assert other != vdf
got = fix.set_wrapper(other, "400", True)
apps_part, cloud_part = got.split('"cloud"')
assert '"LaunchOptions"\t\t"keep {me}"' in cloud_part and S not in cloud_part, cloud_part
assert '"400"' in apps_part and f"{S} %command%" in apps_part, apps_part
# Which machines it's for: any NVIDIA card of the series (a second one too); none on AMD/Intel (no nvidia-smi, or no
# NVIDIA device), nor another game
import os, stat, tempfile
bin_ = tempfile.mkdtemp(dir=sys.argv[2])  # (in the test's folder: removed also when a check fails)
smi = os.path.join(bin_, "nvidia-smi")
def gpus(out):
    with open(smi, "w") as f:
        f.write(f"#!/bin/sh\nprintf '{out}'\n")
    os.chmod(smi, stat.S_IRWXU)
os.environ["PATH"] = bin_
assert not fix.affected("1091500"), "affected with no nvidia-smi"
gpus("No devices were found\\n")
assert not fix.affected("1091500"), "affected with no NVIDIA device"
gpus("8.9, 610.43\\n")
assert not fix.affected("1091500"), "affected on another architecture"
gpus("8.9, 610.43\\n7.5, 610.43\\n")
assert fix.affected("1091500"), "a Turing second card not seen"
assert not fix.affected("100"), "affected for a game it has no fix for"
# Affected but no spirv-tools to make the fix with: the game just runs, and you're told
ran, told = [], []
fix.os.execvp = lambda prog, cmd: ran.append(cmd) or sys.exit(0)
fix.notify = told.append
os.environ["SteamAppId"] = "1091500"
fix.HOME = fix.OVERRIDES = bin_  # (not your own: a fix made there already took the spirv-tools check out of it)
try:
    fix.run(["game"])
except SystemExit:
    pass
assert ran == [["game"]] and "spirv-tools" in told[0], (ran, told)
# With them: the launch dumps the shader; a fixed one that failed half-written isn't left to be loaded next launch,
# one that worked is
spv = f"{bin_}/1091500/2169eb1a6850d504.spv"
game = ["/bin/sh", "-c", 'echo dumped >"$VKD3D_SHADER_DUMP_PATH/2169eb1a6850d504.spv"']
for tool, script in (("spirv-val", "exit 0"), ("spirv-opt", 'echo half >"$4"; exit 1')):
    with open(f"{bin_}/{tool}", "w") as f:
        f.write(f"#!/bin/sh\n{script}\n")
    os.chmod(f"{bin_}/{tool}", stat.S_IRWXU)
fix.run(game)
assert not os.path.exists(spv), "a fixed shader that failed half-written left in place"
with open(f"{bin_}/spirv-opt", "w") as f:
    f.write('#!/bin/sh\necho fixed >"$4"\n')
fix.run(game)
assert open(spv).read() == "fixed\n" and not os.path.exists(spv + ".tmp"), "the fixed shader not made"
P
echo "ok nvidia-shader-fix"

#!/usr/bin/env bash
# ci/test-passes.sh: which side broke the tests. All pass on this run's [agros]: ok; those that failed pass with the
# published [agros]: hold-agros, and which new build broke them (each tried alone, those tests alone run again), held
# with what needs it; then on Arch as of the last good day: hold-upstream; else fail. Each pass runs every test (what it
# ran: "all"). pacman and the tests are stand-ins, which fail as $BROKEN says (built, published, today, a new build)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/repo/ci" "$t/repo/tests" "$t/bin"
cp "$here/ci/test-passes.sh" "$t/repo/ci/"
printf '[core]\nInclude = x\n[agros]\nServer = https://example.invalid/old\n' >"$t/pacman.conf"
: >"$t/mirrorlist"
# mkdb <db> <name>-<version>[:<needs>,...[:<provides>,...]]...: a sync database
mkdb() {
    local db=$1 d p n v; shift
    d=$(mktemp -d "$t/db.XXXX")
    for p; do
        n=${p%%:*} v=${p%%:*} && v=${v##*-} n=${n%-*}
        p+=::
        mkdir "$d/$n-$v-1"
        printf '%%FILENAME%%\n%s-%s-1-x86_64.pkg.tar.zst\n\n%%NAME%%\n%s\n\n%%DEPENDS%%\n%s\n\n%%PROVIDES%%\n%s\n\n' "$n" "$v" \
            "$n" "$(cut -d: -f2 <<<"$p" | tr ',' '\n')" "$(cut -d: -f3 <<<"$p" | tr ',' '\n')" >"$d/$n-$v-1/desc"
    done
    (cd "$d" && bsdtar -czf "$db" -- *)
}
# (this run's [agros]: new Caelestia, Quickshell (which Caelestia needs, by what it provides), CLI and a meta package
# that needs Caelestia, not installed here; the published one's; what's installed here)
mkdir -p "$t/dbs"
mkdb "$t/dbs/built.db" 'caelestia-shell-2:quickshell>=2,glibc' 'quickshell-git-2::quickshell=2' caelestia-cli-2 \
    'caelestia-meta-2:caelestia-shell' spicetify-1 agros-system-9
mkdb "$t/dbs/published.db" 'caelestia-shell-1:quickshell' 'quickshell-git-1::quickshell=1' caelestia-cli-1 \
    'caelestia-meta-1:caelestia-shell' spicetify-1 agros-system-8
printf '%s\n' caelestia-cli caelestia-shell glibc quickshell-git spicetify-not >"$t/here"
# (pacman: the [agros] it syncs, the database its Server names; fails while that's the one $PACFAIL names, a download
# that failed. -U puts this run's builds in ($t/installed), -Suu takes them out, -Q what's installed here)
sed "s|@T@|$t|g" >"$t/bin/pacman" <<'S'
#!/bin/bash
srv=$(sed -n 's|^Server = ||p' @T@/pacman.conf) && srv=${srv##*/}
case $1 in
    -Sy*) [[ ! -s @T@/mirrorlist ]] || srv=archive
        echo "$srv $*" >>@T@/syncs
        if [[ -n $PACFAIL && $srv == "${PACFAIL%:once}" ]]; then
            [[ $PACFAIL == *:once && -e @T@/failed-once ]] || { touch @T@/failed-once; exit 1; }
        fi
        [[ ! -e @T@/dbs/$srv.db ]] || cp @T@/dbs/$srv.db @T@/sync/agros.db ;;
    -U) for f in "${@:2}"; do [[ $f == -* ]] || { f=${f##*/}; echo "${f%-*-*-*}" >>@T@/installed; }; done ;;
    -Suu) : >@T@/installed ;;
    -Q) grep -qx "$2" @T@/here ;;
    -Qq) sort -u @T@/here @T@/installed ;;
esac
S
printf '#!/bin/sh\nshift 2\nexec "$@"\n' >"$t/bin/runuser"
# (the stand-in tests: hypr-api and lutris; they fail where $BROKEN names the [agros] or the Arch they run on, or a new
# build installed (all those installed here with this run's [agros], a trial's alone: "lutris@a+b", only both), and pass
# saying upstream's next release doesn't fit where it names main: the line a test makes for it, lib.sh's ok_line;
# "crash": run.sh itself fails, naming none. $t/flaky: a trial's failure once only)
ahead "no longer fits main"; ahead x
ok_line test "2 left out" >"$t/main-line"
sed "s|@T@|$t|g" >"$t/repo/tests/run.sh" <<'S'
#!/bin/bash
echo "${*:-all}" >>@T@/ran
trap -p INT >>@T@/int
[[ " $BROKEN " != *" crash "* ]] || exit 3
agros=$(sed -n "s/^Server = //p" @T@/pacman.conf) arch=$(cat @T@/mirrorlist)
agros=${agros##*/}
if [[ $agros == built ]]; then inst=$(printf '%s\n' caelestia-cli caelestia-shell quickshell-git); else inst=$(cat @T@/installed 2>/dev/null); fi
for n in ${*:-hypr-api lutris}; do
    br=
    case " $BROKEN " in *" $n@$agros "* | *" $n@today "*) [[ -n $arch && " $BROKEN " != *" $n@always "* ]] || br=1 ;; esac
    for w in $BROKEN; do
        [[ $w == "$n@"* ]] || continue
        all=1
        for p in ${w#*@}; do grep -qx "$p" <<<"$inst" || all=; done
        [[ ${w#*@} != *+* ]] || { all=1; IFS=+ read -ra ps <<<"${w#*@}"; for p in "${ps[@]}"; do grep -qx "$p" <<<"$inst" || all=; done; }
        [[ -z $all ]] || br=1
    done
    if [[ -n $br && $agros != built && -e @T@/flaky ]]; then
        if [[ -e @T@/flaky-seen ]]; then br=; else touch @T@/flaky-seen; fi
    fi
    if [[ -n $br ]]; then echo "FAIL $n: broken"
    elif [[ " $BROKEN " == *" $n@main "* ]]; then sed "s/^ok test /ok $n /" @T@/main-line
    else echo "ok $n"; fi
done
S
chmod +x "$t/bin/"* "$t/repo/tests/run.sh"
# go <BROKEN> [<day>]: the result line, what ran (a line per pass, or trial: the tests it ran)
go() {
    rm -f "$t/ran" "$t/out" "$t/flaky-seen" "$t/failed-once" "$t/syncs"; : >"$t/mirrorlist"; : >"$t/installed"
    sed -i 's|^Server = .*|Server = https://example.invalid/old|' "$t/pacman.conf"
    # (the published repo's database signatures, as an earlier sync leaves them)
    mkdir -p "$t/sync"; touch "$t/sync/agros.db.sig" "$t/sync/agros.files.sig" "$t/sync/core.db"
    BROKEN=$1 AGROS_RETRY_WAIT=0 PATH=$t/bin:$PATH PACMAN_CONF=$t/pacman.conf PACMAN_SYNC=$t/sync MIRRORLIST=$t/mirrorlist GITHUB_OUTPUT=$t/out \
        AGROS_TEST_REPORT=$t/report "$t/repo/ci/test-passes.sh" file:///built https://example.invalid/published "${2:-}" \
        >/dev/null 2>&1 || true
    echo "$(grep '^result=' "$t/out") | $(paste -sd'|' "$t/ran")"
}
# holds: the hold= lines of the last go
holds() { sed -n '/^hold<<EOF$/,/^EOF$/p' "$t/out" | sed '1d;$d'; }
[[ $(go "") == "result=ok | all" ]] || fail "all passing: not ok: $(go "")"
# (no stale database signature left for the unsigned built repo: pacman refused its new database with the old .sig)
go "" >/dev/null
[[ ! -e $t/sync/agros.db.sig && ! -e $t/sync/agros.files.sig && -e $t/sync/core.db ]] ||
    fail "[agros]'s old database signatures left, or another repo's file taken: $(ls "$t/sync")"
# (the published [agros] fixes lutris: this run's AUR builds broke it; every test run again. Each new build installed
# here then tried alone, lutris alone run: none fails it, so not found which, every new build held (no hold= line))
[[ $(go "lutris@built") == "result=hold-agros | all|all|lutris|lutris|lutris" ]] || fail "broken by this run's [agros]: $(go "lutris@built")"
grep -q 'FAIL lutris' "$t/report" || fail "the report doesn't say what failed: $(cat "$t/report")"
[[ -z $(holds) ]] && grep -q '^    not found which one (each passes alone: .*): every new AUR build held$' "$t/report" ||
    fail "none found to have broken them, and not all held, said: $(holds) $(cat "$t/report")"
# Which one: Caelestia's new build breaks lutris (tried with Quickshell's, which it needs; twice), the others pass alone,
# then every test with them together: Caelestia held, with the meta package that needs it (not installed here); the CLI
# and Quickshell go out. Not the spicetify build the published one has, nor AgrOS's own
[[ $(go "lutris@caelestia-shell") == "result=hold-agros | all|all|lutris|lutris|lutris|lutris|all" ]] ||
    fail "the new build that broke them not looked for: $(go "lutris@caelestia-shell")"
[[ $(holds) == "caelestia-meta: it needs caelestia-shell's new build, held"$'\n'"caelestia-shell: its new build fails AgrOS's tests lutris (they pass with the published one)" ]] ||
    fail "not the new build that broke them held, with what needs it: $(holds)"
grep -q '^    caelestia-shell: fails lutris, twice$' "$t/report" && grep -q '^    held: caelestia-meta, caelestia-shell; the other new builds go out (every test passes with caelestia-cli quickshell-git)$' "$t/report" ||
    fail "which one broke them not in the report: $(cat "$t/report")"
# (Quickshell's broke it: Caelestia, tried with it, fails too: held as needing it)
go "lutris@quickshell-git" >/dev/null
[[ $(holds) == "caelestia-meta: it needs caelestia-shell's new build, held"$'\n'"caelestia-shell: it needs quickshell-git's new build, held"$'\n'"quickshell-git: its new build fails AgrOS's tests lutris (they pass with the published one)" ]] ||
    fail "a dependency that broke them: not held with what needs it: $(holds)"
# (only two together fail it, a failure that doesn't come again, too many to try, the others together failing: not
# found, every new build held)
for c in "lutris@caelestia-cli+quickshell-git|each passes alone" "flaky lutris@caelestia-shell|caelestia-shell's failed lutris, then passed: by chance" \
    "many lutris@caelestia-shell|3 new builds, more than AGROS_TRIALS=3 tries" \
    "lutris@caelestia-shell hypr-api@caelestia-cli+quickshell-git|the others together fail hypr-api"; do
    b=${c%%|*}; rm -f "$t/flaky"
    [[ $b != flaky\ * ]] || { touch "$t/flaky"; b=${b#flaky }; }
    if [[ $b == many\ * ]]; then r=$(AGROS_TRIALS=3 go "${b#many }"); else r=$(go "$b"); fi
    [[ $r == result=hold-agros\ * && -z $(holds) ]] && grep -qF "    not found which one (${c#*|}" "$t/report" ||
        fail "not found which one ($b), not said, or some held: $r $(holds) $(cat "$t/report")"
done
rm -f "$t/flaky"
# (one that passed on this run's [agros] fails on the published one, which a hold would put out beside this commit's
# own packages: an overlay changed for the new Caelestia, on the old one): not a hold
[[ $(go "hypr-api@built lutris@published") == "result=fail | all|all" ]] ||
    fail "a test failing only on the published [agros] not run before holding it: $(go "hypr-api@built lutris@published")"
# (broken on today's Arch, whatever [agros]; fine on the last good day's Arch)
[[ $(go "hypr-api@today" 2026/11/14) == "result=hold-upstream | all|all|all" ]] || fail "broken by an Arch update: $(go "hypr-api@today" 2026/11/14)"
grep -qx 'Server = https://archive.archlinux.org/repos/2026/11/14/$repo/os/$arch' "$t/mirrorlist" || fail "not on Arch's snapshot of that day: $(cat "$t/mirrorlist")"
[[ $(go "hypr-api@today hypr-api@always" 2026/11/14) == "result=fail | all|all|all" ]] || fail "AgrOS's own break not a failure"
[[ $(go "hypr-api@today") == "result=fail | all|all" ]] || fail "no last good day: not a failure"
grep -q '^    !! no day Arch last passed on .*: not known which side' "$t/report" || fail "no last good day not said: $(cat "$t/report")"
# (run.sh failing with no test named (runuser refused, run.sh cut off): not "all passed", which approves Hyprland)
[[ $(go crash) == "result=fail | all" ]] || fail "the tests not run read as all passed: $(go crash)"
# (upstream's next release not fitting: no failure, said in the report once, after what failed, whatever the result)
[[ $(go "lutris@main") == "result=ok | all" ]] || fail "upstream's main not fitting: not ok: $(go "lutris@main")"
grep -qx '    AHEAD lutris: no longer fits main; x' "$t/report" || fail "upstream's main not fitting not in the report: $(cat "$t/report")"
[[ $(go "lutris@main hypr-api@built") == "result=hold-agros | all|all|hypr-api|hypr-api|hypr-api" ]] || fail "with upstream's main not fitting: $(go "lutris@main hypr-api@built")"
[[ $(grep -c AHEAD "$t/report") == 1 && $(tail -n1 "$t/report") == "    AHEAD lutris: no longer fits main; x" ]] ||
    fail "upstream's main not said once, at the end: $(cat "$t/report")"
[[ $(go "lutris@main hypr-api@today hypr-api@always" 2026/11/14) == "result=fail | all|all|all" ]] ||
    fail "AgrOS's own break not a failure with a test saying upstream's main doesn't fit"
# (a pass that couldn't install, a download failed: nothing out, and said in the report, not read as AgrOS's code)
[[ $(PACFAIL=published go "lutris@built") == "result=fail | all" ]] ||
    fail "the published [agros] not installing: not a failure: $(PACFAIL=published go "lutris@built")"
grep -q "^    !! the published \[agros\] didn't install: not known which side" "$t/report" ||
    fail "an install that failed not in the report: $(cat "$t/report")"
# (a download that failed once, the archive's or the published [agros]'s: tried again, the pass run; the archive's
# without pacman's download timeout, which its slow answers tripped. Failing every time: tried three times, stopped)
[[ $(PACFAIL=published:once go "lutris@built") == "result=hold-agros | all|all|lutris|lutris|lutris" ]] ||
    fail "the published [agros] failing once: not tried again: $(PACFAIL=published:once go "lutris@built")"
[[ $(PACFAIL=archive:once go "hypr-api@today" 2026/11/14) == "result=hold-upstream | all|all|all" ]] ||
    fail "Arch's archive failing once: not tried again: $(PACFAIL=archive:once go "hypr-api@today" 2026/11/14)"
grep -q '^archive .*--disable-download-timeout' "$t/syncs" || fail "the archive's sync with pacman's download timeout: $(cat "$t/syncs")"
[[ $(PACFAIL=archive go "hypr-api@today" 2026/11/14) == "result=fail | all|all" && $(grep -c '^archive ' "$t/syncs") == 3 ]] ||
    fail "Arch's archive failing each time: not tried three times, then stopped: $(cat "$t/syncs")"
# (not in a background job, which starts with Ctrl+C ignored: dotfiles-sync-edge's Ctrl+C then never reached the sync)
[[ ! -s $t/int ]] || fail "the tests ran with Ctrl+C ignored: $(sort -u "$t/int")"
echo "ok ci-test-passes"

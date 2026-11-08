#!/usr/bin/env bash
# setup's pkg_install: repo packages from pacman, the rest from the AUR helper, and a name in neither said and left out
# (paru refused the whole batch for it: Faugus not installed with cachyos-gaming-meta missing on Arch); the apps step's
# gaming entry: CachyOS's meta package where its repos have it, Arch's own packages for it where not
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$t/bin"
# pacman -Si: the names in $REPO; paru -Si: those in $AUR; -S of either noted; sudo runs it
cat >"$t/bin/pacman" <<EOF
#!/bin/sh
case \$1 in
    -Si) case " \$REPO " in *" \$2 "*) exit 0 ;; esac; exit 1 ;;
    -S) shift; echo "pacman \$*" >>"$t/calls" ;;
esac
EOF
cat >"$t/bin/paru" <<EOF
#!/bin/sh
case \$1 in
    -Si) [ -z "\$AUR_DOWN" ] || exit 1; case " \$AUR " in *" \$2 "*) exit 0 ;; esac; exit 1 ;;
    -S) shift; echo "paru \$*" >>"$t/calls" ;;
esac
EOF
printf '#!/bin/sh\nexec "$@"\n' >"$t/bin/sudo"
# curl: the AUR's information service answering, unless $AUR_DOWN
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ -z "$AUR_DOWN" ]\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH REPO="steam wine" AUR="faugus-launcher"
run() { repo=$here yes=true bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/40-apps.sh"; "${@:2}"' _ "$here" "$@" 2>&1; }

# One name in neither (cachyos-gaming-meta on Arch): said, left out, the rest installed (Faugus from the AUR too)
out=$(run pkg_install steam cachyos-gaming-meta faugus-launcher) && fail "a package in neither reported success"
[[ $out == *"Not in the repos nor the AUR: cachyos-gaming-meta"* ]] || fail "the missing package not said: $out"
{ grep -q "^pacman --needed --noconfirm steam$" "$t/calls" && grep -q "^paru --needed --noconfirm faugus-launcher$" "$t/calls"; } ||
    fail "the rest not installed: $(cat "$t/calls")"
grep -q cachyos-gaming-meta "$t/calls" && fail "the missing package passed on to install: $(cat "$t/calls")"
# The AUR out of reach (every name answers "not found"): said so, not called missing
: >"$t/calls"
out=$(AUR_DOWN=1 run pkg_install steam faugus-launcher) && fail "the AUR out of reach reported success"
[[ $out == *"Couldn't reach the AUR (offline?): not installed this time: faugus-launcher"* && $out != *"Not in the repos"* ]] ||
    fail "the AUR out of reach not said as such: $out"

# The gaming entry: on Arch, Wine, umu (Faugus runs games with it) and the rest instead of the meta package
out=$(run eval 'printf "%s\n" "${APPS[@]//@gaming-meta@/$(gaming_meta)}"' | grep '^CachyOS gaming')
[[ $out == *" wine winetricks "*"umu-launcher"*"faugus-launcher"* && $out != *cachyos-gaming-meta* && $out != *@* ]] ||
    fail "the gaming entry on Arch: $out"
out=$(REPO="cachyos-gaming-meta" run eval 'printf "%s\n" "${APPS[@]//@gaming-meta@/$(gaming_meta)}"' | grep '^CachyOS gaming')
[[ $out == *" cachyos-gaming-meta "* && $out != *umu-launcher* ]] || fail "the gaming entry on CachyOS: $out"
# The VMware entry: the headers of every installed kernel (DKMS builds its modules against them), no placeholder left
out=$(run eval 'printf "%s\n" "${APPS[@]//@kernel-headers@/$(kernel_headers)}"' | grep '^VMware')
for f in /usr/lib/modules/*/pkgbase; do
    [[ ! -f $f || $out == *" $(<"$f")-headers"* ]] || fail "the VMware entry lacks $(<"$f")-headers: $out"
done
[[ $out != *@* ]] || fail "the VMware entry kept its placeholder: $out"

# Phone Link: adb with the phone's USB device open to you (android-udev's rules), not only to root
[[ $(run eval 'printf "%s\n" "${APPS[@]}"' | grep '^Phone Link') == *"|scrcpy android-tools android-udev|"* ]] ||
    fail "Phone Link without android-udev: adb can't reach the phone as you"

# Adding Flathub failing (offline, Flathub down) is said, not the end of the step under set -e (the apps after it, the
# printing and VMware services, not set up)
bad=$(grep -n 'flatpak remote-add' "$here"/setup/modules/*.sh | grep -v '|| *$' || true)
[[ -z $bad ]] || fail "a flatpak remote-add whose failure stops the step: $bad"

# Every package the apps step names is still in the repos or the AUR (the real ones: a rename upstream shows here, not
# as a failed install). Needs the network for the AUR
names=$(run eval 'for e in "${APPS[@]}"; do IFS="|" read -r _ p _ <<<"$e"; echo "$p"; done' | tr ' ' '\n' | grep -v '^@\|^$' | sort -u)
aur=()
for p in $names; do /usr/bin/pacman -Si "$p" >/dev/null 2>&1 || aur+=("$p"); done
helper=$(command -v /usr/bin/paru /usr/bin/yay 2>/dev/null | head -1) || true
if [[ -z $helper ]] || ! /usr/bin/curl -fsI --max-time 10 https://aur.archlinux.org >/dev/null 2>&1; then
    echo "ok setup-packages (SKIPPED: the AUR names: no AUR helper or no network)"; exit 0
fi
gone=()
for p in "${aur[@]}"; do "$helper" -Si --aur "$p" >/dev/null 2>&1 || gone+=("$p"); done
((${#gone[@]} == 0)) || fail "the apps step names packages in neither the repos nor the AUR: ${gone[*]}"
echo "ok setup-packages"

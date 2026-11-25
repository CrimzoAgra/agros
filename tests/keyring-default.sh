#!/usr/bin/env bash
# keyring-default: the passwords of another default keyring ("Default keyring", its own password) moved into "login"
# (those it hasn't already), then "login" made the default; nothing done when it's the default already, or isn't
# unlocked (the login screen's PAM lines missing); a keyring whose unlock prompt was cancelled left as it is, and "login"
# not made the default (asked again next login). With a stand-in secretstorage (no D-Bus here)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
check() {  # <case>: what the keyring service was asked, one line each
    python3 -I - "$here/.local/bin/keyring-default" "$1" <<'P'
import importlib.machinery, importlib.util, sys, types
case = sys.argv[2]
LOGIN = "/org/freedesktop/secrets/collection/login"
calls = []


class Item:
    def __init__(self, label, attrs, secret=b"s"):
        self.label, self.attrs, self.secret = label, attrs, secret
    def get_label(self): return self.label
    def get_attributes(self): return dict(self.attrs)
    def get_secret(self): return self.secret
    def get_secret_content_type(self): return "text/plain"


class Col:
    def __init__(self, path, items, locked=False, cancel=False):
        self.collection_path, self.items, self.locked, self.cancel = path, items, locked, cancel
    def is_locked(self): return self.locked
    def unlock(self):
        calls.append(f"unlock {self.collection_path.rsplit('/', 1)[1]}")
        self.locked = self.cancel
        return self.cancel  # (secretstorage: True when the prompt was dismissed)
    def get_all_items(self): return list(self.items)
    def create_item(self, label, attrs, secret, replace=False, content_type=""):
        calls.append(f"create {self.collection_path.rsplit('/', 1)[1]} {label} {secret.decode()}")


login = Col(LOGIN, [Item("kept", {"a": "1"})], locked=case == "login-locked")
other = Col("/org/freedesktop/secrets/collection/Default_5fkeyring",
            [Item("kept", {"a": "1"}), Item("moved", {"b": "2"}, b"pw")],
            locked=case in ("other-locked", "cancelled"), cancel=case == "cancelled")
session = Col("/org/freedesktop/secrets/collection/session", [Item("temp", {})])
default = LOGIN if case == "already" else other.collection_path


class Service:
    def __init__(self, *a): pass
    def call(self, method, sig, *args):
        if method == "ReadAlias":
            return (default,)
        calls.append(f"{method} {' '.join(args)}")


ss = types.ModuleType("secretstorage")
ss.dbus_init = lambda: None
ss.util = types.SimpleNamespace(DBusAddressWrapper=Service)
ss.defines = types.SimpleNamespace(SS_PREFIX="org.freedesktop.Secret.")
ss.get_all_collections = lambda bus: [login, other, session]
sys.modules["secretstorage"] = ss
loader = importlib.machinery.SourceFileLoader("kd", sys.argv[1])
kd = importlib.util.module_from_spec(importlib.util.spec_from_loader("kd", loader))
loader.exec_module(kd)
import contextlib, io
with contextlib.redirect_stdout(io.StringIO()):
    kd.main()
print("\n".join(calls))
P
}
moved=$'create login moved pw\nSetAlias default /org/freedesktop/secrets/collection/login'
[[ $(check move) == "$moved" ]] || fail "another default keyring: $(check move)"
[[ $(check other-locked) == $'unlock Default_5fkeyring\n'"$moved" ]] || fail "a locked one, unlocked: $(check other-locked)"
[[ $(check cancelled) == "unlock Default_5fkeyring" ]] || fail "its prompt cancelled: $(check cancelled)"
[[ -z $(check already) ]] || fail "login the default already: $(check already)"
[[ -z $(check login-locked) ]] || fail "login not unlocked: $(check login-locked)"
echo "ok keyring-default"

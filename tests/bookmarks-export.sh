#!/usr/bin/env bash
# firefox-bookmarks-export on a made-up LibreWolf profile: folders and escaping, a profile kept elsewhere (full path),
# and an empty profile writes nothing
set -euo pipefail
. "$(dirname "$0")/lib.sh"
prof=$t/.config/librewolf/librewolf/test.default
mkdir -p "$prof"
printf '[Profile0]\nName=default\nPath=test.default\nDefault=1\n' >"$t/.config/librewolf/librewolf/profiles.ini"
db() { python3 - "$prof/places.sqlite" "$1" <<'P'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT);
CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INT, fk INT, parent INT, position INT, title TEXT,
                            dateAdded INT, lastModified INT, guid TEXT);
INSERT INTO moz_bookmarks VALUES (1,2,NULL,0,0,'',0,0,'root________'), (2,2,NULL,1,0,'menu',0,0,'menu________'),
  (3,2,NULL,1,1,'toolbar',0,0,'toolbar_____'), (4,2,NULL,1,2,'unfiled',0,0,'unfiled_____');
""")
if sys.argv[2] == "full":
    db.executescript("""
    INSERT INTO moz_places VALUES (1,'https://a.example/?x=1&y="2"'), (2,'https://b.example/');
    INSERT INTO moz_bookmarks VALUES (5,1,1,3,0,'Tom & Jerry',1000000,0,'a'), (6,2,NULL,3,1,'Games',0,0,'b'),
      (7,1,2,6,0,'Inside',0,0,'c');
    """)
db.commit()
P
}
out=$t/bookmarks.html
db full
HOME=$t "$here/.local/bin/firefox-bookmarks-export" "$out" >/dev/null
# --profile (setup and dotfiles-sync): the same profile, here only marked Default=1 (no [Install] section)
[[ $(HOME=$t "$here/.local/bin/firefox-bookmarks-export" --profile) == "$prof" ]] || fail "--profile found another profile"
(cd "$t" && HOME=$t "$here/.local/bin/firefox-bookmarks-export" plain.html >/dev/null) && [[ -s $t/plain.html ]] || fail "a bare file name as the output wasn't written"
[[ $(HOME=$t "$here/.local/bin/firefox-bookmarks-export" --help 2>&1) == *"--profile"* && ! -e ./--help ]] || fail "--help not the usage"
grep -q 'HREF="https://a.example/?x=1&amp;y=&quot;2&quot;"' "$out" || fail "URL not escaped"
grep -q '>Tom &amp; Jerry</A>' "$out" || fail "title not escaped"
grep -A2 '<H3[^>]*>Games</H3>' "$out" | grep -q 'b.example' || fail "folder lost its bookmark"
grep -q 'Other Bookmarks' "$out" && fail "empty Other Bookmarks folder written"
# Not a UTF-8 locale (Python's own UTF-8 mode off): written as UTF-8 all the same, as the file says it is (it failed on
# the first accented title)
python3 - "$prof/places.sqlite" <<'P'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("UPDATE moz_bookmarks SET title = 'Ação' WHERE id = 7")
db.commit()
P
LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 HOME=$t "$here/.local/bin/firefox-bookmarks-export" "$t/latin.html" >/dev/null ||
    fail "an accented title stopped the export outside a UTF-8 locale"
grep -q '>Ação</A>' "$t/latin.html" || fail "the accented title not written as UTF-8"
# A profile kept elsewhere (IsRelative=0): profiles.ini names it by its full path
ini=$t/.config/librewolf/librewolf/profiles.ini
mv "$prof" "$t/elsewhere"; cp "$ini" "$t/ini"
printf '[Profile0]\nName=default\nIsRelative=0\nPath=%s\nDefault=1\n' "$t/elsewhere" >"$ini"
HOME=$t "$here/.local/bin/firefox-bookmarks-export" "$t/out2" >/dev/null 2>&1 || fail "a profile kept elsewhere wasn't found"
mv "$t/elsewhere" "$prof"; mv "$t/ini" "$ini"

rm "$prof/places.sqlite"; db empty; cp "$out" "$t/before"
if HOME=$t "$here/.local/bin/firefox-bookmarks-export" "$out" 2>/dev/null; then fail "empty profile reported success"; fi
cmp -s "$out" "$t/before" || fail "empty profile replaced the bookmarks"
rm "$prof/places.sqlite"
if HOME=$t "$here/.local/bin/firefox-bookmarks-export" "$out" 2>/dev/null; then fail "missing database reported success"; fi
echo "ok bookmarks-export"

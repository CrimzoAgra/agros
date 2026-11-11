#!/usr/bin/env bash
# The desktop widgets' weather location field: suggestions as you type (open-meteo's geocoding search, a quarter
# second after the last key, older replies dropped), each "City, region, country" (placeLabel run by node; a region
# named as the city left out), a pick saved as "lat,lon" with its name kept for the tab, and Escape closing the
# suggestions before it cancels. The workings in common/PlacePicker.qml (Caelestia's settings use the same), the field in
# the widget
set -euo pipefail
. "$(dirname "$0")/lib.sh"
qml=$here/.config/quickshell/widgets/shell.qml
pick=$here/.config/quickshell/common/PlacePicker.qml
# shellcheck disable=SC2016  # (QML's own ${...}, matched as written)
{ grep -q 'geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=20' "$pick" &&
    grep -A2 'id: suggestDelay' "$qml" | grep -q 'interval: 250' &&
    grep -q 'if (id !== root.suggestId)' "$pick" &&
    grep -q 'const loc = `${Number(p.latitude).toFixed(4)},${Number(p.longitude).toFixed(4)}`;' "$pick" &&
    grep -q 'fetchForecast(id, root.places.name, coords\[0\], coords\[1\]);' "$qml" &&
    grep -q 'name: root.townName(p)' "$pick" &&
    grep -A1 'if (loc === root.location)' "$pick" | grep -q 'root.changed();' &&
    grep -A2 'function onChanged(): void {' "$qml" | grep -q 'root.fetchWeather();' &&
    grep -q 'Keys.onEscapePressed: root.places.suggestions.length > 0 ? cityEdit.closeSuggestions() : cityEdit.finish(false)' "$qml"; } ||
    fail "the location suggestions not wired as they should be"
# A new list of suggestions (a reply for what's typed now) drops the pick made in the one before: Enter then takes what's
# typed, not whichever place came to sit at that row
grep -A3 'function onSuggestionsChanged(): void {' "$qml" | grep -q 'cityEdit.picked = -1;' ||
    fail "a pick kept over a new list of suggestions"
# ...nor one from a list for an earlier text, still on screen while the new one is on its way (or never comes, offline):
# Up/Down and Enter use the list only while it's for what's typed
{ [[ $(grep -c 'root.places.suggestedFor === text.trim()' "$qml") == 2 ]] &&
    grep -q 'if (picked >= 0 && suggestions\[picked\] && suggestedFor === text.trim())' "$pick" &&
    grep -q 'root.places.apply(field.text, picked);' "$qml" &&
    grep -q 'root.suggestedFor = q;' "$pick"; } || fail "a suggestion for an earlier text can be picked"
# A picked place's name read after its forecast was asked for (at login): asked again, so the tab shows the name, not
# the coordinates, until the next refresh half an hour later
sed -n '/id: placeNamesFile/,/^    }/p' "$pick" | grep -q 'root.changed();' ||
    fail "the place names read after the first forecast was asked for leave the tab named by coordinates"
command -v node >/dev/null || { echo "ok widgets-location (SKIPPED: no node to run placeLabel)"; exit 0; }
fn=$(sed -n '/^    function placeLabel(p: var): string {$/,/^    }$/p' "$pick" | sed 's/(p: var): string {/(p) {/')
[[ -n $fn ]] || fail "placeLabel not found"
out=$(node -e "$fn
console.log(placeLabel({ name: 'Lisbon', admin1: 'Lisbon', country: 'Portugal' }));
console.log(placeLabel({ name: 'Lisbon', admin1: 'Ohio', country: 'United States' }));
console.log(placeLabel({ name: 'Nowhere', country: 'Somewhere' }));")
[[ $out == $'Lisbon, Portugal\nLisbon, Ohio, United States\nNowhere, Somewhere' ]] || fail "placeLabel said: $out"
# Towns only (GeoNames' feature code), and an area's seat named "<area> <one word>" named as the area, the same rule
# for every country: real longer names and a city's parts kept (cases from open-meteo's real answers)
fns=$(for f in towns townName; do sed -n "/^    function $f(.*: var): .* {\$/,/^    }\$/p" "$pick" | sed -E 's/\((results|p): var\): (var|string) \{/(\1) {/'; done)
[[ $(grep -c '^    function' <<<"$fns") == 2 ]] || fail "towns/townName not found"
out=$(node -e "$fns
const t = (name, feature_code, a = {}) => townName(Object.assign({ name, feature_code }, a));
console.log([
  t('Matosinhos Municipality', 'PPLA2', { admin2: 'Porto', admin3: 'Matosinhos' }),
  t('Querétaro City', 'PPLA', { admin2: 'Querétaro' }),
  t('Frankfurt am Main', 'PPLA3', { admin4: 'Frankfurt' }),
  t('Santiago de los Caballeros', 'PPLA', { admin3: 'Santiago' }),
  t('Stuttgart Feuerbach', 'PPLX', { admin4: 'Stuttgart' }),
  t('Budapest II. kerület', 'PPLX', { admin2: 'Budapest II.' }),
  t('Lisbon', 'PPLC', { admin2: 'Lisbon' }),
  t('Mexico City', 'PPLC', { admin1: 'Mexico City' })
].join('|'));
console.log(towns([{ name: 'Romania', feature_code: 'PCLI' }, { name: 'Roma', feature_code: 'PPLA2' }, { name: 'Tōkyō Zan', feature_code: 'MT' }, { name: 'X Airport', feature_code: 'AIRP' }]).map(p => p.name).join('|'));")
[[ $out == $'Matosinhos|Querétaro|Frankfurt am Main|Santiago de los Caballeros|Stuttgart Feuerbach|Budapest II. kerület|Lisbon|Mexico City\nRoma' ]] ||
    fail "towns/townName said: $out"
# Regions without their kind, one rule for every country; only directions or kinds left: whole (real region names)
fn=$(sed -n '/^    function regionName(s: var): string {$/,/^    }$/p' "$pick" | sed 's/(s: var): string {/(s) {/')
[[ -n $fn ]] || fail "regionName not found"
out=$(node -e "$fn
console.log(['Porto District', 'Moscow Oblast', 'Canton of Bern', 'Canton Ticino', 'Departamento de Bolívar',
  'Jakarta Special Capital Region', 'National Capital Territory of Delhi', 'Khanty-Mansiysk Autonomous Okrug', 'Bavaria',
  'New York', 'Western Province', 'National Capital Region', 'Free State', undefined].map(regionName).join('|'));")
[[ $out == 'Porto|Moscow|Bern|Ticino|Bolívar|Jakarta|Delhi|Khanty-Mansiysk|Bavaria|New York|Western Province|National Capital Region|Free State|' ]] ||
    fail "regionName said: $out"
grep -q 'admin1: root.regionName(p.admin1)' "$pick" || fail "the suggestions' regions not shortened"
echo "ok widgets-location"

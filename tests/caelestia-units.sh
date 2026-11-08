#!/usr/bin/env bash
# Caelestia's units as the desktop widget has them, not by the locale: its "Auto" weather unit is Fahrenheit for
# en_GB (Qt counts the UK as imperial) and its clock follows the locale. Set in the repo's shell.json (setup installs
# it; a change you make in Caelestia's settings goes back to the repo by dotfiles-sync): °C for weather and sensors,
# 24-hour clock. Where Caelestia is installed, those are names its enums still have
set -euo pipefail
. "$(dirname "$0")/lib.sh"
json=$here/.config/caelestia/shell.json
[[ $(jq -r '.services | "\(.weatherUnits) \(.sensorUnits) \(.clockFormat)"' "$json") == "Celsius Celsius TwentyFourHour" ]] ||
    fail "shell.json doesn't set °C and a 24-hour clock: $(jq -c .services "$json")"
types=/usr/lib/qt6/qml/Caelestia/Config/caelestia-config.qmltypes
[[ -f $types ]] || { echo "ok caelestia-units (SKIPPED: Caelestia not installed, its names not checked)"; exit 0; }
for p in weatherUnits sensorUnits clockFormat; do
    grep -q "name: \"$p\"" "$types" || fail "Caelestia's config has no services.$p any more"
done
grep -A10 '"caelestia::config::TemperatureUnit"' "$types" | grep -q '"Celsius"' || fail "Caelestia's TemperatureUnit has no Celsius"
grep -A10 '"caelestia::config::ClockFormat"' "$types" | grep -q '"TwentyFourHour"' || fail "Caelestia's ClockFormat has no TwentyFourHour"
echo "ok caelestia-units"

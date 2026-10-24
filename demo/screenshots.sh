#!/bin/bash
# Retakes screenshots/*.png and preview.png with the demo data.
#
# Swaps the demo data in for your own hours.json while it runs and puts your
# file back afterwards, also when interrupted. The shell restarts a few times
# and the panel opens on its own; don't touch it until the script is done.
#   demo/screenshots.sh
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
data="$HOME/.local/share/on-the-clock/hours.json"
cache="$HOME/.cache/on-the-clock-demo/events.json"
id=s-curve.on-the-clock
work=$(mktemp -d)

restore() {
  cp "$work/Panel.qml" "$here/Panel.qml"
  if [[ -f $work/hours.json ]]; then
    cp "$work/hours.json" "$data"
    cmp -s "$work/hours.json" "$data" && echo "your data is back" || echo "RESTORE FAILED: your data is in $work/hours.json"
  fi
  omarchy-restart-shell >/dev/null 2>&1 || true
}
trap restore EXIT

node "$here/demo/make-demo.js"
mkdir -p "$(dirname "$cache")" "$here/screenshots"
cp "$here/demo/out/events.json" "$cache"
cp "$here/Panel.qml" "$work/Panel.qml"
[[ -f $data ]] && cp "$data" "$work/hours.json"
cp "$here/demo/out/hours.json" "$data"

output=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')

# shot <name> <tab> [bottom]
shot() {
  cp "$work/Panel.qml" "$here/Panel.qml"
  sed -i "s/property string tab: \"week\"/property string tab: \"$2\"/" "$here/Panel.qml"
  if [[ ${3:-} == bottom ]]; then
    sed -i 's/^\( *\)onContentYChanged: root.scrolled()$/&\n\1Timer { interval: 300; running: true; repeat: true; onTriggered: scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height) }/' "$here/Panel.qml"
  fi
  omarchy-restart-shell >/dev/null 2>&1
  sleep 5
  omarchy-shell shell summon "$id" '{}' >/dev/null
  sleep 2
  grim -o "$output" "$work/full.png"
  omarchy-shell shell hide "$id" >/dev/null
  local geometry
  geometry=$(magick "$work/full.png" ppm:- | node "$here/demo/find-panel.js")
  magick "$work/full.png" -crop "$geometry" +repage -resize '1200x>' -strip "$here/screenshots/$1.png"
  echo "screenshots/$1.png"
}

shot week week
shot overview overview
shot calendar calendar
shot admin admin
shot admin-settings admin bottom
cp "$here/screenshots/overview.png" "$here/preview.png"

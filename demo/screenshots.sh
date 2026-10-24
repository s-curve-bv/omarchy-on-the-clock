#!/bin/bash
# Retakes screenshots/*.png and preview.png with the demo data, or writes
# them to another folder for a look before they go into the repo.
#
# Uses the plugin's demo mode, so your own hours.json is never touched. The
# shell restarts a few times and the panel opens on its own; don't touch it
# until the script is done. The shell is back on your data afterwards.
#   demo/screenshots.sh [output-folder]
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
shots=${1:-$here/screenshots}
id=s-curve.on-the-clock
work=$(mktemp -d)

restore() {
  cp "$work/Panel.qml" "$here/Panel.qml"
  cp "$work/AdminView.qml" "$here/AdminView.qml"
  omarchy-restart-shell >/dev/null 2>&1 || true
}
trap restore EXIT

mkdir -p "$shots"
cp "$here/Panel.qml" "$work/Panel.qml"
cp "$here/AdminView.qml" "$work/AdminView.qml"

output=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')

# shot <name> <tab> [bottom | edit]
shot() {
  cp "$work/Panel.qml" "$here/Panel.qml"
  cp "$work/AdminView.qml" "$here/AdminView.qml"
  sed -i "s/property string tab: \"week\"/property string tab: \"$2\"/" "$here/Panel.qml"
  if [[ ${3:-} == bottom ]]; then
    sed -i 's/^\( *\)onContentYChanged: root.scrolled()$/&\n\1Timer { interval: 300; running: true; repeat: true; onTriggered: scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height) }/' "$here/Panel.qml"
  fi
  if [[ ${3:-} == edit ]]; then
    sed -i 's/property string editingProject: ""/property string editingProject: "p2"/' "$here/AdminView.qml"
  fi
  omarchy-restart-shell >/dev/null 2>&1
  sleep 5
  omarchy-shell ontheclock demo quiet >/dev/null
  sleep 1
  omarchy-shell shell summon "$id" '{}' >/dev/null
  sleep 2
  grim -o "$output" "$work/full.png"
  omarchy-shell shell hide "$id" >/dev/null
  sleep 1
  grim -o "$output" "$work/closed.png"
  magick "$work/full.png" "$work/open.ppm"
  magick "$work/closed.png" "$work/closed.ppm"
  local geometry
  geometry=$(node "$here/demo/find-panel.js" "$work/open.ppm" "$work/closed.ppm")
  magick "$work/full.png" -crop "$geometry" +repage -resize '1200x>' -strip "$shots/$1.png"
  echo "$shots/$1.png"
}

shot week week
shot overview overview
shot calendar calendar
shot admin admin
shot admin-edit admin edit
shot admin-settings admin bottom
if [[ -z ${1:-} ]]; then cp "$shots/overview.png" "$here/preview.png"; fi

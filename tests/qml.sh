#!/bin/bash
# Runs the QML tests (tests/qml/tst_*.qml) headless: the real Service and
# Week view with Omarchy's own UI modules, and stand-ins for Quickshell
# (tests/qml/fakes) with an in-memory file system.
#   tests/qml.sh [omarchy-shell-dir]   (default /usr/share/omarchy/shell)
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
shell=$(cd "${1:-/usr/share/omarchy/shell}" && pwd)
runner=$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
ln -s "$shell" "$root/qs"

QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
  "$runner" -import "$here/tests/qml/fakes" -import "$root" -input "$here/tests/qml"

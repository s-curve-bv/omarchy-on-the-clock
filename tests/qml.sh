#!/bin/bash
# Runs the QML tests (tests/qml/tst_*.qml) headless: the real Service, Week
# and Admin views with Omarchy's own UI modules, and stand-ins for Quickshell
# (tests/qml/fakes) with an in-memory file system.
#   tests/qml.sh [omarchy-shell-dir]   (default /usr/share/omarchy/shell)
# Always offscreen, so no test window opens or takes focus, whatever your
# session's QT_QPA_PLATFORM says. QML_TEST_PLATFORM=wayland to watch them.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
shell=$(cd "${1:-/usr/share/omarchy/shell}" && pwd)
runner=$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
ln -s "$shell" "$root/qs"

QT_QPA_PLATFORM=${QML_TEST_PLATFORM:-offscreen} \
  "$runner" -import "$here/tests/qml/fakes" -import "$root" -input "$here/tests/qml"

#!/bin/bash
# Lints all QML against the real Omarchy shell (qs.Ui, qs.Commons) and
# Quickshell modules. Omarchy's style objects (Style.spacing, Style.font)
# and Loader items are untyped, so lookups on them are reported as missing
# on QObject; those are the only warnings allowed through.
#   tests/lint.sh [omarchy-shell-dir] [extra import dirs...]
# CI has no Quickshell installed and passes tests/qml/fakes as extra import;
# with extra imports the installed Quickshell is hidden, so a local run
# behaves exactly like CI.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
shell=$(cd "${1:-/usr/share/omarchy/shell}" && pwd)
extra=()
for dir in "${@:2}"; do extra+=(-I "$(cd "$dir" && pwd)"); done
qmllint=$(command -v qmllint6 || command -v qmllint || echo /usr/lib/qt6/bin/qmllint)

# The shell resolves "qs.Ui" to <shell>/Ui; give qmllint the same layout.
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
ln -s "$shell" "$root/qs"

if (( ${#extra[@]} )); then
  # Qt's own modules without Quickshell, instead of the default import path.
  qt=$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/qt6/qml)
  mkdir "$root/qt"
  for module in "$qt"/*; do [[ $(basename "$module") == Quickshell ]] || ln -s "$module" "$root/qt/"; done
  extra=(--bare "${extra[@]}" -I "$root/qt")
fi

out=$("$qmllint" "${extra[@]}" -I "$root" "$here"/*.qml 2>&1 || true)
problems=$(grep -E "^(Warning|Error):" <<<"$out" \
  | grep -vE "not found on type (\"QObject\"|.* with type QObject) \[missing-property\]" || true)

if [[ -n $problems ]]; then
  echo "$problems"
  echo "lint: $(grep -c . <<<"$problems") problem(s)"
  exit 1
fi
files=("$here"/*.qml)
echo "ok: ${#files[@]} QML files lint clean"

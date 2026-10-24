#!/bin/bash
# backup.sh commits real data and refuses demo data.
#   bash tests/test_backup.sh
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null

echo '{"settings": {"backup": true}}' > "$dir/hours.json"
bash "$here/backup.sh" "$dir" >/dev/null
[[ $(git -C "$dir" rev-list --count HEAD) == 1 ]] || { echo "FAIL: real data was not committed"; exit 1; }

echo '{"settings": {"backup": true, "demo": true}}' > "$dir/hours.json"
if bash "$here/backup.sh" "$dir" 2>/dev/null; then
  echo "FAIL: backup.sh accepted demo data"; exit 1
fi
[[ $(git -C "$dir" rev-list --count HEAD) == 1 ]] || { echo "FAIL: demo data was committed"; exit 1; }
[[ $(git -C "$dir" show HEAD:hours.json) != *demo* ]] || { echo "FAIL: demo data in history"; exit 1; }

# A folder with only demo data must not even become a repository.
demo=$(mktemp -d)
echo '{"settings": {"demo": true}}' > "$demo/hours.json"
bash "$here/backup.sh" "$demo" 2>/dev/null && { echo "FAIL: demo folder accepted"; exit 1; }
[[ ! -e $demo/.git ]] || { echo "FAIL: git init ran on demo folder"; exit 1; }
rm -rf "$demo"

echo "ok: real data committed, demo data refused"

#!/bin/bash
# Commit hours.json in its own folder and push it when a remote is set up.
# Run by the service a few minutes after changes and once at startup.
#   backup.sh <data-dir> [remote-url]
# An empty remote keeps whatever origin the repository already has.
set -euo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

cd "$1"
remote="${2:-}"

# Never touch anything holding demo data (Demo.js marks it), whatever the
# caller thinks; checked before git runs at all.
if jq -e '.settings.demo == true' hours.json >/dev/null 2>&1; then
  echo "refusing to back up demo data" >&2
  exit 1
fi

[[ -d .git ]] || git init -q -b main
if ! git config user.email >/dev/null; then
  git config user.name "On the Clock"
  git config user.email "on-the-clock@localhost"
fi

if [[ -n $remote ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    [[ $(git remote get-url origin) == "$remote" ]] || git remote set-url origin "$remote"
  else
    git remote add origin "$remote"
  fi
fi

git add hours.json
git diff --cached --quiet || git commit -q -m "Backup $(date '+%F %H:%M')"

if git remote get-url origin >/dev/null 2>&1; then
  git push -q -u origin HEAD
  echo "pushed to $(git remote get-url origin)"
else
  echo "committed locally"
fi

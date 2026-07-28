#!/usr/bin/env bash
# Lint shell scripts with ShellCheck using repo .shellcheckrc (baseline).
# Usage: ./lint-shell.sh [path...]
# With no args, checks every tracked-looking *.sh outside .agents / .git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

command -v shellcheck >/dev/null || {
  echo "FAIL: shellcheck not found (e.g. brew install shellcheck / apt install shellcheck)" >&2
  exit 1
}

files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r f; do
    files+=("$f")
  done < <(find . -name '*.sh' -not -path './.agents/*' -not -path './.git/*' | sort)
fi

[[ ${#files[@]} -gt 0 ]] || {
  echo "FAIL: no shell scripts to lint" >&2
  exit 1
}

# .shellcheckrc is discovered automatically from the repo root.
# -S warning: infos (notes) that are not disabled stay out of the gate.
exec shellcheck -S warning "${files[@]}"

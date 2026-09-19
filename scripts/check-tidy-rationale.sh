#!/usr/bin/env bash
#
# Every check switched off in .clang-tidy has to be explained in
# docs/coding-style.md. This is what makes that a rule rather than a wish.
#
#   ./scripts/check-tidy-rationale.sh
#
# The failure it prevents is specific: a config that grows an exclusion at a
# time, each one added to get a build green, until nobody knows which of them
# still matter and the whole list becomes untouchable.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

readonly config=.clang-tidy
readonly document=docs/coding-style.md

[ -f "$config" ] || { echo "error: no $config" >&2; exit 1; }
[ -f "$document" ] || { echo "error: no $document" >&2; exit 1; }

missing=()
while read -r check; do
    grep -qF -- "$check" "$document" || missing+=("$check")
done < <(sed -n '/^Checks:/,/^[A-Za-z]/p' "$config" \
    | grep -oE '^  -[a-z][a-z0-9-]+' \
    | sed 's/^  -//')

if [ ${#missing[@]} -gt 0 ]; then
    echo "error: switched off in $config, not explained in $document:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo >&2
    echo "Write down why, or turn the check back on. A reason you cannot" >&2
    echo "write is a reason you do not have." >&2
    exit 1
fi

echo "Every exclusion in $config is explained in $document."

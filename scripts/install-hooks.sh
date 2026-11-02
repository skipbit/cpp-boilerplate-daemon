#!/usr/bin/env bash
#
# Points git at .githooks/, so that the checks CI runs also run before a commit.
#
#   ./scripts/install-hooks.sh
#
# Git deliberately does not run hooks that arrive with a clone - a repository
# you download should not be able to execute code on your machine - so this is
# opt-in and stays that way. The dev container runs it for you.
#
# To undo it: git config --unset core.hooksPath

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks

echo "Hooks installed: core.hooksPath -> .githooks"
echo
missing=()
for tool in clang-format clang-tidy actionlint shellcheck hadolint; do
    command -v "$tool" > /dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Not installed, so those checks will be skipped: ${missing[*]}"
    echo "The dev container in .devcontainer/ has all of them."
fi

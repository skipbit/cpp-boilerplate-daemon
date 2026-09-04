#!/usr/bin/env bash
#
# The one list of which files each checker applies to.
#
#   ./scripts/lint-paths.sh shellcheck
#
# Two things need this list, and they need it differently. The commit hook has
# a set of staged paths and wants the ones a checker cares about; CI has no such
# set and wants everything in the tree. Written out in both places, the two
# lists drift in the direction nobody notices - the hook checking an extension
# the CI job does not, so a file passes the commit and no job ever disagrees.
# That has happened here, with .h and .cc.
#
# Answered out of the index rather than by walking the tree: a file that is
# staged but not committed is already in the answer, one that is ignored never
# is, and a build directory full of generated copies cannot get in.

set -euo pipefail

case "${1:-}" in
    clang-format) git ls-files -- '*.cpp' '*.hpp' '*.h' '*.cc' ;;
    clang-tidy)   git ls-files -- '*.cpp' '*.cc' ;;
    shellcheck)   git ls-files -- '*.sh' '.githooks/*' ;;
    actionlint)   git ls-files -- '.github/workflows/*.yml' 'ci/*.yml' ;;
    hadolint)     git ls-files -- '*Dockerfile' ;;
    # Not files a checker is run on, but the files that decide whether it needs
    # running: check-tidy-rationale.sh reads both of them whole.
    tidy-rationale) git ls-files -- '.clang-tidy' 'docs/coding-style.md' ;;
    *)
        echo "usage: $0 <clang-format|clang-tidy|shellcheck|actionlint|hadolint|tidy-rationale>" >&2
        exit 2
        ;;
esac

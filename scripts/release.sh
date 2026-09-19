#!/usr/bin/env bash
#
# A release is a git tag. Everything else - the GitHub release, the notes, the
# archive - is produced from it by .github/workflows/release.yml.
#
#   ./scripts/release.sh --check v1.2.3   # does the tag match the source?
#   ./scripts/release.sh v1.2.3           # check, then create the tag
#
# The tag is the single source of truth for what a release is, and the version
# in CMakeLists.txt is what the built artefacts say about themselves. Those two
# can disagree, and a release where they do is a release nobody can trace. So
# they are compared - here before the tag exists, and again in CI after it
# does, by this same script. See docs/versioning.md.
#
# The tag is not pushed. Pushing it publishes a release, and that is a decision
# rather than a step.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

usage() {
    echo "usage: $0 [--check] <tag>   (tag looks like v1.2.3)" >&2
    exit 2
}

check_only=false
[ "${1:-}" = "--check" ] && { check_only=true; shift; }
tag=${1:-}
[ -n "$tag" ] || usage

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "'$tag' is not a release tag: expected vMAJOR.MINOR.PATCH"

# The first three-part version in CMakeLists.txt that is not the CMake one the
# file requires. project() is the only other place a version appears.
version=$(grep -v cmake_minimum_required CMakeLists.txt \
    | grep -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' \
    | head -1 | cut -d' ' -f2)
[ -n "$version" ] || die "no project version found in CMakeLists.txt"

if [ "${tag#v}" != "$version" ]; then
    die "tag $tag does not match the project version $version in CMakeLists.txt.
       Whichever is wrong, fix it before the release exists: edit project(VERSION)
       and commit, or choose the tag that matches."
fi

if $check_only; then
    echo "$tag matches project(VERSION $version)."
    exit 0
fi

[ -z "$(git status --porcelain)" ] \
    || die "the working tree is dirty; a tag should point at a committed state"
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
    die "$tag already exists"
fi

git tag -a "$tag" -m "$tag"

echo "Created $tag at $(git rev-parse --short HEAD)."
echo
echo "It is local. To publish the release:"
echo "  git push origin $tag"

#!/usr/bin/env bash
#
# Renames the service. Run once, when this becomes your project:
#
#   ./scripts/rename.sh yourservice
#   ./scripts/rename.sh yourservice --url https://github.com/you/yourservice
#   ./scripts/rename.sh yourservice --author "Your Name"
#
# Covers the namespace, the two targets, the generated version header, the name
# the program calls itself in its own messages, and the systemd unit - both the
# name of its template file and what is written inside it. The uppercase form
# (CMake options) follows automatically.
#
# The homepage in project() is covered too. Given no URL, the origin remote is
# used; with no usable origin either the line is deleted, because a missing
# homepage is honest and a wrong one is not.
#
# --author rewrites the copyright holder in LICENSE. It is never guessed: see
# where it is done, below.

set -euo pipefail

readonly old="mydaemon"
readonly OLD="MYDAEMON"

usage() {
    echo "usage: $0 <new-name> [--url URL] [--author NAME]" >&2
    echo "  <new-name>     lowercase, starting with a letter, e.g. tickd" >&2
    echo "  --url URL      the project homepage; taken from the origin remote if omitted" >&2
    echo "  --author NAME  rewrite the copyright holder in LICENSE, and the year with it" >&2
    exit 2
}

# Turns a git remote of any of the usual shapes into a browsable https URL.
# Fails, printing nothing, when it is not one of them.
homepage_from_remote() {
    local url=${1%.git}
    case "$url" in
        ssh://*)   url=${url#ssh://} ;;
        https://*) url=${url#https://} ;;
        http://*)  url=${url#http://} ;;
        git://*)   url=${url#git://} ;;
        *@*:*)     url=${url#*@}; url=${url/:/\/} ;;
        *)         return 1 ;;
    esac
    url=${url#*@}  # any user info that survived the scheme
    case "$url" in
        */*/*) printf 'https://%s\n' "$url" ;;
        *)     return 1 ;;
    esac
}

new=""
homepage=""
author=""
year=$(date +%Y)
readonly year

# One positional argument, the new name, because it is the only required one.
# Everything optional is a flag: this script is going to grow --description and
# whatever else a project needs stamped into it, and a second, third and fourth
# positional argument is a calling convention nobody can read at the call site.
while [ $# -gt 0 ]; do
    case "$1" in
        --url)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "error: --url needs a value" >&2
                usage
            fi
            homepage=$2
            shift 2
            ;;
        --author)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "error: --author needs a name" >&2
                usage
            fi
            author=$2
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        -*)
            echo "error: unknown option '$1'" >&2
            usage
            ;;
        *)
            if [ -n "$new" ]; then
                echo "error: unexpected argument '$1'" >&2
                usage
            fi
            new=$1
            shift
            ;;
    esac
done

[ -n "$new" ] || usage

if ! [[ "$new" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "error: '$new' must be lowercase and start with a letter" >&2
    usage
fi

if [ "$new" = "$old" ]; then
    echo "error: that is already the name" >&2
    exit 1
fi

if [ -n "$homepage" ] && ! [[ "$homepage" =~ ^https?://[^[:space:]]+$ ]]; then
    echo "error: '$homepage' is not an http(s) URL" >&2
    usage
fi

NEW=$(printf '%s' "$new" | tr '[:lower:]' '[:upper:]')

cd "$(dirname "$0")/.."

if ! grep -q "project(${old}" CMakeLists.txt; then
    echo "error: CMakeLists.txt does not declare project(${old}) - has this already been renamed?" >&2
    exit 1
fi

if [ -z "$homepage" ]; then
    origin=$(git config --get remote.origin.url 2>/dev/null || true)
    if [ -n "$origin" ]; then
        homepage=$(homepage_from_remote "$origin" || true)
    fi
fi

# Build directories are skipped: they hold generated copies that are about to be
# stale anyway.
mapfile -t files < <(
    grep -rl -e "$old" -e "$OLD" . \
        --exclude-dir=.git \
        --exclude-dir=build \
        --exclude-dir=out \
        --binary-files=without-match
)

if [ ${#files[@]} -gt 0 ]; then
    sed -i "s/${OLD}/${NEW}/g; s/${old}/${new}/g" "${files[@]}"
fi

# The homepage carries no occurrence of the old name, so it survives the
# substitution above and has to be handled on its own.
if [ -n "$homepage" ]; then
    sed -i "s|^\([[:space:]]*HOMEPAGE_URL[[:space:]]\).*|\1\"${homepage}\"|" CMakeLists.txt
else
    sed -i '/^[[:space:]]*HOMEPAGE_URL[[:space:]]/d' CMakeLists.txt
fi

# Only when asked for. Taking the name from git config would write whoever is
# sitting at this machine onto a repository that may be published under an
# organisation's name, and a confidently wrong attribution is harder to notice
# than the template author's name still being there. 0BSD requires no
# attribution, so the cost of leaving it alone is that it looks wrong, not that
# it is a licence problem.
if [ -n "$author" ]; then
    grep -q '^Copyright (c) ' LICENSE \
        || { echo "error: LICENSE has no copyright line to rewrite" >&2; exit 1; }
    # Through the environment rather than awk -v: awk expands backslash escapes
    # in a -v value, and a person's name is not an escape sequence.
    CPPBP_COPYRIGHT="Copyright (c) ${year} ${author}" \
        awk '/^Copyright \(c\) / && !seen { print ENVIRON["CPPBP_COPYRIGHT"]; seen = 1; next } { print }' \
            LICENSE > LICENSE.new
    mv LICENSE.new LICENSE
fi

# Then the one path that carries the name. The substitution above has already
# fixed the reference to it in CMakeLists.txt; a file name is not text in a file,
# so it is moved here or not at all.
mv "systemd/${old}.service.in" "systemd/${new}.service.in"

echo "Renamed ${old} -> ${new}."
if [ -n "$homepage" ]; then
    echo "Homepage: ${homepage}"
else
    echo "Homepage: removed - no URL given, and origin has none this script could read."
fi
if [ -n "$author" ]; then
    echo "LICENSE: Copyright (c) ${year} ${author}"
fi
echo
echo "Next:"
if [ -z "$author" ]; then
    echo "  - LICENSE still names whoever wrote the template. Pass --author to put"
    echo "    your own name there, or edit the one line by hand. 0BSD asks for no"
    echo "    attribution, so this is a matter of it being wrong, not unlicensed"
fi
echo "  - README.md is still about the template: its badge URL says YOU/YOURS, and"
echo "    'Make it yours' is the instructions you have just finished following"
if [ -z "$homepage" ]; then
    echo "  - put HOMEPAGE_URL back in project() once this has a home to point at"
fi
echo "  - replace what the service does: src/task.cpp is an example, not a feature"
echo "  - read systemd/${new}.service.in and decide what it is allowed to touch"
echo "  - delete this script"
echo "  - cmake --preset debug && cmake --build --preset debug && ctest --preset debug"

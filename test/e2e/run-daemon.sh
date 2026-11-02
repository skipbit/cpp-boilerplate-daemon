#!/usr/bin/env bash
#
# Does to the built program what a service manager does: starts it, signals it,
# and reads what came out.
#
# A shell script rather than the CMake one its siblings use. CMake's script mode
# can start a process, or wait for one, but not both - so there is no moment at
# which it could send a signal.

set -euo pipefail

program=${1:?usage: run-daemon.sh <program> <work-dir>}
work=${2:?usage: run-daemon.sh <program> <work-dir>}

rm -rf "$work"
mkdir -p "$work"

pid=""
log=""
status=0

cleanup() {
    if [ -n "$pid" ]; then
        kill -KILL "$pid" 2> /dev/null || true
    fi
}
trap cleanup EXIT

fail() {
    echo "$*" >&2
    if [ -n "$log" ] && [ -f "$log" ]; then
        echo "--- ${log} ---" >&2
        sed 's/^/  /' "$log" >&2
    fi
    exit 1
}

start() {
    log=$1
    shift
    : > "$log"
    "$program" "$@" 2> "$log" &
    pid=$!
}

await() {
    status=0
    wait "$pid" || status=$?
    pid=""
}

# Polled rather than slept for: a sanitizer build takes longer to get anywhere,
# and a fixed sleep long enough for that one is a long time to add to this one.
wait_for() {
    local attempts=0
    while ! grep -qE -- "$1" "$log" 2> /dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -gt 400 ]; then
            return 1
        fi
        sleep 0.05
    done
}

# --- SIGTERM: stops, and stops cleanly -------------------------------------

start "$work/term.log" --interval 0.05 --label alpha
wait_for '^alpha run 3$' || fail "SIGTERM: the program never reached its third run"
kill -TERM "$pid"
await
[ "$status" -eq 0 ] || fail "SIGTERM: expected exit 0, got ${status}"

mapfile -t lines < "$log"
count=${#lines[@]}
[ "$count" -ge 4 ] || fail "SIGTERM: only ${count} line(s) came out"
[ "${lines[$((count - 1))]}" = "stopping" ] || fail "SIGTERM: the last line is '${lines[$((count - 1))]}'"

# Every run before it is a whole line, and they count without a gap. A stop
# taken inside the work rather than between two runs would leave a half-written
# line or a missing number here.
expected=1
for line in "${lines[@]:0:count-1}"; do
    [ "$line" = "alpha run ${expected}" ] || fail "SIGTERM: expected 'alpha run ${expected}', got '${line}'"
    expected=$((expected + 1))
done

# --- SIGKILL: the same program, without the clean path ----------------------
#
# Without this, "it exited 0 and wrote a last line" would be a claim about
# nothing: a check that cannot tell a graceful stop from a killed process is not
# checking the graceful stop.

start "$work/kill.log" --interval 0.05 --label beta
wait_for '^beta run 2$' || fail "SIGKILL: the program never reached its second run"
kill -KILL "$pid"
await
[ "$status" -eq 137 ] || fail "SIGKILL: expected 137, got ${status}"
if grep -qx 'stopping' "$log"; then
    fail "SIGKILL: the stop line is here too, so its presence above says nothing"
fi

# --- SIGHUP: reads the configuration again ----------------------------------

config="$work/mydaemon.conf"
printf 'interval = 0.05\nlabel = "before"\n' > "$config"
start "$work/hup.log" --config "$config"
wait_for '^before run 1$' || fail "SIGHUP: the program never made its first run"

printf 'interval = 0.05\nlabel = "after"\n' > "$config"
kill -HUP "$pid"
wait_for '^after run ' || fail "SIGHUP: the configuration was not read again"

# A configuration that stopped making sense is not a reason to stop a service
# already running with one that works.
printf 'nonsense = 1\n' > "$config"
kill -HUP "$pid"
wait_for 'keeping the one already loaded' || fail "SIGHUP: an unreadable configuration was not refused"

kill -TERM "$pid"
await
[ "$status" -eq 0 ] || fail "SIGHUP: expected exit 0 after an unreadable configuration, got ${status}"

mapfile -t lines < "$log"
count=${#lines[@]}
[ "${lines[$((count - 1))]}" = "stopping" ] || fail "SIGHUP: the last line is '${lines[$((count - 1))]}'"
case "${lines[$((count - 2))]}" in
    "after run "*) ;;
    *) fail "SIGHUP: the run before the stop is '${lines[$((count - 2))]}', not the configuration that worked" ;;
esac

echo "SIGTERM stops cleanly, SIGKILL does not, SIGHUP re-reads and refuses nonsense."

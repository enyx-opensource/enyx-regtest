#!/bin/bash

[[ -z "${_regtest_utils_sh+x}" ]] || return
_regtest_utils_sh=

# = Test Utilities

# Special return codes.
regtest_ret_fatal=100
regtest_ret_timeout=101

regtest_on_exit=()

# regtest_on_exit <command...>
# Execute command on subshell exit.
regtest_on_exit() {
    regtest_on_exit[$BASH_SUBSHELL]+="$*;"
    trap "${regtest_on_exit[$BASH_SUBSHELL]}" EXIT
}

# A temporary directory for the whole process.
regtest_tmp=$(mktemp -td regtest-XXXXXX)
regtest_on_exit "rm -r $(printf %q "$regtest_tmp")"

# regtest_printn <fmt> <args...>
regtest_printn() {
    printf "\e[34;1;2m[REGTEST]\e[0m $1\n" "${@:2}"
}

# regtest_kill_children_on_exit
# Kill all child processes on exit subshell exit.
regtest_kill_children_on_exit() {
    regtest_on_exit 'kill $(jobs -p) 2>/dev/null || true'
}

# regtest_launch_with_tty_hack <command...>
# Replace the `isatty (3)` function so that it always returns true in order to (hopefully) force
# programs to always colour and line-buffer their output.
regtest_launch_with_tty_hack() {
    local ttyso=$regtest_tmp/regtest-ttyseverywhere.so
    if [[ "${LD_PRELOAD-}" == "$ttyso" ]]; then
        "$@"
    else
        [[ ! -e "$ttyso" ]] &&
            gcc -O2 -fpic -shared -ldl -o "$ttyso" -xc - <<< 'int isatty(int fd) { return (1 == fd || 2 == fd); }'
        LD_PRELOAD="$ttyso" "$@"
    fi
}

# command_name <command...>
# Returns a meaningful name for the command provided in the parameter list.
command_name() {
    if [[ "$1" == env ]]; then
        shift
        while [[ $# != 0 && "$1" == *=* ]]; do
            shift
        done
    fi
    printf '%s\n' "${1-???}"
}

# regtest_nice_kill [-<signal>] <pid> [<timeout>]
# Send <signal> (default: TERM) to process, then KILL it if it refuses to die after <timeout>
# (default: 1½ seconds).
regtest_nice_kill() {
    local sig=-TERM
    [[ "$1" == -* ]] && { sig=$1; shift; }
    local pid=$1 timeout=${2-1.5}
    kill "$sig" -- "$pid"
    while read; do
        ps "$pid" >/dev/null || return 0
        sleep 0.1
    done < <(awk </dev/null -vt="$timeout" 'BEGIN { while (t >= 0) { t -= 0.1; print } }')
    regtest_printn >&2 \
            '\e[31mError: Process %s is still alive after %s seconds.\e[0m KILL time!' \
            "$pid" "$timeout"
    kill -9 -- "$pid"
    return $regtest_ret_fatal
}

# regtest_diff <path1> <path2>
# Perform a diff of two files or directories. Returns 0 iff identical.
regtest_diff() {
    git --no-pager diff --no-index --color=always "$@"
}

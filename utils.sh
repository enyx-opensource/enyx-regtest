#!/bin/bash

[[ -z "${_regtest_utils_sh+x}" ]] || return
_regtest_utils_sh=

# = Test Utilities

# Special return codes.
regtest_ret_fatal=100
regtest_ret_timeout=101

_regtest_on_exit=()
_regtest_kill_children_on_exit=()

regtest_on_exit_handler() {
    if [[ "${_regtest_kill_children_on_exit[$BASH_SUBSHELL]-}" ]]; then
        kill $(jobs -p) 2>/dev/null || true
        wait 2>/dev/null || true
    fi
    local _regtest_on_exit_status=0
    eval "${_regtest_on_exit[$BASH_SUBSHELL]-}"
    return "$_regtest_on_exit_status"
}

# regtest_on_exit <command...>
# Execute command on subshell exit. May be called several times, in which case the commands will
# be executed in _reverse_ order upon exiting. In the case of an ordinary exit (the process was
# not killed), the subshell will exit with the last non-zero return code.
regtest_on_exit() {
    _regtest_on_exit[$BASH_SUBSHELL]="$(
        printf '{ %s; } || _regtest_on_exit_status=$?; %s' \
                "$*" "${_regtest_on_exit[$BASH_SUBSHELL]-}"
    )"
    trap 'regtest_on_exit_handler' EXIT
}

# regtest_kill_children_on_exit
# Kill all child processes on subshell exit. If other cleanup operations have also been setup
# through `regtest_on_exit`, child processes will be killed before running these commands.
regtest_kill_children_on_exit() {
    _regtest_kill_children_on_exit[$BASH_SUBSHELL]=1
    trap 'regtest_on_exit_handler' EXIT
}

# A temporary directory for the whole process.
regtest_tmp=$(mktemp -td regtest-XXXXXX)
regtest_on_exit "rm -r $(printf %q "$regtest_tmp")"

regtest_print_prefix=$'\e[34;1;2m[REGTEST]\e[0m '

# regtest_printn <fmt> <args...>
regtest_printn() {
    printf "$regtest_print_prefix$1\n" "${@:2}"
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
    done < <(gawk </dev/null -vt="$timeout" 'BEGIN { while (t >= 0) { t -= 0.1; print } }')
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

# regtest_checksum <path>
# Compute and print a checksum of a file or a directory. If the file is a symbolic link, compute
# the checksum of the target. Directory checksums are computed according to a custom algorithm
# which takes into account:
# - the file hierarchy, i.e. the paths of all files contained within the directory;
# - file types;
# - symbolic link target paths;
# - whether the _regular_ files are executable;
# - the contents of _regular_ files;
# By default, we use `md5sum` since it is fast (3 times faster than sha256sum), produces short
# hashes, and a strong cryptographic hash function will usually not be necessary.
regtest_checksum() {
    if [[ ! -d "$1" ]]; then
        md5sum <"$1"
    elif [[ -d "$1" ]]; then
        # Prefix the (directory) checksum with 'D' to distinguish it from an ordinary checksum.
        echo -n D
        {
            cd "$1"
            {
                find . -not \( -type f -executable \) -printf '%p %y %l\0'
                find . -type f -executable -printf '%p f x\0'
            } | sed -z 's|^\./||' | LC_ALL=C sort -z
            find . -type f -print0 | sed -z 's|^\./||' | LC_ALL=C sort -z | xargs -0 md5sum --
        } | md5sum
    fi |
    sed 's/ .*//'
}

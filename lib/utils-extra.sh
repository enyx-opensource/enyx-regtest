#!/bin/bash

# = Extra utilities (not required by framework.sh)

## regtest_launch_with_tty_hack <command...>
# Replace the `isatty (3)` function with one that always returns true for stdout and stderr in
# order to (hopefully) force programs to always colour and line-buffer their output. Can have some
# pretty nasty side-effects with some programs. Requires gcc.
# To replace the default `regtest_launch` behaviour:
#
#     regtest_launch() { regtest_launch_with_tty_hack "$@"; }
regtest_launch_with_tty_hack() {
    local ttyso=$_regtest_tmp/regtest-ttyseverywhere.so
    if [[ "${LD_PRELOAD-}" == "$ttyso" ]]; then
        "$@"
    else
        [[ ! -e "$ttyso" ]] &&
            gcc -O2 -fpic -shared -ldl -o "$ttyso" -xc - \
                <<< 'int isatty(int fd) { return fd == 1 || fd == 2; }'
        LD_PRELOAD="$ttyso" "$@"
    fi
}

## regtest_temp_pipe
# Creates a temporary pipe file in /tmp and returns its path. It is the caller's responsibility to
# clean it up.
regtest_temp_pipe() {
    local pipe
    pipe=$(mktemp -u "$_regtest_tmp/regtest-pipe-XXXXX")
    mkfifo -m600 "$pipe"
    printf '%s\n' "$pipe"
}

## regtest_redirect_stdout_to <file> <command...>
# Redirect <command...>'s standard output to <file>.
regtest_redirect_stdout_to() {
    "${@:2}" >"$1"
}

## regtest_from_dir <dir> <command...>
# Run <command...> from directory <dir>.
regtest_from_dir() {
    cd "$1" && "${@:2}"
}

## regtest_env <var>=<val>... <command...>
# Like `env`, but has the advantage that it accepts shell functions for the <command...> argument.
# Runs the command in a subshell.
regtest_env() {
(
    while [[ "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
)
}

## regtest_launch_with_server <ready-regex> <server-command> -- <main-command>
# Runs <server-command> in the background, waits for <ready-regex> to appear in the server's
# output, then launches <main-command>. Kills the server after the main command exits.
regtest_launch_with_server() {
(
    local ready_regex=$1
    shift

    local server_cmd=()
    while [[ "$1" != -- ]]; do
        server_cmd+=("$1")
        shift
    done
    shift

    local ret=0
    local server_pid server_pipe

    server_pipe=$(regtest_temp_pipe)
    regtest_on_exit "rm $(printf %q "$server_pipe")"
    regtest_kill_children_on_exit
    "${server_cmd[@]}" \
        &> >(tee >(cat >"$server_pipe" || cat >/dev/null) |
             stdbuf -oL sed -e$'s/^/\e[36;2m[SERVER] \e[0;2m/' -e$'s/$/\e[0m/') \
        & server_pid=$!
        # Note: `tee -p` not available on centos7, hence the `>(cat >... || cat >/dev/null)` hack.
    # Use -0 because the server will have already received a TERM signal from
    # `regtest_kill_children_on_exit`.
    regtest_on_exit "regtest_nice_kill -0 $server_pid"
    # Wait for ports to be up.
    regtest_printn "Waiting for server to be ready..."
    grep -E -m1 "$ready_regex" "$server_pipe"
    ps $server_pid || { regtest_printn 'Error: Server exited unexpectedly.'; return 1; }
    regtest_printn "Server ready. Launching main command '%s'." "$(command_name "$@")"
    "$@" || {
        ret=$?
        regtest_printn 'Error: %s exited with error (code %d)' "$(command_name "$@")" "$ret";
    }

    return $ret
)
}

## regtest_launch_in_sequence [--\*] <command...> [--* <command...> [--* <...>]]
# Launches `--*`-separated commands one after the other. Stops if one command returns non-zero.
# If the first argument matches regex `^---*$`, it will be used as separator, otherwise `--` will
# be used as separator.
regtest_launch_in_sequence() {
    local sep=--
    if [[ "$1" =~ ^---*$ ]]; then
        sep=$1
        shift
    fi

    while [[ $# != 0 ]]; do
        local args=()
        while [[ $# != 0 && "$1" != "$sep" ]]; do
            args+=("$1")
            shift
        done
        [[ $# != 0 ]] && shift
        regtest_printn "Running %s..." "$(command_name "${args[@]}")"
        "${args[@]}" || return $?
    done
}

## regtest_retry_and_pray [n=5] <command...>
# Try the given <command...> up to `n` times (retry `n - 1` times), until it succeeds. Returns the
# last of <command...>'s return codes. Can be useful for less important tests that are known to
# fail occasionally (...and don't need to be fixed right away).
regtest_retry_and_pray() {
    local i n=5 ret
    [[ "$1" =~ ^[0-9]+$ ]] && { n=$1; shift; }
    for ((i = 1; i <= n; i++)); do
        ((i != 1)) && {
            regtest_printn '\e[34;2m[RETRY]\e[0m \e[2mTry %d/%d...\e[0m' "$i" "$n"
        }
        "$@" && return
        ret=$?
        regtest_printn '\e[31;2m[FAILED]\e[0m \e[2m%s\e[0m' "$(command_name "$@")"
    done
    return $ret
}

## regtest_expect_exit_status <n> <command...>
# Return 0 if the exit status of <command...> is <n>, 1 otherwise. Useful for checking that errors
# are properly detected and reported. Also prevents lines containing "[REGTEST]" or the
# 'regtest_forward_output_pattern' from being forwarded.
regtest_expect_exit_status() {
    local n=$1 pipestatus
    shift
    "$@" |& {
        if [[ "${regtest_forward_output_pattern-}" == . ]]; then
            cat
        else
            # Prevent [REGTEST] lines and other forwarded lines from being forwarded.
            sed -r "s/^.*$(_regtest_forward_command_output_full_pattern)/(regtest-ignore)\0/I"
        fi
    }
    pipestatus=("${PIPESTATUS[@]}")
    [[ ${pipestatus[1]} == 0 ]] || {
        regtest_printn >&2 'sed failed!'
        return $_regtest_ret_fatal
    }
    [[ ${pipestatus[0]} == "$n" ]] || {
        regtest_printn >&2 'Expected exit status %s; got %s.' "$n" "${pipestatus[0]}"
        return 1
    }
    return 0
}

## regtest_expect_grep [--no-kill[=<error-status>]] <pattern> <command...>
# If the awk regex <pattern> is _not_ found in <command...>'s stdout or stderr:
#
# - If `--no-kill` was _not_ specified, returns 1.
# - If `--no-kill[=<error-status>]` was specified, returns <error-status>. The default
#   <error-status> is 200.
#
# If the pattern is found:
#
# - If `--no-kill` was _not_ specified, kills the <command...> and returns 0.
# - If `--no-kill[=<...>]` was specified, waits for the <command...> and returns its exit status.
regtest_expect_grep() {
    if [[ $BASH_VERSION < 4.3 ]]; then
        regtest_printn >&2 \
                'Error: regtest_expect_grep is not compatible with bash versions < 4.3!'
        return $_regtest_ret_fatal
    fi
    local pat no_kill= r
    case $1 in
    --no-kill)   no_kill=200; shift;;
    --no-kill=*) no_kill=${1#--no-kill=}; shift;;
    -*)          regtest_printn >&2 'Error: regtest_expect_grep does not recognize argument %s!' \
                                    "$1"
                 return $_regtest_ret_fatal;;
    esac
    pat=${1//\//\\/}
    shift
    regtest_kill_children_on_exit
    (
        regtest_kill_children_on_exit
        exec 3>&2
        gawk -v no_kill="$no_kill" '
            !found && '"/$pat/"' {
                print $0 " \033[32m--> OK!\033[0m"
                if (no_kill)
                    found = 1
                else
                    exit 0
            }
            { print }
            ENDFILE { exit (found ? 0 : (no_kill ? no_kill : 1)) }' \
            <(
                true & # (clear $!)
                regtest_on_exit 'regtest_nice_kill $! >&3'
                "$@" 2>&1 & wait $!
            ) || {
                r=$?
                regtest_printn >&2 \
                    "Error: Could not find expected pattern %s in standard output/error." "$pat"
                return $r
            }
        # If --no-kill, forward the tested command's error code.
        [[ ! "$no_kill" ]] || wait $!
    )
}

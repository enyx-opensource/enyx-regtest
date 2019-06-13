#!/bin/bash

# This is the main entry point for regression tests. To use it, create a `run-tests` file in the
# same vein as the following example:
#
#     #!/bin/bash
#
#     . regtest/run-tests.sh
#     . regtest/utils-extra.sh # (optional; if required by the test suites)
#
# Followed by the following if the test is divided into test suites:
#
#     regtest_run_suites tests \
#         suite1 \
#         suite2
#
# It is expected that two test suite files, `suite1.sh` and `suite2.sh` will be present in a
# `./tests` directory.
#
# Or, to have all tests in one place, inline:
#
#     regtest_start
#
#     mysuite() {
#     <test cases>
#     }
#     regtest_run_suite mysuite mysuite
#
#     regtest_finish

. "$(readlink -m "$BASH_SOURCE/..")"/framework.sh

usage() {
    echo "Usage: ./run-tests [OPTIONS] [glob...]"
    echo "By default, runs tests matching the given glob patterns."
    echo "Default glob is *."
    echo "Options:"
    echo "    -h,--help             show this help"
    echo "    -l,--list             list tests matching globs"
    echo "    -p,--print            print command line of tests matching globs"
    echo "    -e,--extra-args=<...> add given extra arguments to test commands"
    echo "    -g,--generate         generate reference files (instead of failing when not found)"
    echo "    -f,--forward-output[=<...>] forward test command output to stdout"
    echo "        If a pattern is provided, lines matching the pattern will be forwarded"
    echo '        Note: Lines matching `\[regtest\]` are always forwarded'
    echo '        Example: `-f'\''warning|error'\''`' \
            ${regtest_forward_output_pattern:+"Default: \`$regtest_forward_output_pattern\`"}
    echo "    -D,--deterministic    don't randomize order in which test suites are run"
    echo '    --exclude=<...>       exclude tests matching the given glob'
    echo '        Can be called multiple times.'
    echo '    --no-timeout          disable test suite timeout'
    echo
    echo 'Environment:'
    echo '    REGTEST_INPUTDIR      directory containing input files ({} prefix)'
    echo '    REGTEST_REFDIR        directory of reference files ({ref} prefix)'
    echo '    REGTEST_OUTDIR        directory for output files ({out.<ext>} prefix)'
    echo '    REGTEST_TMPDIR        directory for temporary files ({tmp.<ext>} prefix)'
    echo '    REGTEST_LOGDIR        directory for log files'
    echo '    REGTEST_SUITE_TIMEOUT base timeout for test suites'
}

list=0
print=0

opts=$(getopt -o hlpe:gf::D \
              --long help,list,print,extra-args:,generate,forward-output::,deterministic,exclude:,no-timeout -- "$@") || exit 1
eval set -- "$opts"
while true ; do
    case "$1" in
        -h|--help          ) usage; exit 0;;
        -l|--list          ) list=1; shift;;
        -p|--print         ) print=1; shift;;
        -e|--extra-args    ) regtest_extra_args+=($2); shift 2;;
        -g|--generate      ) regtest_generate=1; shift;;
        -f|--forward-output) regtest_forward_output_pattern=${2:-.}; shift 2;;
        -D|--deterministic ) regtest_run_suites_in_random_order=0; shift;;
        --exclude          ) regtest_exclude_globs+=("$2"); shift 2;;
        --no-timeout       ) regtest_suite_timeout=inf; shift;;
        --                 ) shift; break;;
        *                  ) regtest_printn "Internal error (getopt)!"; exit 1;;
    esac
done
regtest_globs=("${@-*}")

if [[ $list == 1 && $print == 1 ]]; then
    regtest_printn >&2 "Error: Can't have both --list and --print."
    exit 1
fi

if [[ $list == 1 ]]; then
    : ${regtest_tmpdir:=tmp}
    regtest_run_suites_in_random_order=0
    regtest_impl() {
        [[ "$name" =~ $regtest_name_regex ]]
        printf '%s\n' "${BASH_REMATCH[1]}"
    }
elif [[ $print == 1 ]]; then
    : ${regtest_tmpdir:=tmp}
    regtest_run_suites_in_random_order=0
    regtest_impl() {
        regtest_printn '\e[34m%s\e[0m' "$name"
        printf '%s' "$1"
        local i last
        for i in "${@:2}"; do
            if [[ "$i" == -* || ! "${last-}" =~ ^-.*[^-] ]]; then
                printf ' \e[36;2m\\\e[0m\n%s' "$i"
            else
                printf ' %s' "$i"
            fi
            last=$i
        done
        printf '\n\n'
    }
fi

regtest_kill_children_on_exit

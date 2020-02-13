#!/bin/bash

# = Checksum File Monkey-Patches

# When this file is sourced, a file named "reference-md5sums" will be used to store the hashes of
# the reference files. These checksums will be used to determine if outputs have changed instead
# of `diff`. This can help shorten comparison times if the reference files are large and stored
# remotely.

# TODO: Compute checksums of input files.
#regtest_input_checksum_file=input-md5sums
regtest_ref_checksum_file=reference-md5sums

# regtest_ref_checksum <path> (monkey-patch)
# Get a stored checksum for a file. If it hasn't been computed yet, compute it and store it first.
regtest_ref_checksum() {
    local path=$1 filename sum tmp_checksum_file

    filename=$(basename -- "$path")
    sum=$(gawk -v p="$filename" '!/^#/ && $2 == p { print $1; exit; }' \
               "$regtest_ref_checksum_file")

    if [[ -n "$sum" ]]; then
        if [[ ! "$regtest_generate" ]]; then
            printf '%s\n' "$sum"
        else
            regtest_printn >&2 \
                'Reference output checksum already recorded in %s. Checking it...' \
                "$regtest_ref_checksum_file"
            actual_sum=$(regtest_checksum "$path") || return 1
            if [[ "$actual_sum" == "$sum" ]]; then
                regtest_printn >&2 'Checksum OK.'
                printf '%s\n' "$sum"
            else
                regtest_printn >&2 \
                    'Error: The recorded checksum (%s) differs from the actual checksum (%s)!' \
                    "$sum" "$actual_sum"
                regtest_printn >&2 '(Commenting out old checksums...)'
                tmp_checksum_file=$(mktemp "$_regtest_tmp/checksum-file-$BASHPID-XXXXX")
                regtest_on_exit "rm -f $(printf %q $tmp_checksum_file)"
                gawk -v p="$filename" -v s="$actual_sum" \
                     '$2 == p && $1 != s { print "#" $0; next; } { print }' \
                     "$regtest_ref_checksum_file" > "$tmp_checksum_file"
                printf "%s %s\n" "$actual_sum" "$filename" >>"$tmp_checksum_file"
                mv "$tmp_checksum_file" "$regtest_ref_checksum_file"
                return 1
            fi
        fi
    else
        regtest_printn >&2 'Warning: %s checksum unknown. Computing it...' "$path"
        sum=$(regtest_checksum "$path") || return 1
        printf "%s %s\n" "$sum" "$filename" >>"$regtest_ref_checksum_file"
        printf '%s\n' "$sum"
    fi
}

# regtest_out_checksum <path> (monkey-patch)
# Just compute the checksum.
regtest_out_checksum() {
    regtest_checksum "$1"
}

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
    local path=$1 filename sum

    filename=$(basename -- "$path")
    sum=$(gawk -v p="$filename" '$2 == p { print $1; exit; }' "$regtest_ref_checksum_file")

    if [[ -n "$sum" ]]; then
        printf '%s\n' "$sum"
    else
        regtest_printn >&2 'Warning: %s checksum unknown. Computing it...' "$path"
        sum=$(regtest_checksum "$path") || return 1
        printf "%s %s\n" "$sum" "$filename" >>"$regtest_ref_checksum_file"
        printf '%s\n' "$sum"
    fi
}

# regtest_out_checksum <path>
# Just compute the checksum.
regtest_out_checksum() {
    regtest_checksum "$1"
}

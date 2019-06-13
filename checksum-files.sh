#!/bin/bash

# = Checksum File Monkey-Patch for `regtest_get_checksum`

# TODO: Compute checksums of input files.
regtest_input_checksum_file=input-md5sums
regtest_ref_checksum_file=reference-md5sums

# Get a stored checksum for a file. If it hasn't been computed yet, compute it and store it first.
regtest_get_checksum() {
    local path=$1 filename sum

    filename=$(basename -- "$path")
    sum=$(awk -v p="$filename" '$2 == p { print $1; exit; }' "$regtest_ref_checksum_file")

    if [[ -n "$sum" ]]; then
        printf '%s\n' "$sum"
    else
        regtest_printn >&2 'Warning: %s checksum unknown. Computing it...' "$path"
        sum=$(regtest_compute_checksum "$path") || return 1
        printf "%s %s\n" "$sum" "$filename" >>"$regtest_ref_checksum_file"
        printf '%s\n' "$sum"
    fi
}

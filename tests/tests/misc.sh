# = Misc Tests

regtest_dir=.

regtest misc-dir-output \
    sh -c 'mkdir "$0" "$0"/dirindir && echo hello > "$0"/dirindir/file' {out.dir}

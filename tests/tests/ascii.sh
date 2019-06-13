# = Test with ascii

# Note: Tests ending in `-fail` have been made to fail on purpose.

. "$ENYX_REGTEST_DIR"/utils-extra.sh

regtest_dir=ascii

regtest ascii-hello \
    grep Hello {}/hello.txt

# This test fails.
regtest ascii-hello-bad-case-fail \
    grep hello {}/hello.txt

# Test fails but failure is ignored; only emits warning.
regtest ascii-hello-bad-case-warn \
    --warn-only=1 \
    grep hello {}/hello.txt

# Test fails; only warns on error code 2, but error code is 1.
regtest ascii-hello-bad-case-warn-fail \
    --warn-only=2 \
    grep hello {}/hello.txt

# Test Fails but failure is ignored just as in `ascii-hello-bad-case-warn`.
regtest ascii-hello-bad-case-multi-warn \
    --warn-only=2 --warn-only=1 \
    grep hello {}/hello.txt

regtest ascii-hello-case-insensitive \
    grep -i hello {}/hello.txt

regtest ascii-hello-color \
    regtest_redirect_stdout_to {out.txt} \
    grep Hello --color=always {}/hello.txt

# This test fails during comparison phase due to missing reference file.
regtest ascii-hello-color-no-ref-fail \
    regtest_redirect_stdout_to {out.txt} \
    grep Hello --color=always {}/hello.txt

# This test fails during comparison phase due to a reference file that differs from the actual
# output of the grep command.
regtest ascii-hello-color-bad-ref-fail \
    regtest_redirect_stdout_to {out.txt} \
    grep Hello --color=always {}/hello.txt

# = Test the slow version of grep :]

slowgrep() { sleep "$1"; shift; grep "$@"; }

regtest_dir=ascii

regtest slow-hello-1 \
    slowgrep .2 Hello {}/hello.txt

regtest slow-hello-2 \
    slowgrep .3 Hello {}/hello.txt

regtest slow-hello-3 \
    slowgrep 0 Hello {}/hello.txt

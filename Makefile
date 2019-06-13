# == Configuration

build ?= build

version := 0.1.0

prefix  ?= /usr/local
libdir  ?= $(prefix)/lib
datadir ?= $(prefix)/share
mandir  ?= $(datadir)/man
man7dir ?= $(mandir)/man7
docdir  ?= $(datadir)/doc/enyx-regtest

$(shell mkdir -p $(build))
$(shell \
    { \
        echo $(version); \
        echo $(prefix) $(libdir) $(datadir) $(mandir) $(man7dir) $(docdir); \
    } >$(build)/conf.new; \
    touch -a $(build)/conf; \
    diff >&2 -U0 $(build)/conf $(build)/conf.new || mv $(build)/conf.new $(build)/conf \
)

# == Rules

all: $(build)/enyx-regtest.pc

# === pkgconfig

$(build)/enyx-regtest.pc: enyx-regtest.pc.in $(build)/conf
	awk -vprefix=$(prefix) -vlibdir=$(libdir) -vversion=$(version) '{ \
	        gsub("@prefix@",  prefix); \
	        gsub("@libdir@",  libdir); \
	        gsub("@version@", version); \
	        print \
	}' $< > $@

# === Test

test:
	cd tests && chronic ./simple-test
	cd tests && ./run-metatests

cicmd := ./tests/ci $(build)/ci
test_bugged_timeout := \
    (cd tests && \
     chronic ./simple-test && \
     ./run-metatests --exclude meta-suite-timeout)
ci:
	$(cicmd) debian:8 'make test' # (debian 8's version of asciidoctor is too old)
	$(cicmd) debian:9 'make test doc'

	$(cicmd) ubuntu:16.04 'make test doc'
	$(cicmd) ubuntu:18.04 'make test doc'

	# On ubuntu 19.04 (current "rolling"), a bug currently in bash 5.0 (.3) causes the timeout
	# mechanism to stall when triggered. TODO: Remove this comment and
	# `$(test_bugged_timeout)` when a fix is merged into ubuntu.
	# Bug report: http://lists.gnu.org/archive/html/bug-bash/2019-06/msg00000.html
	$(cicmd) ubuntu:rolling '$(test_bugged_timeout) && make doc'

	# $(cicmd) centos:6 # doesn't work due to old bash (4.1; need 4.2) and gawk (3; need 4)

	# On centos7, with bash 4.2, the timeout mechanism seems a bit iffy...
	$(cicmd) centos:7 '$(test_bugged_timeout) && make doc'

# === Install

lib := framework.sh utils.sh utils-extra.sh checksum-files.sh run-tests.sh

install: install-doc install-lib

install-lib: $(lib) $(build)/enyx-regtest.pc
	install -d $(libdir)/enyx-regtest $(libdir)/pkgconfig
	install -m 644 $(lib) $(libdir)/enyx-regtest
	install -m 644 $(build)/enyx-regtest.pc $(libdir)/pkgconfig

uninstall:
	rm -rf $(man7dir)/enyx-regtest.7 \
	       $(docdir) \
	       $(libdir)/enyx-regtest \
	       $(libdir)/pkgconfig/enyx-regtest.pc

# ===

.PHONY: all doc html man \
        test ci \
        install install-doc install-man install-html install-lib uninstall

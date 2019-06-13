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
    diff >&2 -u0 $(build)/conf $(build)/conf.new || mv $(build)/conf.new $(build)/conf \
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
        test \
        install install-doc install-man install-html install-lib uninstall

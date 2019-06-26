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

safer_rm_rf = @[ $(words $(1)) != 1 ] && exit 1; echo rm -rf -- $(1); rm -rf -- $(1)

lib := lib/framework.sh lib/utils.sh lib/utils-extra.sh lib/checksum-files.sh lib/run-tests.sh

# == Rules

all: man html $(build)/enyx-regtest.pc

# === pkgconfig

$(build)/enyx-regtest.pc: enyx-regtest.pc.in $(build)/conf
	awk -vprefix=$(prefix) -vlibdir=$(libdir) -vversion=$(version) '{ \
	        gsub("@prefix@",  prefix); \
	        gsub("@libdir@",  libdir); \
	        gsub("@version@", version); \
	        print \
	}' $< > $@

# === Documentation

html := enyx-regtest.html README.html example

doc: man html
html: $(addprefix $(build)/,$(html))
man: $(build)/enyx-regtest.7

$(build)/function-doc: $(lib)
	$(call safer_rm_rf,$@)
	mkdir -p $@ && gawk -voutdir=$@ ' \
	    /^## [a-z0-9_]*( |$$)/ { \
	        out = outdir "/" $$2 ".adoc"; \
	        print substr($$0, 4) "::\n+\n--" >out; \
	        next \
	    } \
	    out { \
	        if (/^#( |$$)/) { print substr($$0, 3) >>out } \
	        else            { print "--" >>out; out = "" } \
	    }' \
	    $^

$(build)/example: example/run-tests example/tests/suite1.sh
	$(call safer_rm_rf,$@)
	mkdir -p $@ && cp -r example/run-tests example/tests $@

$(build)/help.txt: tests/example/run-tests lib/run-tests.sh
	{ cd tests/example && ./run-tests --help; } | awk '/^$$/ { exit } { print }' > $@

$(build)/enyx-regtest.7: enyx-regtest.adoc $(build)/help.txt $(build)/function-doc
	asciidoctor -aincludedir=$(build) -amanversion=$(version) -bmanpage $< --out-file $@

$(build)/%.html: %.adoc $(build)/help.txt $(build)/function-doc
	asciidoctor -aincludedir=$(build) -arevnumber=$(version) $< --out-file $@

# === Test

prepare-tests:
	$(call safer_rm_rf,$(build)/test-copy)
	mkdir -p $(build)/test-copy/tests/example
	cp -a lib tests $(build)/test-copy/

chronic := $(shell command -v chronic >/dev/null && echo chronic)

simple-test: prepare-tests
	cd $(build)/test-copy/tests && $(chronic) ./simple-test

metatest: prepare-tests
	cd $(build)/test-copy/tests && ./run-metatests

test: simple-test metatest

# For centos 7.
metatest-no-timeout-test: prepare-tests
	cd $(build)/test-copy/tests && ./run-metatests --exclude meta-suite-timeout
test-no-timeout-test: simple-test metatest-no-timeout-test

cicmd := ./tests/ci $(build)/ci
ci:
	$(cicmd) debian:8 'make test' # (debian 8's version of asciidoctor is too old)
	$(cicmd) debian:9 'make test doc'

	$(cicmd) ubuntu:16.04 'make test doc'
	$(cicmd) ubuntu:18.04 'make test doc'
	$(cicmd) ubuntu:rolling 'make test doc'

	# Centos 6 uses bash 4.1, gawk 3.x (not 4.x), etc. As a result, support is dismal but
	# is mostly sufficient to just run the tests and get a binary (failure/success) result.
	$(cicmd) centos:6 'make simple-test'

	# On centos 7, with bash 4.2, the timeout mechanism seems a bit iffy...
	$(cicmd) centos:7 'make test-no-timeout-test doc'

# === Install

install: install-doc install-lib

install-doc: install-man install-html
install-man: $(build)/enyx-regtest.7
	install -Dm644 -t$(man7dir) $^
install-html: $(addprefix $(build)/,$(html))
	(cd $(build) && find $(html) -type f) | xargs -I{} install -Dm644 $(build)/{} $(docdir)/{}
install-lib: $(lib) $(build)/enyx-regtest.pc
	install -Dm644 -t$(libdir)/enyx-regtest $(lib)
	install -Dm644 -t$(libdir)/pkgconfig $(build)/enyx-regtest.pc

uninstall:
	$(call safer_rm_rf,$(man7dir)/enyx-regtest.7)
	$(call safer_rm_rf,$(docdir))
	$(call safer_rm_rf,$(libdir)/enyx-regtest)
	$(call safer_rm_rf,$(libdir)/pkgconfig/enyx-regtest.pc)

# ===

.PHONY: all doc html man \
        prepare-tests simple-test metatest test metatest-no-timeout-test test-no-timeout-test ci \
        install install-doc install-man install-html install-lib uninstall

#!/bin/bash

# = Test asciidoctor...

# Test HTML generation.
regtest suite1-enyx-regtest-html \
    asciidoctor {}/enyx-regtest.adoc --out-file {out.html}

# Test manpage generation.
regtest suite1-enyx-regtest-manpage \
    asciidoctor {}/enyx-regtest.adoc -bmanpage --out-file {out.7}

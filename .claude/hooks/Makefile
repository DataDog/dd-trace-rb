# Build and test the hooks in this directory
#
#   make             bootstrap Spinel if needed, compile every hook, run tests
#   make test        run every hook's tests (unit + smoke) under CRuby
#   make bootstrap   fetch and build Spinel into SPINEL_HOME
#   make compile     compile every hook into compiled/<name> (builds Spinel first)
#   make clean       remove compiled binaries
#
# Plain Ruby is the portable fallback, so `make test` alone never needs Spinel.
# The smoke suite runs the compiled binary against CRuby when one is present, so
# the default `make` is the native re-verify step after any hook change.

SHELL := /bin/sh

HOOKS_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
SOURCES := $(filter-out %.test.rb,$(wildcard $(HOOKS_DIR)*.rb))
BINARIES := $(patsubst $(HOOKS_DIR)%.rb,$(HOOKS_DIR)compiled/%,$(SOURCES))

SPINEL_HOME ?= $(HOME)/.cache/spinel
SPINEL_REPO ?= https://github.com/matz/spinel
SPINEL_REF ?= 65129ad1c1238aa579c6d6bd5a9f26ea0e3f2882
SPINEL ?= $(SPINEL_HOME)/bin/spinel

.PHONY: all compile test clean bootstrap

all: compile test

compile: $(BINARIES)

bootstrap: $(SPINEL)

$(SPINEL):
	test -d "$(SPINEL_HOME)/.git" || git clone "$(SPINEL_REPO)" "$(SPINEL_HOME)"
	git -C "$(SPINEL_HOME)" fetch --tags origin
	git -C "$(SPINEL_HOME)" checkout "$(SPINEL_REF)"
	$(MAKE) -C "$(SPINEL_HOME)" deps
	$(MAKE) -C "$(SPINEL_HOME)"

$(HOOKS_DIR)compiled/%: $(HOOKS_DIR)%.rb | $(SPINEL)
	@mkdir -p "$(HOOKS_DIR)compiled"
	"$(SPINEL)" "$<" -o "$@"

test:
	@for t in $(HOOKS_DIR)*.test.rb; do echo "ruby $$t"; ruby "$$t" || exit 1; done

clean:
	rm -f $(BINARIES)

# kwt — install the sandbox launcher and its kit extension.
#
#   make install     install the kwt script and the headless kit extension
#   make test        run the test suite
#   make uninstall   remove what install created
#
# Paths default to the usual user locations and can be overridden:
#
#   make install PREFIX=/usr/local
#   make install EXT_DIR="$HOME/.config/kit/extensions"
#   make install DESTDIR=/tmp/stage   # for packaging

SHELL := /bin/bash

# The kwt script lands in a local bin directory. PREFIX defaults to ~/.local,
# which puts it in ~/.local/bin — on PATH on most setups.
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

# The kit extension lands where kit auto-loads user extensions from:
# $XDG_CONFIG_HOME/kit/extensions/*.go, with XDG_CONFIG_HOME defaulting to
# ~/.config. The 00- prefix is load-order significant and must be kept.
XDG_CONFIG_HOME ?= $(HOME)/.config
EXT_DIR ?= $(XDG_CONFIG_HOME)/kit/extensions

KWT := kwt
EXT := extensions/00-headless.go
EXT_NAME := $(notdir $(EXT))

.PHONY: all help install install-script install-extension uninstall test

all: help

help:
	@printf '%s\n' \
	  'kwt' \
	  '' \
	  '  make install            install the kwt script and the kit extension' \
	  '  make install-script     install the kwt script into $(BINDIR)' \
	  '  make install-extension  install the kit extension into $(EXT_DIR)' \
	  '  make test               run the test suite' \
	  '  make uninstall          remove the installed script and extension' \
	  '' \
	  'Override paths with PREFIX=... BINDIR=... EXT_DIR=...' \
	  '(and DESTDIR=... for staged installs).'

# Install both pieces: the launcher a developer runs, and the extension that
# makes a sandboxed kit session start headless.
install: install-script install-extension

install-script: $(KWT)
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(KWT) $(DESTDIR)$(BINDIR)/kwt
	@printf 'installed %s\n' "$(DESTDIR)$(BINDIR)/kwt"

install-extension: $(EXT)
	install -d $(DESTDIR)$(EXT_DIR)
	install -m 0644 $(EXT) $(DESTDIR)$(EXT_DIR)/$(EXT_NAME)
	@printf 'installed %s\n' "$(DESTDIR)$(EXT_DIR)/$(EXT_NAME)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/kwt
	rm -f $(DESTDIR)$(EXT_DIR)/$(EXT_NAME)
	@printf 'removed %s and %s\n' "$(DESTDIR)$(BINDIR)/kwt" "$(DESTDIR)$(EXT_DIR)/$(EXT_NAME)"

test:
	bash test/run.sh

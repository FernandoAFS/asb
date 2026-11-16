# asb — install the sandbox launcher and its kit extension.
#
#   make install     install the asb script and the headless kit extension
#   make test        run the test suite
#   make uninstall   remove what install created
#
# Paths default to the usual user locations and can be overridden:
#
#   make install PREFIX=/usr/local
#   make install EXT_DIR="$HOME/.config/kit/extensions"
#   make install DESTDIR=/tmp/stage   # for packaging

SHELL := /bin/bash

# The asb script lands in a local bin directory. PREFIX defaults to ~/.local,
# which puts it in ~/.local/bin — on PATH on most setups.
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

# The kit extension lands where kit auto-loads user extensions from:
# $XDG_CONFIG_HOME/kit/extensions/*.go, with XDG_CONFIG_HOME defaulting to
# ~/.config. The 00- prefix is load-order significant and must be kept.
XDG_CONFIG_HOME ?= $(HOME)/.config
EXT_DIR ?= $(XDG_CONFIG_HOME)/kit/extensions

ASB := asb
EXT := extensions/00-headless.go
EXT_NAME := $(notdir $(EXT))

# The credential-injecting proxy is a Go module in proxy/. It builds to
# proxy/asb-proxy and installs next to the launcher.
PROXY_DIR := proxy
PROXY := $(PROXY_DIR)/asb-proxy
GO ?= go

.PHONY: all help proxy install install-script install-extension install-proxy uninstall test

all: help

help:
	@printf '%s\n' \
	  'asb' \
	  '' \
	  '  make install            install the launcher, the kit extension, and the proxy' \
	  '  make install-script     install the launcher into $(BINDIR)' \
	  '  make install-extension  install the kit extension into $(EXT_DIR)' \
	  '  make install-proxy      build and install the proxy into $(BINDIR)' \
	  '  make proxy              build the proxy only' \
	  '  make test               run the shell and Go test suites' \
	  '  make uninstall          remove the installed launcher, extension, and proxy' \
	  '' \
	  'Override paths with PREFIX=... BINDIR=... EXT_DIR=...' \
	  '(and DESTDIR=... for staged installs).'

# Install both pieces: the launcher a developer runs, and the extension that
# makes a sandboxed kit session start headless.
install: install-script install-extension install-proxy

install-script: $(ASB)
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(ASB) $(DESTDIR)$(BINDIR)/asb
	@printf 'installed %s\n' "$(DESTDIR)$(BINDIR)/asb"

install-extension: $(EXT)
	install -d $(DESTDIR)$(EXT_DIR)
	install -m 0644 $(EXT) $(DESTDIR)$(EXT_DIR)/$(EXT_NAME)
	@printf 'installed %s\n' "$(DESTDIR)$(EXT_DIR)/$(EXT_NAME)"

# Build the proxy from its own module. `cd` keeps the module self-contained.
proxy:
	cd $(PROXY_DIR) && $(GO) build -o asb-proxy .

install-proxy: proxy
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(PROXY) $(DESTDIR)$(BINDIR)/asb-proxy
	@printf 'installed %s\n' "$(DESTDIR)$(BINDIR)/asb-proxy"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/asb
	rm -f $(DESTDIR)$(EXT_DIR)/$(EXT_NAME)
	rm -f $(DESTDIR)$(BINDIR)/asb-proxy
	@printf 'removed %s, %s, and %s\n' \
	  "$(DESTDIR)$(BINDIR)/asb" "$(DESTDIR)$(EXT_DIR)/$(EXT_NAME)" "$(DESTDIR)$(BINDIR)/asb-proxy"

test:
	bash test/run.sh
	cd $(PROXY_DIR) && $(GO) test ./...
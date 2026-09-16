# SPDX-License-Identifier: Apache-2.0
.PHONY: help lint syntax test check format release-check

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

SHFMT ?= shfmt
SHFMT_FLAGS := -i 4 -ci -bn
SHELLCHECK ?= shellcheck

SH_FILES := $(shell find . -type f -name '*.sh' \
	-not -path './.git/*' \
	-not -path './dist/*' \
	-not -path './build/*' \
	| sort)

help:
	@printf '%s\n' \
		'make help           Show this help' \
		'make syntax         bash -n all shell files' \
		'make lint           ShellCheck all shell files' \
		'make format         Format shell files with shfmt' \
		'make test           Run smoke tests (no cluster required)' \
		'make check          syntax + lint + format-check + tests' \
		'make release-check  Verify version, license, and packaging'

syntax:
	@status=0; \
	for f in $(SH_FILES); do \
		bash -n "$$f" || status=1; \
	done; \
	exit $$status

lint:
	@$(SHELLCHECK) -x $(SH_FILES)

format:
	@$(SHFMT) -w $(SHFMT_FLAGS) $(SH_FILES)

format-check:
	@$(SHFMT) -d $(SHFMT_FLAGS) $(SH_FILES)

test:
	@bash tests/run.sh

check: syntax lint format-check test
	@echo '[OK] make check passed'

release-check: check
	@bash scripts/release-check.sh
	@echo '[OK] make release-check passed'

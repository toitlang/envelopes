# Copyright (C) 2023 Toitware ApS.
#
# Use of this source code is governed by a BSD0-style license that can be
# found in the LICENSE_BSD0 file.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

ifeq ($(OS),Windows_NT)
	EXE_SUFFIX := .exe
else
	EXE_SUFFIX :=
endif

# Set to '--update-patches' to update all patches.
UPDATE_PATCHES :=

TOIT_EXEC := toit$(EXE_SUFFIX)

TOIT_DIRECTORY := toit
BUILD_DIRECTORY := build
VARIANTS_DIRECTORY := variants
SYNTHESIZED_DIRECTORY := synthesized
TOIT_SDK_DIRECTORY := $(BUILD_DIRECTORY)/host/sdk

TOOL_ENTRY := tools/main.toit
TOOL_RUN := "$(TOIT_EXEC)" "$(TOOL_ENTRY)"

TOIT_GIT_URL := https://github.com/toitlang/toit.git

.PHONY: all
all:
	@echo "Please specify a target to build."

.PHONY: download-toit
download-toit: | check-toit-version create-toit-directory
	@# If this is not yet a git repository initial it:
	if [ ! -d $(TOIT_DIRECTORY)/.git ] ; then \
		cd "$(TOIT_DIRECTORY)"; \
		git init; \
		git remote add origin "$(TOIT_GIT_URL)"; \
	fi
	@# Fetch.
	(cd "$(TOIT_DIRECTORY)" && git fetch origin)
	@# Checkout the version of the toit repo that we want to use, and initialize
	@# the submodules.
	(cd "$(TOIT_DIRECTORY)" && git checkout "${TOIT_VERSION}")
	(cd "$(TOIT_DIRECTORY)" && git submodule update --init --recursive)

.PHONY: check-toit-version
check-toit-version:
	@if [ -z "$(TOIT_VERSION)" ]; then \
		echo "TOIT_VERSION is not set"; \
		exit 1; \
	fi

.PHONY: create-toit-directory
create-toit-directory:
	mkdir -p "$(TOIT_DIRECTORY)"

.PHONY: synthesize-all
synthesize-all: | create-build-directory create-synthesized-directory
	$(TOOL_RUN) synthesize \
			--toit-root="$(TOIT_DIRECTORY)" \
			--build-root="$(BUILD_DIRECTORY)" \
			--output-root="$(SYNTHESIZED_DIRECTORY)" \
			--sdk-path="$(TOIT_SDK_DIRECTORY)" \
			--variants-root="$(VARIANTS_DIRECTORY)" \
			$(UPDATE_PATCHES) \
			$(shell $(TOOL_RUN) list variants)

.PHONY: update-patches
update-patches:
	$(MAKE) UPDATE_PATCHES=--update-patches synthesize-all

.PHONY: create-build-directory
create-build-directory:
	mkdir -p "$(BUILD_DIRECTORY)"

.PHONY: create-synthesized-directory
create-synthesized-directory:
	mkdir -p "$(SYNTHESIZED_DIRECTORY)"

.PHONY: build-all
build-all:
	for variant in $(shell $(TOOL_RUN) list variants); do \
		$(MAKE) -C "$(SYNTHESIZED_DIRECTORY)/$$variant"; \
	done

.PHONY: build-host
build-host:
	$(MAKE) -C "$(TOIT_DIRECTORY)" BUILD=$(abspath $(BUILD_DIRECTORY)) sdk

# Copyright 2026 Rumen Damyanov <contact@rumenx.com>
# SPDX-License-Identifier: Apache-2.0
#
# apache-cf-realip — Build system
#
# Builds the Rust static library and links it with the C Apache module shim.

APXS      ?= apxs
CARGO     ?= cargo
INSTALL   ?= install

MODULE_NAME = mod_cf_realip
RUST_LIB    = cf_realip
RUST_TARGET = target/release

# Rust static library path
RUST_STATIC_LIB = $(RUST_TARGET)/lib$(RUST_LIB).a

# System libraries needed by Rust's ureq (TLS)
RUST_SYSLIBS = -lpthread -ldl -lm

.PHONY: all clean install test rust-build rust-test

all: rust-build module

# Build the Rust library
rust-build:
	$(CARGO) build --release

# Build the Apache module, linking against the Rust static library
module: rust-build
	$(APXS) -c -o $(MODULE_NAME).so \
		-Wc,-Wall -Wc,-Wextra \
		-Wl,$(RUST_STATIC_LIB) \
		$(RUST_SYSLIBS) \
		src/$(MODULE_NAME).c

# Run Rust unit tests
rust-test:
	$(CARGO) test

# Run shell-based integration tests
test: module
	@echo "Running integration tests..."
	@if [ -d test ]; then \
		for t in test/*_test.sh; do \
			[ -f "$$t" ] && bash "$$t"; \
		done; \
	fi

# Install the module
install: module
	$(APXS) -i -a -n $(RUST_LIB) src/.libs/$(MODULE_NAME).so

clean:
	$(CARGO) clean
	rm -rf src/.libs src/*.o src/*.lo src/*.la src/*.slo
	rm -f $(MODULE_NAME).so

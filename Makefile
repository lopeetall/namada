package = namada

# Some env vars defaults if not specified
NAMADA_E2E_USE_PREBUILT_BINARIES ?= true
NAMADA_E2E_DEBUG ?= true
RUST_BACKTRACE ?= 1
PROPTEST_CASES ?= 100
# Disable shrinking in `make test-pos-sm` for CI runs. If the test fail in CI,
# we only want to get the seed.
PROPTEST_MAX_SHRINK_ITERS ?= 0

cargo := $(env) cargo
rustup := $(env) rustup
debug-env := RUST_BACKTRACE=$(RUST_BACKTRACE) RUST_LOG=$(package)=debug
debug-cargo := $(env) $(debug-env) cargo
# Nightly build is currently used for rustfmt and clippy.
nightly := $(shell cat rust-nightly-version)

# Path to the wasm source for the provided txs and VPs
wasms := wasm
wasms_for_tests := wasm_for_tests

ifdef JOBS
jobs := -j $(JOBS)
else
jobs :=
endif

# TODO upgrade libp2p
audit-ignores += RUSTSEC-2021-0076

# Workspace crates
crates := namada
crates += namada_account
crates += namada_apps
crates += namada_benchmarks
crates += namada_core
crates += namada_encoding_spec
crates += namada_ethereum_bridge
crates += namada_gas
crates += namada_governance
crates += namada_ibc
crates += namada_light_sdk
crates += namada_macros
crates += namada_merkle_tree
crates += namada_parameters
crates += namada_proof_of_stake
crates += namada_replay_protection
crates += namada_sdk
crates += namada_shielded_token
crates += namada_state
crates += namada_storage
crates += namada_test_utils
crates += namada_tests
crates += namada_token
crates += namada_trans_token
crates += namada_tx
crates += namada_tx_env
crates += namada_tx_prelude
crates += namada_vm_env
crates += namada_vote_ext
crates += namada_vp_env
crates += namada_vp_prelude

build:
	$(cargo) build $(jobs) --workspace --exclude namada_benchmarks

build-test:
	$(cargo) +$(nightly) build --tests $(jobs)

build-release:
	$(cargo) build $(jobs) --release --timings --package namada_apps \
		--manifest-path Cargo.toml \
		--no-default-features \
		--features jemalloc \
		--features migrations

build-debug:
	$(cargo) build --package namada_apps --manifest-path Cargo.toml

install-release:
	$(cargo) install --path ./crates/apps --locked

check-release:
	$(cargo) check --release --package namada_apps

package: build-release
	scripts/make-package.sh

check-wasm = $(cargo) check --target wasm32-unknown-unknown --manifest-path $(wasm)/Cargo.toml
check:
	$(cargo) check --workspace && \
	make -C $(wasms) check && \
	make -C $(wasms_for_tests) check

check-mainnet:
	$(cargo) check --workspace --features "mainnet"

# Check that every crate can be built with default features and that namada crate
# can be built for wasm
check-crates:
	rustup target add --toolchain $(nightly) wasm32-unknown-unknown
	$(foreach p,$(crates), echo "Checking $(p)" && cargo +$(nightly) check -Z unstable-options --tests -p $(p) && ) \
		make -C $(wasms) check && \
		make -C $(wasms_for_tests) check && \
		cargo check --package namada --target wasm32-unknown-unknown --no-default-features --features "namada-sdk" && \
		cargo check --package namada_sdk --all-features

clippy-wasm = $(cargo) +$(nightly) clippy --manifest-path $(wasm)/Cargo.toml --all-targets -- -D warnings

clippy:
	$(cargo) +$(nightly) clippy $(jobs) --all-targets -- -D warnings && \
	make -C $(wasms) clippy && \
	make -C $(wasms_for_tests) clippy

clippy-mainnet:
	$(cargo) +$(nightly) clippy --all-targets --features "mainnet" -- -D warnings

clippy-fix:
	$(cargo) +$(nightly) clippy --fix -Z unstable-options --all-targets --allow-dirty --allow-staged

tendermint:
	./scripts/get_tendermint.sh

install: cometbft
	$(cargo) install --path ./crates/apps --locked

cometbft:
	./scripts/get_cometbft.sh

run-ledger:
	# runs the node
	$(cargo) run --bin namadan -- ledger run

run-gossip:
	# runs the node gossip node
	$(cargo) run --bin namadan -- gossip run

reset-ledger:
	# runs the node
	$(cargo) run --bin namadan -- ledger reset

audit:
	$(cargo) audit $(foreach ignore,$(audit-ignores), --ignore $(ignore))

test: test-unit test-e2e test-wasm test-benches

test-coverage:
	# Run integration tests separately because they require `integration`
	# feature (and without coverage)
	$(cargo) +$(nightly) llvm-cov --output-path lcov.info \
		--features namada/testing \
		--lcov \
		-- --skip e2e --skip pos_state_machine_test --skip integration \
		-Z unstable-options --report-time && \
	$(cargo) +$(nightly) test integration:: \
		--features integration \
		-- -Z unstable-options --report-time

# NOTE: `TEST_FILTER` is prepended with `e2e::`. Since filters in `cargo test`
# work with a substring search, TEST_FILTER only works if it contains a string
# that directly follows `e2e::`, e.g. `TEST_FILTER=multitoken_tests` would run
# all tests that start with `e2e::multitoken_tests`.
test-e2e:
	NAMADA_E2E_USE_PREBUILT_BINARIES=$(NAMADA_E2E_USE_PREBUILT_BINARIES) \
	NAMADA_E2E_DEBUG=$(NAMADA_E2E_DEBUG) \
	RUST_BACKTRACE=$(RUST_BACKTRACE) \
	$(cargo) +$(nightly) test $(jobs) e2e::$(TEST_FILTER) \
	-Z unstable-options \
	-- \
	--test-threads=1 \
	--nocapture \
	-Z unstable-options --report-time

# Run integration tests
test-integration:
	RUST_BACKTRACE=$(RUST_BACKTRACE) \
	$(cargo) +$(nightly) test $(jobs) integration::$(TEST_FILTER)  --features integration \
	-Z unstable-options \
	-- \
	--test-threads=1 \
	-Z unstable-options --report-time

test-unit:
	$(cargo) +$(nightly) test \
		$(TEST_FILTER) \
		$(jobs) \
		-- --skip e2e --skip integration --skip pos_state_machine_test \
		-Z unstable-options --report-time

test-unit-with-coverage:
	$(cargo) +$(nightly) llvm-cov --output-path lcov.info \
		--features namada/testing \
		--lcov \
		-- --skip e2e --skip pos_state_machine_test --skip integration \
		-Z unstable-options --report-time

test-unit-mainnet:
	$(cargo) +$(nightly) test \
		--features "mainnet" \
		$(TEST_FILTER) \
		$(jobs) \
		-- --skip e2e --skip integration \
		-Z unstable-options --report-time

test-unit-debug:
	$(debug-cargo) +$(nightly) test \
		$(jobs) \
		$(TEST_FILTER) \
		-- --skip e2e --skip integration --skip pos_state_machine_test \
		--nocapture \
		-Z unstable-options --report-time

test-wasm:
	make -C $(wasms) test

test-wasm-template = $(cargo) +$(nightly) test \
	--manifest-path $(wasm)/Cargo.toml \
		-- \
		-Z unstable-options --report-time
test-wasm-templates:
	$(foreach wasm,$(wasm_templates),$(test-wasm-template) && ) true

test-debug:
	$(debug-cargo) +$(nightly) test \
		-- \
		--nocapture \
		-Z unstable-options --report-time

# Test that the benchmarks run successfully without performing measurement
test-benches:
	$(cargo) +$(nightly) test --package namada_benchmarks --benches

# Run PoS state machine tests with shrinking disabled by default (can be 
# overridden with `PROPTEST_MAX_SHRINK_ITERS`)
test-pos-sm:
	cd crates/proof_of_stake && \
		RUST_BACKTRACE=1 \
		PROPTEST_CASES=$(PROPTEST_CASES) \
		PROPTEST_MAX_SHRINK_ITERS=$(PROPTEST_MAX_SHRINK_ITERS) \
		RUSTFLAGS='-C debuginfo=2 -C debug-assertions=true -C overflow-checks=true' \
		cargo test pos_state_machine_test --release 

fmt-wasm = $(cargo) +$(nightly) fmt --manifest-path $(wasm)/Cargo.toml
fmt:
	$(cargo) +$(nightly) fmt --all && make -C $(wasms) fmt

fmt-check-wasm = $(cargo) +$(nightly) fmt --manifest-path $(wasm)/Cargo.toml -- --check
fmt-check:
	$(cargo) +$(nightly) fmt --all -- --check && make -C $(wasms) fmt-check

watch:
	$(cargo) watch

clean:
	$(cargo) clean

bench:
	$(cargo) bench --package namada_benchmarks 

build-doc:
	$(cargo) doc --no-deps

doc:
	# build and opens the docs in browser
	$(cargo) doc --open

build-wasm-image-docker:
	docker build -t namada-wasm - < docker/namada-wasm/Dockerfile

build-wasm-scripts-docker: build-wasm-image-docker
	docker run --rm -v ${PWD}:/__w/namada/namada namada-wasm make build-wasm-scripts

debug-wasm-scripts-docker: build-wasm-image-docker
	docker run --rm -v ${PWD}:/usr/local/rust/wasm namada-wasm make debug-wasm-scripts

# Build the validity predicate and transactions wasm
build-wasm-scripts:
	rm $(wasms)/*.wasm || true
	make -C $(wasms)
	make opt-wasm
	make checksum-wasm

# Debug build the validity predicate and transactions wasm
debug-wasm-scripts:
	rm wasm/*.wasm || true
	make -C $(wasms) debug
	make opt-wasm
	make checksum-wasm

# Build the validity predicate and transactions wasm for tests
build-wasm-tests-scripts:
	rm $(wasms_for_tests)/*.wasm || true
	make -C $(wasms_for_tests)
	make opt-wasm-tests

# Debug build the validity predicate and transactions wasm for tests
debug-wasm-tests-scripts:
	rm $(wasms_for_tests)/*.wasm || true
	make -C $(wasms_for_tests) debug
	make opt-wasm-tests

# need python
checksum-wasm:
	python3 wasm/checksums.py

# this command needs wasm-opt installed
opt-wasm:
	@for file in $(shell ls wasm/*.wasm); do wasm-opt -Oz -o $${file} $${file}; done

opt-wasm-tests:
	@for file in $(shell ls wasm_for_tests/*.wasm); do wasm-opt -Oz -o $${file} $${file}; done

clean-wasm-scripts:
	make -C $(wasms) clean

dev-deps:
	$(rustup) toolchain install $(nightly)
	$(rustup) target add wasm32-unknown-unknown
	$(rustup) component add rustfmt clippy miri --toolchain $(nightly)
	$(cargo) install cargo-watch unclog wasm-opt

test-miri:
	$(cargo) +$(nightly) miri setup
	$(cargo) +$(nightly) clean
	MIRIFLAGS="-Zmiri-disable-isolation" $(cargo) +$(nightly) miri test


.PHONY : build check build-release clippy install run-ledger run-gossip reset-ledger test test-debug fmt watch clean build-doc doc build-wasm-scripts-docker debug-wasm-scripts-docker build-wasm-scripts debug-wasm-scripts clean-wasm-scripts dev-deps test-miri test-unit bench

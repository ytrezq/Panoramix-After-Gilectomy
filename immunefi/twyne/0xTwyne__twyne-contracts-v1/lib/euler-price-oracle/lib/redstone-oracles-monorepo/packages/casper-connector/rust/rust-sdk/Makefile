CLIPPY=cargo clippy --release --fix --allow-dirty --allow-staged
DOC=cargo doc --no-deps --document-private-items
TEST=RUST_BACKTRACE=full cargo test --features="helpers"
FEATURE_SETS="crypto_k256" "crypto_k256,network_casper" "crypto_secp256k1" "crypto_secp256k1,network_casper" "crypto_secp256k1,network_radix"
WASM32_FEATURE_SETS="crypto_radix" "crypto_radix,network_radix"

prepare:
	@rustup target add wasm32-unknown-unknown
	cargo install wasm-bindgen-cli wasm-pack

test: clippy
	@for features in $(WASM32_FEATURE_SETS); do \
        echo "Running tests with features: $$features"; \
        (wasm-pack test --node --features="helpers" --features=$$features); \
    done
	@for features in $(FEATURE_SETS); do \
        echo "Running tests with features: $$features"; \
        ($(TEST) --features=$$features); \
    done

docs:
	@for features in $(FEATURE_SETS); do \
        echo "Documenting redstone with features: $$features"; \
        (rm -rf ./target/doc && $(DOC) --features=$$features && mkdir -p ../target/rust-docs/redstone && cp -r ../target/doc ../target/rust-docs/redstone/$$features); \
    done

coverage:
	cargo install grcov --version=0.5.15
	CARGO_INCREMENTAL=0 \
		RUSTFLAGS="-Zprofile -Ccodegen-units=1 -Copt-level=0 -Clink-dead-code -Coverflow-checks=off -Zpanic_abort_tests -Cpanic=abort" \
        RUSTDOCFLAGS="-Cpanic=abort" cargo build --features="crypto_k256"
	CARGO_INCREMENTAL=0 \
		RUSTFLAGS="-Zprofile -Ccodegen-units=1 -Copt-level=0 -Clink-dead-code -Coverflow-checks=off -Zpanic_abort_tests -Cpanic=abort" \
        RUSTDOCFLAGS="-Cpanic=abort" $(TEST) --features="crypto_k256"

clippy: prepare
	@for features in $(FEATURE_SETS); do \
        ($(CLIPPY) --all-targets --features=$$features -- -D warnings); \
    done

check-lint: clippy
	cargo fmt -- --check

lint: clippy
	cargo fmt

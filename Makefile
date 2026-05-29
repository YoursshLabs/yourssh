.PHONY: core swift-bindings open clean

core:
	@bash scripts/build-core.sh

swift-bindings:
	@cd core && cargo run --bin uniffi-bindgen generate src/yourssh.udl --language swift --out-dir ../macos/YourSSH/Generated

open:
	@cd macos && xcodegen generate && open YourSSH.xcodeproj

clean:
	@cd core && cargo clean
	@rm -rf macos/YourSSH/Generated

setup:
	@echo "Checking dependencies..."
	@which cargo || (echo "Install Rust: https://rustup.rs" && exit 1)
	@which xcodegen || brew install xcodegen
	@rustup target add aarch64-apple-darwin x86_64-apple-darwin
	@echo "✓ All dependencies ready"

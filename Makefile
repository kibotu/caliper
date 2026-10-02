.PHONY: build release install clean help format test analyze example

# Build the debug version
build:
	swift build

# Build the release version
release:
	swift build -c release

# Run the test suite
test:
	swift test

# Install to /usr/local/bin
install: release
	@echo "Installing caliper to /usr/local/bin..."
	@cp .build/release/caliper /usr/local/bin/caliper
	@echo "✅ Installation complete! Run 'caliper --help' to get started."

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Show help
help: build
	.build/debug/caliper --help

# Format code (requires swift-format)
format:
	swift-format --in-place --recursive Sources/

# Full analysis with automatic HTML generation
analyze: release
	@if [ -z "$(IPA_PATH)" ]; then \
		echo "❌ Error: IPA_PATH not set"; \
		echo ""; \
		echo "Usage:"; \
		echo "  make analyze IPA_PATH=path/to/app.ipa [OPTIONS]"; \
		echo ""; \
		echo "Options:"; \
		echo "  LINK_MAP_PATH=path/to/LinkMap.txt    - LinkMap for accurate binary sizes"; \
		echo "  OWNERSHIP_FILE=module-ownership.yml  - Module ownership tracking"; \
		echo "  PACKAGE_RESOLVED=Package.resolved    - Swift package versions"; \
		echo "  PACKAGE_MAPPING=packages.yml         - Module name to package identity"; \
		echo "  OUTPUT_DIR=build/reports              - Where to write reports (default: .)"; \
		echo "  MAX_PACKAGE_SIZE=52428800             - Fail above this IPA size in bytes"; \
		echo "  MAX_INSTALL_SIZE=104857600            - Fail above this install size in bytes"; \
		echo ""; \
		echo "Example:"; \
		echo "  make analyze IPA_PATH=MyApp.ipa LINK_MAP_PATH=LinkMap.txt"; \
		exit 1; \
	fi
	@CMD=".build/release/caliper --ipa-path $(IPA_PATH)"; \
	if [ -n "$(LINK_MAP_PATH)" ]; then CMD="$$CMD --link-map-path $(LINK_MAP_PATH)"; fi; \
	if [ -n "$(OWNERSHIP_FILE)" ]; then CMD="$$CMD --ownership-file $(OWNERSHIP_FILE)"; fi; \
	if [ -n "$(PACKAGE_RESOLVED)" ]; then CMD="$$CMD --package-resolved-path $(PACKAGE_RESOLVED)"; fi; \
	if [ -n "$(PACKAGE_MAPPING)" ]; then CMD="$$CMD --package-mapping-file $(PACKAGE_MAPPING)"; fi; \
	if [ -n "$(OUTPUT_DIR)" ]; then CMD="$$CMD --output-dir $(OUTPUT_DIR)"; fi; \
	if [ -n "$(MAX_PACKAGE_SIZE)" ]; then CMD="$$CMD --max-package-size $(MAX_PACKAGE_SIZE)"; fi; \
	if [ -n "$(MAX_INSTALL_SIZE)" ]; then CMD="$$CMD --max-install-size $(MAX_INSTALL_SIZE)"; fi; \
	echo "🚀 Running: $$CMD"; \
	echo ""; \
	$$CMD

# Quick example run
example: release
	@if [ -z "$(IPA_PATH)" ]; then \
		echo "❌ Error: IPA_PATH not set"; \
		echo ""; \
		echo "Usage: make example IPA_PATH=path/to/app.ipa"; \
		exit 1; \
	fi
	@CMD=".build/release/caliper --ipa-path $(IPA_PATH)"; \
	if [ -n "$(LINK_MAP_PATH)" ]; then CMD="$$CMD --link-map-path $(LINK_MAP_PATH)"; fi; \
	if [ -n "$(OWNERSHIP_FILE)" ]; then CMD="$$CMD --ownership-file $(OWNERSHIP_FILE)"; fi; \
	echo "🚀 Running: $$CMD"; \
	echo ""; \
	$$CMD
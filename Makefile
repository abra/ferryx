.PHONY: get l10n format format-check analyze test test-dart test-rust test-macos core codegen icons verify run build-macos dmg release build-linux build-windows linux clean help

FLUTTER ?= fvm flutter
DART ?= fvm dart
CARGO ?= cargo
# Pagecraft pins its compiler separately; keep cargo and rustc on that toolchain.
PAGECRAFT_RUST_ENV = PATH="$$(dirname "$$(rustup which rustc)"):$$PATH"

PACKAGES = \
	packages/domain_models \
	packages/monitoring \
	packages/ferryx_backend \
	packages/ferryx_localizations \
	packages/component_library \
	packages/shortcuts \
	packages/preferences_service \
	packages/file_repository \
	packages/operations_service \
	packages/platform_services \
	packages/terminal_service \
	packages/thumbnail_service \
	packages/native_text_selection \
	packages/pagecraft \
	packages/features/panels \
	packages/features/viewer \
	packages/features/find \
	packages/features/settings \
	packages/features/palette \
	packages/features/terminal \
	packages/features/sync \
	packages/features/checksums \
	packages/features/duplicates \
	packages/network_service \
	packages/features/network

ROOT_ANALYZE_PATHS = lib test
DART_PACKAGES = packages/pdfium_dart

## Install dependencies for root and all packages
get:
	$(FLUTTER) pub get
	@set -e; for pkg in $(PACKAGES); do \
		echo "▶ pub get $$pkg"; \
		(cd $$pkg && $(FLUTTER) pub get); \
	done
	@set -e; for pkg in $(DART_PACKAGES); do \
		echo "▶ pub get $$pkg"; \
		(cd $$pkg && $(DART) pub get); \
	done

## Regenerate localizations (ARB → Dart)
l10n:
	cd packages/ferryx_localizations && $(FLUTTER) gen-l10n

## Rebuild every platform's app icon from the masters in brand/ (needs rsvg-convert)
icons:
	python3 brand/build_icons.py

## Regenerate flutter_rust_bridge bindings after changing rust/crates/ferryx_api/src/api
codegen:
	flutter_rust_bridge_codegen generate

## Format Dart and Rust code
format:
	$(DART) format ./
	cd rust && $(CARGO) fmt
	cd packages/pagecraft/rust && $(PAGECRAFT_RUST_ENV) $(CARGO) fmt

## Check formatting without changing files
format-check:
	$(DART) format --output=none --set-exit-if-changed $(ROOT_ANALYZE_PATHS) packages
	cd rust && $(CARGO) fmt --check
	cd packages/pagecraft/rust && $(PAGECRAFT_RUST_ENV) $(CARGO) fmt --check

## Analyze all Dart code and lint Rust
analyze:
	$(FLUTTER) analyze $(ROOT_ANALYZE_PATHS)
	@set -e; for pkg in $(PACKAGES); do \
		echo "▶ analyze $$pkg"; \
		(cd $$pkg && $(FLUTTER) analyze); \
	done
	@set -e; for pkg in $(DART_PACKAGES); do \
		echo "▶ analyze $$pkg"; \
		(cd $$pkg && $(DART) analyze); \
	done
	cd rust && $(CARGO) clippy --workspace --all-targets -- -D warnings
	cd packages/pagecraft/rust && $(PAGECRAFT_RUST_ENV) $(CARGO) clippy --locked --all-targets -- -D warnings

## Run every Dart and Rust test
test: test-rust test-dart

## Rust unit and integration tests
test-rust:
	cd rust && $(CARGO) test --workspace
	cd packages/pagecraft/rust && $(PAGECRAFT_RUST_ENV) $(CARGO) test --locked

## Build the host dylib the real-core Dart tests load (rust/target/debug)
core:
	cd rust && $(CARGO) build -p ferryx_api

## Dart tests for every package that has a test directory, then the app's; all run, failures listed at the end
test-dart: core
	@failed=""; for pkg in $(PACKAGES) .; do \
		if [ -d $$pkg/test ] && [ -n "$$(ls -A $$pkg/test 2>/dev/null)" ]; then \
			echo "▶ test $$pkg"; \
			(cd $$pkg && $(FLUTTER) test) || failed="$$failed $$pkg"; \
		fi; \
	done; \
	for pkg in $(DART_PACKAGES); do \
		echo "▶ test $$pkg"; \
		(cd $$pkg && $(DART) test) || failed="$$failed $$pkg"; \
	done; \
	if [ -n "$$failed" ]; then echo "✗ tests failed in:$$failed"; exit 1; fi

## Full local quality gate
verify: format-check analyze test

## Native AppKit window tests (macOS with Xcode, in addition to verify)
test-macos:
	xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath build/macos -only-testing:RunnerTests test

## Run the desktop app on the host platform
run:
	$(FLUTTER) run -d $(shell uname -s | tr A-Z a-z | sed 's/darwin/macos/')

## Release build for macOS
build-macos:
	$(FLUTTER) build macos --release

## macOS disk image of the release build: build/Ferryx-<version>.dmg
dmg: build-macos
	tools/macos/dmg.sh

## Publish the disk image as the GitHub release v<version> (gh; commit and push first)
release:
	tools/macos/release.sh check
	$(MAKE) dmg
	tools/macos/release.sh publish

## Release build for Linux (run on Linux)
build-linux:
	$(FLUTTER) build linux --release

## Release build for Windows (run on Windows)
build-windows:
	$(FLUTTER) build windows --release

## Quality gate in a Linux container (Docker); others: LINUX="test-dart build-linux"
LINUX ?= verify
linux:
	docker build -t ferryx-linux \
		--build-arg FLUTTER_VERSION=$$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' .fvmrc) \
		tools/linux
	docker run --rm -v "$(CURDIR)":/src:ro -v ferryx-linux-work:/work \
		-v ferryx-linux-pub:/root/.pub-cache -v ferryx-linux-cargo:/root/.cargo/registry \
		ferryx-linux /src/tools/linux/run.sh $(LINUX)

## Remove build artifacts
clean:
	$(FLUTTER) clean
	cd rust && $(CARGO) clean
	cd packages/pagecraft/rust && $(PAGECRAFT_RUST_ENV) $(CARGO) clean

## Show available targets
help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk '/^## /{d=substr($$0,4);next} /^[a-z][a-z0-9-]*:/{if(d!=""){sub(/:.*/,"");printf "  %-14s %s\n",$$0,d};d=""}' Makefile
	@echo ""

# Default to the newest simulator runtime installed on this machine; override
# with an env var (e.g. `IOS_VERSION=26.0 make test-ios`) to pin a specific version.
# Snapshot tests are rendering-sensitive to OS versions, so pin explicitly for snapshot-consistent runs.
IOS_VERSION ?= $(shell xcrun simctl list runtimes available | grep -oE '^iOS [0-9]+\.[0-9]+' | sort -V | tail -1 | cut -d' ' -f2)
TVOS_VERSION ?= $(shell xcrun simctl list runtimes available | grep -oE '^tvOS [0-9]+\.[0-9]+' | sort -V | tail -1 | cut -d' ' -f2)
WATCHOS_VERSION ?= $(shell xcrun simctl list runtimes available | grep -oE '^watchOS [0-9]+\.[0-9]+' | sort -V | tail -1 | cut -d' ' -f2)
VISIONOS_VERSION ?= $(shell xcrun simctl list runtimes available | grep -oE '^visionOS [0-9]+\.[0-9]+' | sort -V | tail -1 | cut -d' ' -f2)

PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS $(IOS_VERSION),iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS $(TVOS_VERSION),TV)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS $(WATCHOS_VERSION),Watch)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS $(VISIONOS_VERSION),Vision)

default: test

test: test-macos test-ios test-tvos test-watchos test-visionos

test-quick:
	@echo "Running fast macOS SwiftPM tests..."
	swift test

test-macos:
	@echo "Testing macOS..."
	xcodebuild test -scheme RemodexTextKit -destination platform="$(PLATFORM_MACOS)"

test-ios:
	@if [ -z "$(IOS_VERSION)" ]; then echo "error: no iOS simulator runtime installed (xcrun simctl list runtimes)"; exit 1; fi
	@echo "Testing iOS $(IOS_VERSION)..."
	xcodebuild test -scheme RemodexTextKit -destination platform="$(PLATFORM_IOS)"

test-tvos:
	@if [ -z "$(TVOS_VERSION)" ]; then echo "error: no tvOS simulator runtime installed (xcrun simctl list runtimes)"; exit 1; fi
	@echo "Testing tvOS $(TVOS_VERSION)..."
	xcodebuild test -scheme RemodexTextKit -destination platform="$(PLATFORM_TVOS)"

test-watchos:
	@if [ -z "$(WATCHOS_VERSION)" ]; then echo "error: no watchOS simulator runtime installed (xcrun simctl list runtimes)"; exit 1; fi
	@echo "Testing watchOS $(WATCHOS_VERSION)..."
	xcodebuild test -scheme RemodexTextKit -destination platform="$(PLATFORM_WATCHOS)"

test-visionos:
	@if [ -z "$(VISIONOS_VERSION)" ]; then echo "error: no visionOS simulator runtime installed (xcrun simctl list runtimes)"; exit 1; fi
	@echo "Testing visionOS $(PLATFORM_VISIONOS)..."
	xcodebuild test -scheme RemodexTextKit -destination platform="$(PLATFORM_VISIONOS)"

format:
	swift format \
		--configuration .swift-format \
		--ignore-unparsable-files \
		--in-place \
		--parallel \
		--recursive \
		./Package.swift ./Sources ./Tests ./Examples

bundle-prism:
	@echo "Bundling Prism.js..."
	./Scripts/bundle-prism.sh

build-demo:
	@echo "Building RemodexTextKit demo for iOS..."
	xcodebuild build -workspace RemodexTextKit.xcworkspace -scheme RemodexTextKitDemo -destination platform="$(PLATFORM_IOS)" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
	@echo "Building RemodexTextKit demo for macOS..."
	xcodebuild build -workspace RemodexTextKit.xcworkspace -scheme RemodexTextKitDemo -destination platform="$(PLATFORM_MACOS)" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

.PHONY: format test test-quick bundle-prism build-demo

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef

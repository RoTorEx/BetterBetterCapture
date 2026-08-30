SHELL := /bin/sh

PROJECT_NAME := BetterBetterCapture
PROJECT_FILE := BetterBetterCapture.xcodeproj
SCHEME := BetterBetterCapture
DESTINATION ?= platform=macOS
CONFIGURATION ?= Debug
CONSTRUCTION_SIDE ?= $(HOME)/construction_side
PROJECT_CONSTRUCTION_SIDE ?= $(CONSTRUCTION_SIDE)/better-better-capture
DERIVED_DATA_PATH ?= $(PROJECT_CONSTRUCTION_SIDE)/DerivedData.noindex
SOURCE_PACKAGES_PATH ?= $(PROJECT_CONSTRUCTION_SIDE)/SourcePackages
SWIFTLINT_CACHE_PATH ?= $(PROJECT_CONSTRUCTION_SIDE)/SwiftLintCache
LOCAL_APPLICATIONS_DIR ?= $(HOME)/Applications
LOCAL_APP_PATH := $(LOCAL_APPLICATIONS_DIR)/$(PROJECT_NAME).app
XCODEBUILD ?= xcodebuild

XCODE_COMMON := \
	-project "$(PROJECT_FILE)" \
	-scheme "$(SCHEME)" \
	-destination "$(DESTINATION)" \
	-derivedDataPath "$(DERIVED_DATA_PATH)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_PATH)" \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	COMPILER_INDEX_STORE_ENABLE=NO

.DEFAULT_GOAL := help

.PHONY: help install install-local build test lint check release release-push vibe-kernel-path vibe-kernel-set vibe-pull

help:
	@printf "BetterBetterCapture commands:\n"
	@printf "  make install\n"
	@printf "  make install-local\n"
	@printf "  make build\n"
	@printf "  make test\n"
	@printf "  make lint\n"
	@printf "  make check\n"
	@printf "  make release\n"
	@printf "  make release-push\n"
	@printf "  make vibe-pull\n"
	@printf "\nBuild state: %s\n" "$(PROJECT_CONSTRUCTION_SIDE)"

install:
	@command -v brew >/dev/null 2>&1 || { echo "ERROR: Homebrew is required to install SwiftLint." >&2; exit 1; }
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint

install-local:
	@mkdir -p "$(PROJECT_CONSTRUCTION_SIDE)" "$(LOCAL_APPLICATIONS_DIR)"
	@$(XCODEBUILD) build $(XCODE_COMMON) -configuration Release -quiet
	@rm -rf "$(LOCAL_APP_PATH)"
	@ditto "$(DERIVED_DATA_PATH)/Build/Products/Release/$(PROJECT_NAME).app" "$(LOCAL_APP_PATH)"
	@rm -rf "$(DERIVED_DATA_PATH)/Build/Products/Debug/$(PROJECT_NAME).app"
	@touch "$(LOCAL_APP_PATH)"
	@printf "Installed %s\n" "$(LOCAL_APP_PATH)"

build:
	@mkdir -p "$(PROJECT_CONSTRUCTION_SIDE)"
	@$(XCODEBUILD) build $(XCODE_COMMON) -configuration "$(CONFIGURATION)" -quiet

test:
	@mkdir -p "$(PROJECT_CONSTRUCTION_SIDE)"
	@$(XCODEBUILD) test $(XCODE_COMMON) -configuration Debug -quiet

lint:
	@command -v swiftlint >/dev/null 2>&1 || { echo "ERROR: SwiftLint is missing. Run: make install" >&2; exit 1; }
	@mkdir -p "$(SWIFTLINT_CACHE_PATH)"
	@swiftlint lint --strict --baseline .swiftlint-baseline.json --cache-path "$(SWIFTLINT_CACHE_PATH)"

check: lint test

release:
	@sh scripts/release.sh

release-push:
	@set -eu; \
	branch="$$(git branch --show-current)"; \
	test "$$branch" = "main" || { echo "ERROR: release push requires main, not $$branch" >&2; exit 1; }; \
	version="$$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);/\1/p' "$(PROJECT_FILE)/project.pbxproj" | head -n 1)"; \
	tag="v$$version"; \
	git rev-parse -q --verify "refs/tags/$$tag" >/dev/null || { echo "ERROR: missing $$tag. Run make release." >&2; exit 1; }; \
	git push origin main --follow-tags

vibe-kernel-path:
	@test -f .vibe/KERNEL_SOURCE || { echo "Missing .vibe/KERNEL_SOURCE. Run: make vibe-kernel-set" >&2; exit 1; }
	@sed -n '1p' .vibe/KERNEL_SOURCE

vibe-kernel-set:
	@mkdir -p .vibe; \
	if [ -n "$(KERNEL)" ]; then kernel_root="$(KERNEL)"; else printf "Kernel path: "; read -r kernel_root; fi; \
	case "$$kernel_root" in /*) ;; *) echo "ERROR: kernel path must be absolute." >&2; exit 1;; esac; \
	test -f "$$kernel_root/tools/vibe-pull" || { echo "ERROR: invalid kernel path: $$kernel_root" >&2; exit 1; }; \
	printf "%s\n" "$$kernel_root" > .vibe/KERNEL_SOURCE

vibe-pull:
	@test -f .vibe/KERNEL_SOURCE || { echo "Missing .vibe/KERNEL_SOURCE. Run: make vibe-kernel-set" >&2; exit 1; }
	@kernel_root="$$(sed -n '1p' .vibe/KERNEL_SOURCE)"; \
	python3 "$$kernel_root/tools/vibe-pull" .

# VIBE:KERNEL_MAKE_START

.PHONY: vibe-propose

vibe-propose:
	@test -f .vibe/KERNEL_SOURCE || { echo "Missing .vibe/KERNEL_SOURCE. Run: make vibe-kernel-set" >&2; exit 1; }
	@kernel_root="$$(sed -n '1p' .vibe/KERNEL_SOURCE)"; \
	test -f "$$kernel_root/tools/vibe-propose" || { echo "Missing $$kernel_root/tools/vibe-propose. Update the kernel source first." >&2; exit 1; }; \
	python3 "$$kernel_root/tools/vibe-propose" .

# VIBE:KERNEL_MAKE_END

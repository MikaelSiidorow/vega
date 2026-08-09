.PHONY: check format lint test test-unit test-ui build-for-testing build-wger-api refresh-wger-schema

WGER_SCHEMA_URL ?=
IOS_SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest
XCODEBUILD_FLAGS ?=
XCODE_RESULT_BUNDLE_PATH ?=
XCODEBUILD_TEST_SELECTION ?=
SWIFT_FORMAT_PATHS := Vega VegaTests VegaUITests \
	Packages/WgerAPI/Package.swift Packages/WgerAPI/Sources/WgerAPI

check:
	$(MAKE) lint
	$(MAKE) test-unit

format:
	xcrun swift-format format --in-place --recursive $(SWIFT_FORMAT_PATHS)

lint:
	xcrun swift-format lint --strict --recursive $(SWIFT_FORMAT_PATHS)

test:
	@temporary_directory="$$(mktemp -d /tmp/vega-tests.XXXXXX)"; \
	result_bundle_path='$(XCODE_RESULT_BUNDLE_PATH)'; \
	if test -z "$$result_bundle_path"; then \
		result_bundle_path="$$temporary_directory/Vega.xcresult"; \
	fi; \
	trap 'rm -rf "$$temporary_directory"' 0 1 2 15; \
	xcodebuild \
		-quiet \
		$(XCODEBUILD_FLAGS) \
		$(XCODEBUILD_TEST_SELECTION) \
		-project Vega.xcodeproj \
		-scheme Vega \
		-destination '$(IOS_SIMULATOR_DESTINATION)' \
		-resultBundlePath "$$result_bundle_path" \
		test

test-unit: XCODEBUILD_TEST_SELECTION := -only-testing:VegaTests -parallel-testing-enabled NO
test-unit: test

test-ui: XCODEBUILD_TEST_SELECTION := -only-testing:VegaUITests -parallel-testing-enabled NO
test-ui: test

build-wger-api:
	xcodebuild \
		-quiet \
		$(XCODEBUILD_FLAGS) \
		-project Vega.xcodeproj \
		-scheme WgerAPI \
		-destination 'generic/platform=iOS Simulator' \
		build

refresh-wger-schema:
	@test -n "$(WGER_SCHEMA_URL)" || { \
		echo 'Set WGER_SCHEMA_URL to a wger 2.6 OpenAPI schema URL.' >&2; \
		exit 2; \
	}
	@temporary_directory="$$(mktemp -d /tmp/vega-schema.XXXXXX)"; \
	trap 'rm -rf "$$temporary_directory"' 0 1 2 15; \
	curl --fail --silent --show-error \
		-H 'Accept: application/json' \
		"$(WGER_SCHEMA_URL)" \
		-o "$$temporary_directory/server-openapi.json"; \
	test "$$(jq -r '.openapi' "$$temporary_directory/server-openapi.json")" = '3.0.3'; \
	test "$$(jq -r '.info.version' "$$temporary_directory/server-openapi.json")" = '2.6.0'; \
	sh Scripts/normalize-wger-openapi.sh \
		"$$temporary_directory/server-openapi.json" \
		"$$temporary_directory/openapi.json"; \
	cp "$$temporary_directory/server-openapi.json" \
		Packages/WgerAPI/Sources/WgerAPI/server-openapi.json; \
	cp "$$temporary_directory/openapi.json" \
		Packages/WgerAPI/Sources/WgerAPI/openapi.json

build-for-testing:
	@temporary_directory="$$(mktemp -d /tmp/vega-xcresult.XXXXXX)"; \
	trap 'rm -rf "$$temporary_directory"' 0 1 2 15; \
	xcodebuild \
		-quiet \
		$(XCODEBUILD_FLAGS) \
		-project Vega.xcodeproj \
		-scheme Vega \
		-destination 'generic/platform=iOS Simulator' \
		-resultBundlePath "$$temporary_directory/Vega.xcresult" \
		clean build-for-testing

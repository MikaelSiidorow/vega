.PHONY: build-for-testing

build-for-testing:
	@temporary_directory="$$(mktemp -d /tmp/vega-xcresult.XXXXXX)"; \
	trap 'rm -rf "$$temporary_directory"' 0 1 2 15; \
	xcodebuild \
		-quiet \
		-project Vega.xcodeproj \
		-scheme Vega \
		-destination 'generic/platform=iOS Simulator' \
		-resultBundlePath "$$temporary_directory/Vega.xcresult" \
		clean build-for-testing

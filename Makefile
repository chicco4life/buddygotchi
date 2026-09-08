# Root Makefile: the next-generation app in app/. The archived generation has
# its own Makefile under archived/.
.PHONY: build test run lint
build:
	cd app && swift build --product Boop && swift build --product BoopSignal
test:
	cd app && swift test
run:
	cd app && swift run Boop
lint:
	cd app && (command -v swift-format >/dev/null && swift-format lint -r Boop Tests || echo "swift-format not installed")

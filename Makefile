
.PHONY: all clean test test-release build release

build:
	echo "Building the project..."

clean:
	echo "Cleaning the project..."

lint:
	luacheck Core.lua ./modules/ tests/

test:
	busted --verbose ./tests/*.lua	
	$(MAKE) test-release

test-release:
	python3 -B -m unittest discover -s tests -p release_archive_test.py -v

release:
	python3 scripts/build_release.py

all: clean test build

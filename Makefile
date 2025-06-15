
.PHONY: all clean test build release

build:
	echo "Building the project..."

clean:
	echo "Cleaning the project..."

lint:
	luacheck Core.lua ./modules/ tests/

test:
	busted --verbose ./tests/*.lua	

release:
	mkdir -p release
	cp RLHelper.toc release/
	cp RLHelper.xml release/
	cp Core.lua release/
	cp -r modules release/
	cp -r lib release/
	cd release && zip -r ../RLHelper.zip .

all: clean test build
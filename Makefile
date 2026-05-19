
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
	mkdir -p release/RLHelper
	cp RLHelper.toc release/RLHelper
	cp RLHelper.xml release/RLHelper
	cp Core.lua release/RLHelper
	cp -r modules release/RLHelper
	cp -r lib release/RLHelper
	cp -r Libs release/RLHelper
	cd release && zip -r ../RLHelper.zip .

all: clean test build
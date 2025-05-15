
.PHONY: all clean test build

build:
	echo "Building the project..."

clean:
	echo "Cleaning the project..."

lint:
	luacheck Core.lua ./modules/ tests/

test:
	busted --verbose ./tests/*.lua	

all: clean test build
.PHONY: build
.PHONY: test
.PHONY: clean

build:
	dub build --build=release

build-docs:
	dub build --build=ddox

test:
	dub test

clean:
	dub clean

run-examples: run-quickstartExample\
	run-jsonExample \
	run-javaPropertiesExample \
	run-valueSubstitutionExample \
	run-manipulationExample

run-quickstartExample:
	dub run --build=release --config=quickstartExample

run-jsonExample:
	dub run --build=release --config=jsonExample

run-javaPropertiesExample:
	dub run --build=release --config=javaPropertiesExample

run-valueSubstitutionExample:
	dub run --build=release --config=valueSubstitutionExample

run-manipulationExample:
	dub run --build=release --config=manipulationExample
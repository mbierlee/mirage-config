.PHONY: build
.PHONY: test
.PHONY: clean

build:
	dub build --build=release

test:
	dub test

clean:
	dub clean

run-examples: run-jsonExample \
	run-javaPropertiesExample \
	run-valueSubstitutionExample \
	run-manipulationExample

run-jsonExample:
	dub run --build=release --config=jsonExample

run-javaPropertiesExample:
	dub run --build=release --config=javaPropertiesExample

run-valueSubstitutionExample:
	dub run --build=release --config=valueSubstitutionExample

run-manipulationExample:
	dub run --build=release --config=manipulationExample
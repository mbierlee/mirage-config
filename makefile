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
	run-valueSubstitutionExample

run-jsonExample:
	dub run --build=release --config=jsonExample

run-valueSubstitutionExample:
	dub run --build=release --config=valueSubstitutionExample
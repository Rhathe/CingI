FORCE:

deps: FORCE
	mix deps.get

test:
	mix test

build-cli:
	mix escript.build

test-cli:
	make build-cli
	./cingi --file test/mission_plans/example1.plan

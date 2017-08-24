FORCE:

deps: FORCE
	mix deps.get

test: FORCE
	mix test
	make test-distributed

test-distributed: FORCE
	mix test --only distributed

build-cli:
	mix escript.build

test-cli:
	make build-cli
	#./cingi --file test/mission_plans/example1.plan
	./cingi --file test/mission_plans/exits.plan

kill-all-epmd:
	for pid in $$(ps -ef | grep "/usr/lib/erlang/erts-9.0/bin/epmd -daemon" | awk '{print $$2}'); do kill -9 $$pid; done

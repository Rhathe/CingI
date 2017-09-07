FORCE:

deps: FORCE
	mix deps.get

test: FORCE
	mix test
	make test-distributed

test-distributed: FORCE
	epmd -daemon
	mix test --only distributed
	make kill-all-epmd

build-cli:
	mix escript.build

test-cli:
	make build-cli
	./cingi --file test/mission_plans/outposts/setup.yaml

test-multi-cli:
	make test-hq-cli &
	make test-branch-cli
	make kill-all-epmd

test-hq-cli:
	epmd -daemon
	make build-cli
	./cingi --file test/mission_plans/outposts/multinode.yaml --minbranches 2 --name one@localhost --cookie test

test-branch-cli:
	epmd -daemon
	make build-cli
	./cingi --file test/mission_plans/outposts/multinode.yaml --connectto one@localhost --name two@localhost --cookie test

kill-all-epmd: FORCE
	for pid in $$(ps -ef | grep -v "grep" | grep "epmd -daemon" | awk '{print $$2}'); do kill -9 $$pid; done

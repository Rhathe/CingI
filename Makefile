MIN_BRANCHES = 2
BRANCH_NAME = two
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
	./cingi --file test/mission_plans/outposts/multinode.yaml; echo "exited with $$?"

test-two-cli:
	make test-hq-cli &
	make test-branch-cli
	make kill-all-epmd

test-three-cli:
	make test-hq-cli MIN_BRANCHES=3 &
	make test-branch-cli &
	make test-branch-cli BRANCH_NAME=three
	make kill-all-epmd

test-hq-cli:
	epmd -daemon
	make build-cli
	./cingi --file test/mission_plans/outposts/multinode.yaml --minbranches $(MIN_BRANCHES) --name one@localhost --cookie test

test-branch-cli:
	epmd -daemon
	make build-cli
	./cingi --file test/mission_plans/outposts/multinode.yaml --connectto one@localhost --name $(BRANCH_NAME)@localhost --cookie test

kill-all-epmd: FORCE
	for pid in $$(ps -ef | grep -v "grep" | grep "epmd -daemon" | awk '{print $$2}'); do kill -9 $$pid; done

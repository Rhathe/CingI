MIN_BRANCHES = 2
BRANCH_NAME = two
FILE = --file test/mission_plans/outposts/multinode.yaml
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

build-cli: FORCE
	mix escript.build

epmd-daemon: FORCE
	epmd -daemon

test-cli: build-cli
	./cingi $(FILE); echo "exited with $$?"

test-two-cli:
	make test-branch-cli &
	make test-hq-cli
	make kill-all-epmd

test-three-cli:
	make test-branch-cli &
	make test-branch-cli BRANCH_NAME=three &
	make test-hq-cli MIN_BRANCHES=3
	make kill-all-epmd

test-hq-cli: build-cli epmd-daemon
	./cingi $(FILE) --minbranches $(MIN_BRANCHES) --name one@localhost --cookie test

test-branch-cli: build-cli epmd-daemon
	./cingi --connectto one@localhost --name $(BRANCH_NAME)@localhost --cookie test

test-submit-file: build-cli epmd-daemon
	./cingi $(FILE) --connectto one@localhost --name file@localhost --cookie test

test-close: build-cli epmd-daemon
	./cingi --closehq --connectto one@localhost --name close@localhost --cookie test

kill-all-epmd: FORCE
	for pid in $$(ps -ef | grep -v "grep" | grep "epmd -daemon" | awk '{print $$2}'); do kill -9 $$pid; done

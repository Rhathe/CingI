MIN_BRANCHES = 2
BRANCH_NAME = two
PRINT_BRANCH_OUTPUT =
FILE = --file test/gitclone_cingi.yaml
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

test-two-cli: build-cli epmd-daemon
	make two-cli
	make kill-all-epmd

test-three-cli: build-cli epmd-daemon
	make three-cli
	make kill-all-epmd

test-hq-cli: build-cli epmd-daemon
	make hq-cli

test-branch-cli: build-cli epmd-daemon
	make branch-cli

test-submit-file: build-cli epmd-daemon
	./cingi $(FILE) --connectto one@localhost --sname file@localhost --cookie test

test-close: build-cli epmd-daemon
	./cingi --closehq --connectto one@localhost --sname close@localhost --cookie test

hq-cli:
	./cingi $(FILE) --minbranches $(MIN_BRANCHES) --sname one@localhost --cookie test $(if $(PRINT_BRANCH_OUTPUT), "--printbranchoutput")

branch-cli:
	./cingi --connectto one@localhost --sname $(BRANCH_NAME)@localhost --cookie test $(if $(PRINT_BRANCH_OUTPUT), "--printbranchoutput")

two-cli:
	make branch-cli &
	make hq-cli

three-cli:
	make branch-cli &
	make branch-cli BRANCH_NAME=three &
	make hq-cli MIN_BRANCHES=3

kill-all-epmd: FORCE
	for pid in $$(ps -ef | grep -v "grep" | grep "epmd -daemon" | awk '{print $$2}'); do kill -9 $$pid; done

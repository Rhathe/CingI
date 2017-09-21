# CingI [![Build Status](https://travis-ci.org/Rhathe/CingI.svg)](https://travis-ci.org/Rhathe/CingI)

![logo](https://rawgit.com/Rhathe/C-ING-I/master/c-ing-i-logo.svg)


Continuous-ing Integration

CingI is currently a distributed task ("mission") runner.
It introduces the concepts of "Missions", which can be considered both pipelines and tasks.
They either run "Submissions" or a basic bash command. Missions with submissions pipe the output
of one submission to another if run sequentially, but submissions can also be run in parallel.

It can be used as a simple command line task runner locally or set up to
run missions spread out among different machines (A main "Headquarters" and several "Branch" nodes).
CingI uses yaml files ("Mission Plans") to define and execute missions.

Future work is to build a CI server on top of its core to put the
"Continuous Integration" in "Continuous-ing Integration"... or CingI.


## Installation

CingI is used via the command line. The easiest way to install is through mix.


```bash
$ mix escript.install hex cingi
```

Or you can build from source


```bash
$ mix deps.get
$ mix escript.build
```

## Command Line Examples

### Local Task Running

You can run CingI as a local task runner by just passing a valid yaml file.

```bash
$ cingi --file example.yaml
```

### Distributed Task Running

You can also run it as a distributed task runner for a valid yaml file, stopping when the given file is finished.
(NOTE: You may need to start the epmd daemon on each machine so they can connect by running epmd -daemon)

1. Start the Headquarters Branch node, waiting for 2 other branches to connect

	```bash
	$ cingi --file example.yaml --minbranches 3 --name one@FIRST_IP --cookie test
	```

2. Start the second branch node in a different machine and connect to the first node, having a different name but the same cookie

	```bash
	$ cingi --connectto one@FIRST_IP --name two@SECOND_IP --cookie test
	```

3. Start the third branch node in a third machine

	```bash
	$ cingi --connectto one@FIRST_IP --name three@THIRD_IP --cookie test
	```

If you want to leave them constantly running instead:

1. Don't pass a file to the Headquarters node.

	```bash
	$ cingi --minbranches 3 --name one@FIRST_IP --cookie test
	```

2. Submit files to the Headquarters node.

	```bash
	$ cingi --file example.yaml --connectto one@FIRST_IP --name file@ANY_IP --cookie test
	```

3. You can stop the task runner by submitting a stop command.

	```bash
	$ cingi --closehq --connectto one@FIRST_IP --name close@ANY_IP --cookie test
	```


## Mission Plans

A mission plan is a yaml file that defines a single mission.

A mission can be a bash command:

```yaml
echo "This line is a valid mission plan"
```

Or a map to configure the mission:

```yaml
name: Some mission
missions: echo "This map is a valid mission plan"
```


### Sequential/Parallel Missions

Although a mission plan is a single mission, all missions either run
a single bash command, or are composed of other smaller missions, or submissions.

You can do a sequential list of submissions, run one after the other, with one mission encompassing them all:

```yaml
- echo "This list"
- echo "is a valid"
- echo "mission plan"
```

```yaml
missions:
  - echo "This list"
  - echo "is also a valid"
  - echo "mission plan"
```

Or a parallel map of submissions, which are all run at the same time
(NOTE: parallel missions can only be defined under the missions key):

```yaml
missions:
  one: echo "This map"
  two: echo "is also a valid"
  three: echo "mission plan"
```

Submissions are just missions, so they too can have submissions of their own:

```yaml
name: Top Missions
missions:
  one: echo "Missions can just a bash command"
  two:
    - echo "Missions"
    - - echo "can be"
      - echo "a list"
    - name: Inside List
      missions: echo "of bash commands"
  three:
    name: Sub Parallel Group
    missions:
      threeone: echo "Or another map of bash commands"
      threetwo: echo "These are in parallel, so they may be executed out of order"
```


#### Failing Fast

When a submission fails in a sequential list of submissions,
no further submissions of the mission will run
and the exit code will propagate up to the supermission.

```yaml
- echo "will run"
- exit 5
- echo "won't run"
```

However, setting `fail_fast: false` will keep running submissions,
and the exit code of the mission will be the last submissions exit code.

```yaml
fail_fast: false
missions:
  - echo "will run"
  - exit 5
  - echo "will still run"
```

On the other hand, by default, a mission will wait for all parallel submissions
to finish, and will use the largest exit code of from its submissions.

```yaml
missions:
  one: sleep 2; echo "will run"
  two: sleep 1; exit 5
  three: sleep 2; echo "will also run"
```

However, setting `fail_fast: true` will kill all parallel submissions when one fails,
and the exit code of the mission will still be the largest submissions exit code.

```yaml
fail_fast: true
missions:
  one: echo "will run"
  two: sleep 1; exit 5
  three: sleep 2; echo "will not run"
```


## License

CingI is licensed under the [MIT license](LICENSE).

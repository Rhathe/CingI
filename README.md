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


#### Inputs and Outputs

A list of sequential submissions, by default, will pipe their output to the next submission.

```yaml
- echo "mission input"
- read INPUT; echo "input is ($INPUT)" # will print "input is (mission input)"
```

If a mission is composed of sequential submissions, the first submission will use its supermission's input as its own input.

```yaml
- echo "mission input"
- missions:
  - read INPUT; echo "first input is ($INPUT)" # will print "first input is (mission input)"
  - read INPUT; echo "second input is [$INPUT]" # will print "second input is [first input is (mission input)]"
```

If a mission is composed of parallel submissions, all submissions will use its supermission's input as its own input.

```yaml
- echo "mission input"
- missions:
    one: read INPUT; echo "first input is ($INPUT)" # will print "first input is (mission input)"
    two: read INPUT; echo "second input is [$INPUT]" # will print "second input is [mission input]"
```

A mission's output will be output of its submissions
(in order if sequential submissions,
interleaved depending on execution time if parallel submissions).

```yaml
- - echo one
  - echo two
  - echo three

# will print:
#  input: one
#  input: two
#  input: three
- "while read line; do echo \"input: $line\"; done"
```

```yaml
- missions:
    one: echo one
    two: echo two

# will print:
#  input: one
#  input: two
# or print:
#  input: two
#  input: one
- "while read line; do echo \"input: $line\"; done"
```

You can filter the output based on index if sequential submissions or key if parallel submissions
with a special "$OUT" string or list of "$OUT" strings in the `output` field.
(NOTE: filter order doesn't matter in the list)

```yaml
# output will be "two"
- output: $OUT[2]
  missions:
    - echo one
    - echo two
    - echo three

# output will be "one\nthree"
- output:
    - $OUT[$LAST]
    - $OUT[0]
  missions:
    - echo one
    - echo two
    - echo three

# output will be "one\ntwo" or "two\none"
- output:
    - $OUT['one']
    - $OUT["two"]
  missions:
    one: echo one
    two: echo two
    three: echo three
```

A submission can select its input by index or key if the previous mission is composed of submissions
with a special "$IN" string or list of "$IN" strings in the `input` field.
(NOTE: Unlike the `output` field, input order DOES matter)

```yaml
- - echo one
  - echo two
  - echo three
- missions:

    # will print "a: one"
    a:
      input: $IN[0]
      missions: "while read line; do echo \"a: $line\"; done"

    # will print "b: three\nb: two"
    b:
      input:
        - $IN[$LAST]
        - $IN[1]
      missions: "while read line; do echo \"b: $line\"; done"
```

```yaml
- missions:
    one: echo one
    two: echo two
    three: echo three
- missions:

    # will print "a: one"
    a:
      input: $IN['one']
      missions: "while read line; do echo \"a: $line\"; done"

    # will print "b: three\nb: two"
    b:
      input:
        - $IN["three"]
        - $IN['two']
      missions: "while read line; do echo \"b: $line\"; done"
```

### Outposts

Since CingI can be run in a distributed manner, each Branch could have been run in different
directories with different environment variables. It may be necessary to set up the environment
to run the missions in.

"Outposts" serve as a way to setup the environment in a branch before running a mission.
They are defined in the `outpost` field, with further configuration using the
`dir`, `env`, and `setup` fields. Outpost directories and environment variables are
carried through all submissions of the mission where it's defined in,
unless overriden by a submission's own outpost.

```yaml
outpost:
  dir: /tmp
  env:
    ENV_1: one
    ENV_2: two
missions:
  - pwd # Will print "/tmp"
  - outpost:
      dir: /tmp/tmp2
      env:
        ENV_2: another_two
    missions:
      - pwd # Will print "/tmp/tmp2" 
      - echo "$ENV_1, $ENV_2" # Will print "one, another_two"
  - echo "$ENV_1, $ENV_2" # Will print "one, two"
```

You can also specify a `setup`. An outpost setup is essentially a mission that's run
whenever an outpost needs to be setup for a mission. Setups and any parent setups are run only when
a submission of that particular branch is running a bash command.

```yaml
outpost:
  setup:
    - mkdir test
    - echo "{}"
missions:
  - outpost:
      setup:
        - cat "echo testecho" > test/script.sh
        - echo "{}"
    missions:
      - bash test/script.sh # Will print "testecho"
```

If you're wondering what the `echo "{}"` is for, it's because the `dir` and `env` fields
can be configured using the last line of the `setup` output if the last line
is a valid json string, and can be selected with the special "$SETUP" string.

```yaml
outpost:
  dir: $SETUP['a']
  env:
    SOME_ENV: $SETUP['b']
  setup:
    - "echo \"{\\\"a\\\": \\\"/tmp\\\", \\\"b\\\": \\\"someval\\\"}\""
missions:
  - pwd # Will print "/tmp"
  - echo "$SOME_ENV" # Will print someval
```

### When: Conditional Missions

You can have missions run conditionally if run sequentially by setting the `when` field.
You can conditionally run a missions based on `outputs`, `exit_codes`, and `success`.
(NOTE: if you want to condition based on `exit_codes` or `success`,
then make sure the supermission has `fail_fast: false`)

```yaml
fail_fast: false
missions:
  - echo test; exit 5;
  - missions:
    run1:
      when:
        - outputs: test
      missions: echo "runs with output 'test'"
    skipped1:
      when:
        - exit_codes: 4
      missions: echo "doesn't run since exit code is not 4"
    run2:
      when:
        - success: false
      missions: echo "runs with failure"
```

Then `when` field takes a list, so all the elements of the list need to pass.

```yaml
fail_fast: false
missions:
  - echo test; exit 5;
  - missions:
    runs:
      when:
        - outputs: test
        - exit_codes: 5
      missions: echo "runs with output 'test' and exit_code 5"
    skips:
      when:
        - outputs: test
        - exit_codes: 4
      missions: echo "doesn't run since exit code is still not 4"
```

However, only one condition within the element of the list needs to pass for the entire element to pass.

```yaml
fail_fast: false
missions:
  - echo test; exit 5;
  - missions:
    runs1:
      when:
        - outputs:
           - test
           - nottest
      missions: echo "runs with output 'test'"
    runs2:
      when:
        - outputs: test
          exit_codes: 4
      missions: echo "runs this time because of extra condition outputs: test"
```


## License

CingI is licensed under the [MIT license](LICENSE).

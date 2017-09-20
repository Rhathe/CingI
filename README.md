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


## Mission Plan Examples


## License

CingI is licensed under the [MIT license](LICENSE).

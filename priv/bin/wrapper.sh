#!/bin/bash

cmd=$1
pid=""
stdin_pid=""

cleanup() {
	exit_code=$?
	kill -KILL $pid > /dev/null 2>&1
	kill -KILL $stdin_pid > /dev/null 2>&1
	#echo "exiting with code $exit_code, pids $pid and $stdin_pid"
	exit $exit_code
}

trap cleanup EXIT

if [ "$#" -eq "2" ]; then
	bash -c "cat $2 | $1"&
	pid=$!
else
	bash -c "$cmd"&
	pid=$!
fi

# Needed wrapper because Erlang VM sends EOF when process dies, but
# some programs don't respect the EOF signal, so a kill is necessary
# NOTE: Don't use /bin/sh, <&0 redirection does not work
{
	while read line ; do
		if [ "$line" = "kill" ]; then
			cleanup
		fi
	done
} <&0 &
stdin_pid=$!

wait $pid > /dev/null 2>&1

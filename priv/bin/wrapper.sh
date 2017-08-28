#!/bin/bash

set -m

cmd=$1
file="$2"
del_tmp_file="$3"
PID=""
PGID=""
STDIN_PID=""

cleanup() {
	exit_code=$?

	# Indicated to be a tmp_file, delete here so that exit traps clean it up
	if [ "$del_tmp_file" = "true" ]; then
		rm "$file" > /dev/null 2>&1
	fi

	kill -KILL "$PID" > /dev/null 2>&1
	kill -KILL -"$PID" > /dev/null 2>&1
	kill -KILL -"$PGID" > /dev/null 2>&1
	kill -KILL $STDIN_PID > /dev/null 2>&1
	exit $exit_code
}

trap cleanup EXIT

if [ "$#" -eq "1" ]; then
	bash -c "$cmd"&
	PID=$!
else
	# Pipe input file to cmd with cat, suppress stderr since
	# pipe can be broken but we don't care
	(cat "$file" 2> /dev/null) | (bash -c "$cmd") &
	PID=$!
fi

# Get PGID to kill all child processes
# https://stackoverflow.com/questions/392022/best-way-to-kill-all-child-processes
PGID=$(ps opgid= "$PID")

# Needed wrapper because Erlang VM sends EOF when process dies, but
# some programs don't respect the EOF signal, so a kill is necessary
# NOTE: Don't use /bin/sh, <&0 redirection does not work
{
	while read line ; do
		if [ "$line" = "kill" ]; then
			cleanup
		fi
	done
	cleanup
} <&0 &
STDIN_PID=$!

wait $PID > /dev/null 2>&1

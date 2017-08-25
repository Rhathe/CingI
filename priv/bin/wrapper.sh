#!/bin/bash

cmd=$1
file="$2"
del_tmp_file="$3"
pid=""
stdin_pid=""

cleanup() {
	exit_code=$?

	# Indicated to be a tmp_file, delete here so that exit traps clean it up
	if [ "$del_tmp_file" = "true" ]; then
		rm "$file" > /dev/null 2>&1
	fi
	kill -KILL $pid > /dev/null 2>&1
	kill -KILL $stdin_pid > /dev/null 2>&1
	exit $exit_code
}

trap cleanup EXIT

if [ "$#" -eq "1" ]; then
	bash -c "$cmd"&
	pid=$!
else
	# Pipe input file to cmd with cat, suppress stderr since
	# pipe can be broken but we don't care
	(cat "$file" 2> /dev/null) | (bash -c "$cmd") &
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

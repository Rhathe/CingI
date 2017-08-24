#!/bin/sh

if [ "$#" -eq "2" ]; then
	bash -c "cat $2 | $1"&
	pid=$!
else
	bash -c "$1"&
	pid=$!
fi

cleanup() {
	exit_code=$1
	kill -KILL $pid > /dev/null 2>&1
	exit $exit_code
}

trap "cleanup $?" CHLD

while read line ; do
	if [ "$line" = "kill" ]; then
		break
	fi
done

cleanup 1

#!/bin/sh

bash -c "cat $1 | $2"&
pid=$!

cleanup() {
	exit_code=$1
	kill -KILL $pid > /dev/null 2>&1
	exit $exit_code
}

trap "cleanup $?" CHLD

while read line ; do
	:
done

cleanup

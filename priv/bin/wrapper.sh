#!/bin/sh

bash -c "$@"&
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

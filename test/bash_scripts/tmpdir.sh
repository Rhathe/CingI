#!/bin/bash

if [ -z "$1" ]; then
	WORK_DIR=`mktemp -d`
else
	WORK_DIR=`mktemp -d -p $1`
fi

cp $0 $WORK_DIR

echo "{\"dir\": \"$WORK_DIR\"}"

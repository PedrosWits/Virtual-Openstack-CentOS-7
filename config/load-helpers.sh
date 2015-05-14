#!/bin/bash

yell() { echo "$0: $*" >&2; }
die() { yell "$*"; exit 111; }
try() { "$@" || die "cannot $*"; }

# Requires log function to be loaded-defined first (load-log.sh)
runCommand() {	
	if ! eval "$1"
	  then STATUS="$SFAILED"; result=1
	  else STATUS="$SOK"; result=0
	fi
	log "$2: $STATUS"
}

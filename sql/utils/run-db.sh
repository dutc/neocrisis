#!/bin/bash

curdir="$(dirname "$(readlink -f "$(which $0)")")"
basedir="${1:-$curdir}"

shutdown() {
	pg_ctl -D "$basedir/db" stop
}

trap "trap - SIGTERM && shutdown && exit 1 && kill -- -$$" SIGINT SIGTERM exit

pg_ctl -D "$basedir/db" -l "$basedir/db-logs/$(date).log" start

while true; do
    echo "postgresql running with PID $$"
    sleep 60
done

#!/bin/zsh

curdir="$(dirname "$(readlink -f "$(which $0)")")"

export PYTHONIOENCODING='utf-8'

jinja2 --format=yaml "$curdir/model.jinja.sql" <(
    echo 'materialized: False'
)

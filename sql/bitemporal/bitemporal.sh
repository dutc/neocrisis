#!/bin/zsh

curdir="$(dirname "$(readlink -f "$(which $0)")")"

export PYTHONIOENCODING='utf-8'

jinja2 --format=yaml "$curdir/bitemporal.sql.template" <(
echo 'tables:'
(psql -q -d nc -t -A -F'.' <<EOF
    select table_schema, table_name
    from information_schema.tables
    where table_schema not in ('information_schema', 'pg_catalog')
    and table_schema not in ('history')
    and table_type <> 'VIEW'
EOF
) | sed -r 's/^/ - /'
)

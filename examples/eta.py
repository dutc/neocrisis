#!/usr/bin/env python3
import os
import time

import psycopg2
from psycopg2.extras import NamedTupleCursor


DBNAME = os.environ.get('DBNAME', 'nc')
DBHOST = os.environ.get('DBHOST', None)
DBUSER = os.environ.get('DBUSER', 'postgres')

DBPARAMS = {'dbname': DBNAME, 'user': DBUSER}
if DBHOST is not None:
    DBPARAMS['host'] = DBHOST


QUERY = r"""
select
    n.name
    , coalesce(n.target, 'unknown') as target
    , n.regclass
    , case
    when (n.rock_params).v = 0 then 'Infinity'::double precision
    else (n.pos).r / (n.rock_params).v
    end as eta
from api.neos as n
where n.regclass = 'api.rocks'::regclass
"""

if __name__ == '__main__':
    with psycopg2.connect(**DBPARAMS, cursor_factory=NamedTupleCursor) as db:
        with db.cursor() as cur:
            while True:
                os.system('clear')
                # cur.execute('select name from api.neos')
                # for row in cur:
                #     print(row)
                print(f'{"name".center(32,"-")}{"target".center(32,"-")}{"eta".center(16,"-")}')
                cur.execute(QUERY)
                for row in cur:
                    print(f'{row.name:^32}{row.target:^32}{row.eta:>8.0f}s')
                time.sleep(.1)

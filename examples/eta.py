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


ETA_QUERY = r"""
set search_path = game, public;

select
    name
    , regclass
    , (pos).r as eta / (rock_params).v as eta
from api.neos
where neos.regclass = 'rocks'::regclass -- and (rock_params).v != 0;
"""


if __name__ == '__main__':
    db = psycopg2.connect(**DBPARAMS, cursor_factory=NamedTupleCursor)
    with db.cursor() as cursor:
        while True:
            import pdb
            pdb.set_trace()
            cursor.execute(ETA_QUERY)
            for asteroid in cursor:
                name, eta = asteroid.name, asteroid.eta
                print(f'ASTEROID "{name}" IS {eta} SECONDS FROM IMPACT')
            time.sleep(1)
            os.system('clear')
    db.close()

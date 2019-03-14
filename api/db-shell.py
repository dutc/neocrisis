#!/usr/bin/env python

from warnings import catch_warnings, simplefilter
with catch_warnings():
    simplefilter('ignore')
    from psycopg2 import connect
    from psycopg2.extras import NamedTupleCursor
from contextlib import closing
from code import InteractiveConsole
from os import environ
from rlcompleter import readline

DBNAME = environ.get('DBNAME', 'nc')
DBHOST = environ.get('DBHOST', None)
DBUSER = environ.get('DBUSER', 'postgres')

DBPARAMS = {'dbname': DBNAME, 'user': DBUSER}
if DBHOST is not None:
    DBPARAMS['host'] = DBHOST

if __name__ == '__main__':
    with closing(connect(**DBPARAMS, cursor_factory=NamedTupleCursor)) as db:
        db.set_session(autocommit=True)
        with db.cursor() as cur:
            def q(query):
                cur.execute(query)
                return [row for row in cur]
            readline.parse_and_bind('tab:complete')
            InteractiveConsole(locals=globals()).interact('')

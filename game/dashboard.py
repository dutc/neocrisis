#!/usr/bin/env python3

from warnings import catch_warnings, simplefilter
with catch_warnings():
    simplefilter('ignore')
    from psycopg2 import connect
    from psycopg2.extras import NamedTupleCursor
from contextlib import closing
from os import environ
from subprocess import run
from time import sleep
from datetime import datetime
from itertools import islice, tee, repeat, chain, zip_longest

nwise = lambda g, n=2: zip(*(islice(g, i, None) for i, g in enumerate(tee(g, n))))
nwise_longest = lambda g, n=2, fillvalue=object(): zip_longest(*(islice(g, i, None) for i, g in enumerate(tee(g, n))), fillvalue=fillvalue)
last = lambda g, n=1, sentinel=object(): ((any(y is sentinel for y in ys), x) for x, *ys in nwise_longest(g, n+1, fillvalue=sentinel))
intercalate = lambda g, fill=repeat(None): chain.from_iterable((x,) if islast else (x, next(fill)) for islast, x in last(g))

DBNAME = environ.get('DBNAME', 'nc')
DBHOST = environ.get('DBHOST', None)
DBUSER = environ.get('DBUSER', 'postgres')

DBPARAMS = {'dbname': DBNAME, 'user': DBUSER}
if DBHOST is not None:
    DBPARAMS['host'] = DBHOST

rocks_query = '''
    select name, age, (pos).r as pos_r, (rock_params).v as params_v, coalesce(target, '?') as target
    from api.neos where regclass = 'api.rocks'::regclass
    order by age desc
    limit 5
'''
slugs_query = '''
    select name, age, (pos).r as pos_r, coalesce(target, '?') as target
    from api.neos where regclass = 'api.slugs'::regclass
    order by age asc
    limit 5
'''
misses_query = '''
    select rock, target, (collision).t as t
    from api.misses
'''

if __name__ == '__main__':
    with closing(connect(**DBPARAMS, cursor_factory=NamedTupleCursor)) as db:
        db.set_session(autocommit=True)
        with db.cursor() as cur:
            while True:
                COLUMNS = intercalate([20, 10, 20, 10, 15], repeat(1))
                WIDTH = sum(COLUMNS)

                run('clear')
                print(f' Dashboard {datetime.now():%H:%M:%S} '.center(WIDTH, '='))

                print()
                print(f'  Rocks  '.center(WIDTH, '-'))
                print(f'{"Name":<20} {"Distance":>10} {"Time To Impact (s)":>20} {"Age (s)":>10} {"Target":>15}')
                cur.execute(rocks_query)
                for rock in cur:
                    print(f'{rock.name:<20} {rock.pos_r:>10.2f} {rock.pos_r / -rock.params_v if rock.params_v < 0 else float("inf"):>20.2f} {rock.age.seconds:>10.0f} {rock.target[:20]:>15}')

                print()
                print(f'  Slugs  '.center(WIDTH, '-'))
                print(f'{"Name":<20} {"Distance":>10} {"":>20} {"Age (s)":>10} {"Target":>15}')
                cur.execute(slugs_query)
                for slug in cur:
                    print(f'{slug.name[:20]:<20} {slug.pos_r:>10.2f} {"":>20} {slug.age.seconds:>10.0f} {slug.target[:20]:>15}')

                print()
                print(f'  Status  '.center(WIDTH, '-'))
                print(f'{"Name":<20} {"Target":<15} {"Time":>8} {"Status":>15}')
                cur.execute(misses_query)
                for miss in cur:
                    print(f'{miss.rock[:20]:<20} {miss.target[:15]:<15} {miss.t:%H:%M:%S} {"vaporized":>15}!')

                sleep(.5)

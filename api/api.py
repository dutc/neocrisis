import os
from random import randint
from multiprocessing import Value
from numbers import Number

from flask import Flask, g, request, jsonify, make_response
from psycopg2 import connect
from psycopg2.extras import NamedTupleCursor


counter = Value('i', 0)

app = Flask(__name__)


def get_db():
    'opens database connection'
    if not hasattr(g, 'db'):
        g.db = connect(f'dbname={DBNAME} host={DBHOST}',
                       cursor_factory=NamedTupleCursor)
        g.db.set_session(autocommit=True)
    return g.db


@app.teardown_appcontext
def close_db(_):
    if hasattr(g, 'db'):
        g.db.close()


def fire_slug(name, theta, phi):
    query = '''
        insert into game.slugs (name, params)
        values (%(name)s, (%(theta)s, %(phi)s, c() / 10))
    '''
    params = {'name': name, 'theta': theta, 'phi': phi}
    with get_db().cursor() as cur:
        cur.execute(query, params)
    return {'slug': params}


def observation(octant):
    query = '''
        select
            regclass
            , name
            , mass
            , fired
            , (pos).r::double precision as pos_r
            , (pos).theta::double precision as pos_theta
            , (pos).phi::double precision as pos_phi
            , (cpos).x::double precision as cpos_x
            , (cpos).y::double precision as cpos_y
            , (cpos).z::double precision as cpos_z
            , t
            , octant
            , age
        from api.neos
        where octant = %(octant)s
    '''
    with get_db().cursor() as cur:
        cur.execute(query, {'octant': octant})
        objects = [
            {
                'type': {'api.rocks': 'rock', 'api.slugs': 'slug'}.get(x.regclass, 'unknown'),
                'name': x.name,
                'mass': x.mass,
                'fired': x.fired,
                'pos': {'r': x.pos_r, 'theta': x.pos_theta, 'phi': x.pos_phi},
                'cpos': {'x': x.cpos_x, 'y': x.cpos_y, 'z': x.cpos_z},
                'obs_time': x.t,
                'octant': x.octant,
                'age': x.age.seconds,
            }
            for x in cur
        ]
    return {'objects': objects}


@app.route('/telescope/<int:octant>', methods=['GET'])
def telescope(octant):
    if not 1 <= octant <= 8:
        msg = {'error': f'invalid octant {octant} must be [1, 8]'}
        return make_response(jsonify(msg), 400)
    return jsonify(observation(octant))


@app.route('/railgun', methods=['POST'])
def laser():
    data = request.json

    with counter.get_lock():
        counter.value += 1
        name = data.get('name', f'{counter.value * 10}')

    try:
        theta = float(data.get('theta'))
        phi = float(data.get('phi'))
    except ValueError:
        msg = {'error': f'bad theta/phi params'}
        return make_response(jsonify(msg), 400)

    slug = fire_slug(name, theta, phi)
    if slug is None:
        msg = {'error': f'firing failed'}
        return make_response(jsonify(msg), 400)
    return jsonify(slug)


if __name__ == '__main__':
    DBNAME = os.environ.get('DBNAME', 'nc')
    DBHOST = os.environ.get('HOST', '/tmp/')

    port = os.environ.get('JSON_API_PORT', 5000)
    debug = os.environ.get('DEBUG', False)
    app.run(host='localhost', port=port, debug=debug)

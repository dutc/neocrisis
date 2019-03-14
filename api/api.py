from os import environ
from random import randint
from multiprocessing import Value
from numbers import Number

from flask import Flask, g, request, jsonify, make_response, redirect
from flask.json import JSONEncoder
from warnings import catch_warnings, simplefilter
with catch_warnings():
    simplefilter('ignore')
    from psycopg2 import connect
    from psycopg2.extras import NamedTupleCursor
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from dateutil.parser import parse
from datetime import datetime, timedelta
from tzlocal import get_localzone
from pytz import timezone

TIMEZONE = get_localzone()
if 'TIMEZONE' in environ:
    TIMEZONE = timezone(environ['TIMEZONE'])

DBNAME = environ.get('DBNAME', 'nc')
DBHOST = environ.get('DBHOST',  None)
DBUSER = environ.get('DBUSER', 'postgres')
DBPARAMS = {'dbname': DBNAME, 'user': DBUSER}
if DBHOST is not None:
    DBPARAMS['host'] = DBHOST

SATELLITE_NAME = environ.get('SATELLITE_NAME', None)

SLUG_VELOCITY = 1

class CustomEncoder(JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)

app = Flask(__name__)
app.json_encoder = CustomEncoder
limiter = Limiter(
    app,
    key_func = get_remote_address,
    default_limits = ['20 per second'],
)

counter = Value('i', 0)

def get_db():
    'opens database connection'
    if not hasattr(g, 'db'):
        g.db = connect(**DBPARAMS, cursor_factory=NamedTupleCursor)
        g.db.set_session(autocommit=True)
    return g.db


@app.teardown_appcontext
def close_db(_):
    if hasattr(g, 'db'):
        g.db.close()


@app.route('/', methods=['GET'])
@app.route('/docs', methods=['GET'])
def docs():
    return redirect('https://github.com/dutc/neocrisis.git')


@app.route('/help/', methods=['GET'])
def help():
    return jsonify({
        'message': 'check out /telescope/help/ and /railgun/help/',
    })


@app.route('/telescope/help/', methods=['GET'])
def telescope_help():
    return jsonify({
        'endpoints': {
            '/telescope/help/':        'describes the /telescope/<int:octant> endpoint',
            '/telescope/<int:octant>': 'makes an observation in the specified octant',
        },
        'methods': {
            '/telescope/help/':        ['GET'],
            '/telescope/<int:octant>': ['GET'],
        },
        'inputs': {
            '/telescope/help/': {},
            '/telescope/<int:octant>': {
                'octant': 'the octant in which to make the observation (integer, [1, 8])'
            },
        },
        'outputs': {
            '/telescope/help/': {
                'endpoints': 'the relevant endpoints',
                'methods':   'the HTTP verbs (GET, POST, PUT, DELETE, etc.) that the endpoints support',
                'inputs':    'the inputs the endpoints take',
                'outputs':   'the outputs the endpoints return',
            },
            '/telescope/<int:octant>': {
                'objects': [
                    'the objects (rocks and slugs) seen in that octant',
                    {
                        'id':         "the object's unique identifier",
                        'type':       "the type of object (either 'rock' or 'slug')",
                        'name':       'the human readable name of the object',
                        'target':     "the human readable name of the object's desired target",
                        'mass':       "the mass (in kg) of the object",
                        'fired':      'the time when the object was first launched',
                        'pos':        ['the position of the object in polar coördinates', {
                                       'r':     'radius (distance from earth) (in AU)',
                                       'theta': '(also: θ or azimuth) the angle measured east-to-west (longitudinally) from the 0° Prime Meridian (Greenwich, UK) toward the 90° meridian (Memphis, TN) (in radians, [0, 2π])',
                                       'phi':   '(also: φ or inclination) the angle measured north-to-south (latitudinally) from the North Pole to the South Pole (in radians, [0, π]])',
                                       }],
                        'cpos':        ['the position of the object in Cartesian coördinates', {
                                        'x': "the distance from the earth's core toward the 0° Prime Meridian (Greenwich, UK) (in AU, [0, ∞))",
                                        'y': "the distance from the earth's core toward the 90° meridian (Memphis, TN) (in AU, [0, ∞))",
                                        'z': "the distance from the earth's core toward 0° latitutde (North Pole) (in AU, [0, ∞))",
                                       }],
                        'obs_time':    'the time of this observation (i.e., the time when the object was at the above coördinates)',
                        'octant':      'the octant the object was spotted in',
                        'age':         'the amount of time since the object was launched (in secs)',
                    }
                ]
            },
        },
    })

@app.route('/telescope/<int:octant>', methods=['GET'])
def telescope(octant):
    if not 1 <= octant <= 8:
        msg = {'error': f'invalid octant {octant} must be [1, 8]'}
        return make_response(jsonify(msg), 400)
    query = '''
        select
            id
            , regclass
            , name
            , mass
            , target
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
                'help': 'GET /telescope/help/ for more information',
                'id': x.id,
                'type': {'api.rocks': 'rock', 'api.slugs': 'slug'}.get(x.regclass, 'unknown'),
                'name': x.name,
                'target': x.target,
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
    return jsonify({'objects': objects})


@app.route('/railgun/help/', methods=['GET'])
def railgun_help():
    return jsonify({
        'endpoints': {
            '/railgun/help/': 'describes the /railgun/<int:octant> endpoint',
            '/railgun':       'fires a slug',
        },
        'methods': {
            '/railgun/help/': ['GET'],
            '/railgun':       ['POST'],
        },
        'inputs': {
            '/railgun/help/': {},
            '/railgun': ['the following are all passed as JSON POST data', {
                'name':   '(OPTIONAL) the name of the slug (so you can identify it easily later) (string)',
                'theta':  '(also: θ or azimuth) the angle at which to fire, measured east-to-west (longitudinally) from the 0° Prime Meridian (Greenwich, UK) toward the 90° meridian (Memphis, TN) (number, in radians, [0, 2π])',
                'phi':    '(also: φ or inclination) the angle at which to fore, measured north-to-south (latitudinally) from the North Pole to the South Pole (number, in radians, [0, π]])',
                'target': "the name of the rock you're trying to hit (for display purposes only) (string)",
                'fired':  '(OPTIONAL) the time when you want to fire; must be in the future, must be within 5 minutes of the current time; if not specified, assume immediate firing (string, as HH:MM:SS in local time zone)',
            }],
        },
        'outputs': {
            '/railgun/help/': {
                'endpoints': 'the relevant endpoints',
                'methods':   'the HTTP verbs (GET, POST, PUT, DELETE, etc.) that the endpoints support',
                'inputs':    'the inputs the endpoints take',
                'outputs':   'the outputs the endpoints return',
            },
            '/railgun': {
                'object': [
                    'the details of the slug you just fired',
                    {
                        'id':         "the slug's unique identifier",
                        'type':       "the type of object (always 'slug')",
                        'name':       'the human readable name of the slug',
                        'target':     "the human readable name of the slug's desired target",
                        'fired':      'the time when the slug was fired',
                        'pos':        ['the position of the slug in polar coördinates', {
                                       'r':     'radius (distance from earth) (in AU)',
                                       'theta': '(also: θ or azimuth) the angle measured east-to-west (longitudinally) from the 0° Prime Meridian (Greenwich, UK) toward the 90° meridian (Memphis, TN) (in radians, [0, 2π])',
                                       'phi':   '(also: φ or inclination) the angle measured north-to-south (latitudinally) from the North Pole to the South Pole (in radians, [0, π]])',
                                       }],
                        'cpos':        ['the position of the slug in Cartesian coördinates', {
                                        'x': "the distance from the earth's core toward the 0° Prime Meridian (Greenwich, UK) (in AU, [0, ∞))",
                                        'y': "the distance from the earth's core toward the 90° meridian (Memphis, TN) (in AU, [0, ∞))",
                                        'z': "the distance from the earth's core toward 0° latitutde (North Pole) (in AU, [0, ∞))",
                                       }],
                        'obs_time':    'the time of this observation (i.e., the time when the slug was at the above coördinates)',
                        'octant':      'the octant the slug was spotted in',
                        'age':         'the amount of time since the slug was launched (in secs)',
                    }
                ]
            },
        },
    })


@app.route('/railgun', methods=['POST'])
@limiter.limit('5 per 1 seconds')
def railgun():
    data = request.json
    if data is None:
        msg = {'error': 'malformed request'}
        return make_response(jsonify(msg), 400)

    if 'name' in data:
        name = data['name']
    else:
        with counter.get_lock():
            counter.value += 1
            name = data.get('name', f'shot #{counter.value * 10}')

    try:
        theta = float(data.get('theta'))
        phi = float(data.get('phi'))
        target = data.get('target')
    except Exception as e:
        msg = {'error': f'bad theta/phi params', 'msg': repr(e)}
        return make_response(jsonify(msg), 400)

    now = datetime.now(TIMEZONE)
    if 'fired' not in data:
        fired = None
    else:
        try:
            fired = TIMEZONE.localize(parse(data['fired'], ignoretz=True))
            if fired < now:
                msg = {'error': f"firing time before current time", 'now': now, 'fired': fired}
                return make_response(jsonify(msg), 400)
            if (fired - now).total_seconds() > (60 * 5):
                msg = {'error': f"firing time too far into future; must be within 5 minutes of current time", 'now': now, 'fired': fired}
                return make_response(jsonify(msg), 400)
        except Exception as e:
            msg = {'error': f'bad firing time', 'msg': repr(e)}
            return make_response(jsonify(msg), 400)

    params = {'name': name, 'theta': theta, 'phi': phi, 'target': target}
    if fired is None:
        insert_query = f'''
            insert into game.slugs (name, params)
            values (%(name)s, (%(theta)s, %(phi)s, {SLUG_VELOCITY}))
            returning id
        '''
    else:
        insert_query = f'''
            insert into game.slugs (name, params, fired)
            values (%(name)s, (%(theta)s, %(phi)s, {SLUG_VELOCITY}), %(fired)s)
            returning id
        '''
        params['fired'] = fired
    select_query = '''
        select
            id
            , name
            , target
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
        where regclass = 'api.slugs'::regclass and id = %(slug_id)s
    '''
    with get_db().cursor() as cur:
        cur.execute(insert_query, params)
        slug_id, = cur.fetchone()
        cur.execute(select_query, {'slug_id': slug_id})
        x = cur.fetchone()
        obj = {} if x is None else {
            'help': 'GET /railgun/help/ for more information',
            'id': x.id,
            'type': 'slug',
            'name': x.name,
            'target': x.target,
            'fired_time': x.fired,
            'pos': {'r': x.pos_r, 'theta': x.pos_theta, 'phi': x.pos_phi},
            'cpos': {'x': x.cpos_x, 'y': x.cpos_y, 'z': x.cpos_z},
            'obs_time': x.t,
            'octant': x.octant,
            'age': x.age.seconds,
        }
    return jsonify({'object': obj})


@app.route('/info', methods=['GET'])
@limiter.limit('10 per 1 second')
def info():
    info = {
        'name': SATELLITE_NAME,
        'railgun': {
            'online': True,
        },
        'telescope': {
            'online': True,
        },
    }
    return jsonify(info)


if __name__ == '__main__':
    host = environ.get('HOST', 'localhost')
    port = environ.get('PORT', 5000)
    debug = environ.get('DEBUG', False)
    app.run(host=host, port=port, debug=debug)

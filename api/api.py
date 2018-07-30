import os
from random import randint

from flask import Flask


OK = 'ok'
OUT_OF_AMMO = 'out of ammo'


app = Flask(__name__)


def check_ammo():
    lucky = randint(1, 10) % 2 == 0
    return lucky


def shoot_laser(name, theta, phi):
    success = check_ammo()
    if lucky:
        return OK
    return OUT_OF_AMMO


def observation(field, theta, phi):
    objects = [
        {}
    ]
    return dict(objects=objects)


@app.route('/telescope', methods=['GET'])
def telescope():
    field = request.args.get('field')
    theta = request.args.get('theta')
    phi = request.args.get('phi')
    return jsonify(observation(field, theta, phi))


@app.route('/laser', methods=['POST'])
def laser():
    request_data = request.json
    name = request_data.get('name', 'Missile')
    theta = request_data.get('theta')
    phi = request_data.get('phi')
    return shoot_laser(name, theta, phi)


if __name__ == '__main__':
    port = os.environ.get('JSON_API_PORT', 5000)
    debug = os.environ.get('DEBUG', False)
    app.run(host='localhost', port=port, debug=debug)

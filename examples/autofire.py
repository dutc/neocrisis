#!/usr/bin/env python3
from time import sleep
from requests import get, post
from logging import getLogger, basicConfig, CRITICAL, INFO, DEBUG
from argparse import ArgumentParser
from collections import defaultdict, deque
from dateutil.tz import tzlocal
from dateutil.parser import parse as dateutil_parse
from math import isclose
from datetime import datetime, timedelta
from sys import exit

C = 299792458.0 # m / s
V_SLUG = C / 10

logger = getLogger(__name__)

parser = ArgumentParser()
parser.add_argument('-v', '--verbose', action='count')
parser.add_argument('host', nargs='?', default='localhost')
parser.add_argument('port', nargs='?', default=5000, type=int)

if __name__ == '__main__':
    args = parser.parse_args()
    level = {0: CRITICAL, 1: INFO, 2: DEBUG}.get(args.verbose, CRITICAL)
    basicConfig(level=level)

    railgun_url = f'http://{args.host}:{args.port}/railgun'
    base_telescope_url = f'http://{args.host}:{args.port}/telescope/{{octant}}'
    telescope_urls = {
        base_telescope_url.format(octant=octant)
        for octant in range(1, 9)
    }

    objects = defaultdict(lambda: deque(maxlen=2))
    while True:
        all_clear = True

        for url in telescope_urls:
            resp = get(url)
            logger.info('GET %s -> %s', url, resp.status_code)
            if resp.ok:
                for obj in resp.json()['objects']:
                    if obj['type'] != 'rock':
                        continue
                    name, fired = obj['name'], obj['fired']
                    t, pos = obj['obs_time'], obj['pos']
                    objects[name, fired].append((t, pos))

                    all_clear = False

        if all_clear:
            print('All clear!')
            # exit()

        for (name, fired), pos in objects.items():
            if len(pos) == 2:
                logger.info('Computing solution for %s', name)
                (t0, pos0), (t1, pos1) = pos[0], pos[1]
                r0, theta0, phi0 = pos0['r'], pos0['theta'], pos0['phi']
                r1, theta1, phi1 = pos1['r'], pos1['theta'], pos1['phi']

                pos.clear()

                fired = dateutil_parse(fired)
                t0 = (dateutil_parse(t0) - fired).total_seconds()
                t1 = (dateutil_parse(t1) - fired).total_seconds()

                # given:
                #   r0 = v * t0 + r_orig
                #   r1 = v * t1 + r_orig

                # ∴ v = (r0 - r1) / (t0 - t1)
                # ∴ r_orig = r0 - v * t0
                #          = r1 - v * t1

                v = (r0 - r1) / (t0 - t1)
                r_orig = r0 - v * t0
                if not isclose(r_orig, r1 - v * t1):
                    raise ArithmeticError('bad computation')
                logger.info('Determined (for %s): v = %.2f, r_orig = %.2f',
                            name, v, r_orig)

                # given:
                #   theta0 = m_theta * t0 + b_theta
                #   theta1 = m_theta * t1 + b_theta

                # ∴ m_theta = (theta0 - theta1) / (t0 - t1)
                #   b_theta = theta0 - m_theta * t0
                #   b_theta = theta1 - m_theta * t1

                m_theta = (theta0 - theta1) / (t0 - t1)
                b_theta = theta0 - m_theta * t0
                if not isclose(b_theta, theta1 - m_theta * t1):
                    raise ArithmeticError('bad computation')
                logger.info('Determined (for %s): m_theta = %.2f, b_theta = %.2f',
                            name, m_theta, b_theta)

                # (same for m_phi, b_phi)

                m_phi = (phi0 - phi1) / (t0 - t1)
                b_phi = phi0 - m_phi * t0
                if not isclose(b_phi, phi1 - m_phi * t1):
                    raise ArithmeticError('bad computation')
                logger.info('Determined (for %s): m_phi = %.2f, b_phi = %.2f',
                            name, m_phi, b_phi)

                # assume firing in 10 seconds
                now = datetime.now(tzlocal())

                rock_fired_time = fired
                slug_fired_time = now + timedelta(seconds=5)

                # compute times as seconds
                base_time = now.replace(hour=0, minute=0, second=0, microsecond=0)
                t_rock = (rock_fired_time - base_time).total_seconds()
                t_slug = (slug_fired_time - base_time).total_seconds()

                v_rock, v_slug  = v, V_SLUG
                r0_rock, r0_slug = r0, 0

                # given:
                #   r_collide_rock = r_collide_slug
                #   r_collide_rock = v_rock * (t_collide - t_rock) + r0_rock
                #   r_collide_slug = v_slug * (t_collide - t_slug) + r0_slug

                # ∴ t_collide  = (v_rock * t_rock - r0_rock - v_slug * t_slug + r0_slug)
                #              / (v_rock - v_slug)

                t_collide  = (v_rock * t_rock - r0_rock - v_slug * t_slug + r0_slug) \
                           / (v_rock - v_slug)

                collide_time = base_time + timedelta(seconds=t_collide)
                logger.info('Determined (for %s): collide_time = %s', name, collide_time)

                r_collide = v_rock * (t_collide - t_rock) + r0_rock
                if not isclose(r_collide, v_slug * (t_collide - t_slug) + r0_slug):
                    raise ArithmeticError('bad computation')

                theta_collide = m_theta * (t_collide - t_rock) + b_theta
                phi_collide = m_phi * (t_collide - t_rock) + b_phi

                logger.info('Determined (for %s): theta = %s, phi = %s',
                            name, theta_collide, phi_collide)

                logger.info('Firing at (%s)!', name)
                data = {'name': f'@ {name}', 'theta': theta_collide, 'phi': phi_collide}

                wait = (slug_fired_time - datetime.now(tzlocal())).total_seconds()
                sleep(wait)

                post(railgun_url, json=data)
                logger.info('Fired at (%s)!!', name)

            sleep(.1)

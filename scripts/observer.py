#!/usr/bin/env python3
from time import sleep
from requests import get
from logging import getLogger, basicConfig, CRITICAL, INFO, DEBUG
from argparse import ArgumentParser
from collections import defaultdict

logger = getLogger(__name__)

parser = ArgumentParser()
parser.add_argument('-v', '--verbose', action='count')
parser.add_argument('host', nargs='?', default='localhost')
parser.add_argument('port', nargs='?', default=5000, type=int)

if __name__ == '__main__':
    args = parser.parse_args()
    level = {0: CRITICAL, 1: INFO, 2: DEBUG}.get(args.verbose, CRITICAL)
    basicConfig(level=level)

    base_url = f'http://{args.host}:{args.port}/telescope/{{octant}}'
    urls = {base_url.format(octant=octant) for octant in range(1, 9)}

    objects = defaultdict(list)
    while True:
        for url in urls:
            resp = get(url)
            logger.info('GET %s -> %s', url, resp.status_code)
            if resp.ok:
                for obj in resp.json()['objects']:
                    name, pos = obj['name'], obj['pos']
                    objects[name].append(pos)

            print(f'{"NAME".center(31, "-")}  {"POS (r, Θ, Φ)".center(31, "-")}')
            for name, pos in sorted(objects.items()):
                print(f'{name:^31}  {pos[-1]["r"]:>29.1f} r')
                print(f'{" ":>31}  {pos[-1]["theta"]:>29.1f} Θ')
                print(f'{" ":>31}  {pos[-1]["phi"]:>29.1f} Φ')

            sleep(1)

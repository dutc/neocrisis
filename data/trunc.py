#!/usr/bin/env python3
from sys import stdin
from random import choice, randrange
from string import digits

special = {
    'Fred L. Drake, Jr.':            'FL Drake2',
    'Walker Hale IV':                'W Hale4',
    'Jonas H.':                      'Jonas H',
    'Tattoo Mabonzo K.':             'tmk',
    'Sarah K.':                      'Sarah K',
    'Sunny K':                       'Sunny K',
    'Donald Wallace Rouse II':       'DW Rouse2',
    'Constantina S.':                'Constantina S',
    'Matthieu S':                    'Matthieu S',
    'Jean-Baptiste "Jiba" Lamy':     'J Lamy',
    'Bruno "Polaco" Penteado':       'P Penteado',
    'Bryce "Zooko" Wilcox-O\'Hearn': "Z Wilcox-O'Hearn",
}

if __name__ == '__main__':
    for line in stdin:
        line = line.strip()

        if line in special:
            print(special[line])
            continue

        number = "".join(choice(digits) for _ in range(randrange(2, 9)))
        *forenames, surname = line.split()
        initials = [f[0] for f in forenames if f[0].isalpha()]
        name = f'{"".join(initials)} {surname} {number}'.strip()
        print(name)

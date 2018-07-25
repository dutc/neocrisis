NEO* Crisis!
------------

\* Near-Earth Objects

theta (angle left/right)
phi (angle up/down)

GET telescope
    theta
    phi
    field (size)

{"objects": [
    {"name": "Ceres I",
     "type": "neo",
     "mass": 123,
     "distance": 123,
     "theta": ...,
     "phi": ...},
    {"name": ...,
     "type": "missile",
     "distance": ...,
     "theta": ...,
     "phi": ...,},
]}

PUT/POST orbital weapon
    name
    theta
    phi

{"status": "ok"}
{"status": "out of ammo"}

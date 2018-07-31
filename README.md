# neocrisis <i>!</i>
## a collaborative coding game from NYC Python

Teaches: automation, JSON, REST APIs, Python, `curl`, `httpie`.

<b>The earth is in danger!</b>

We've detected multiple <b>n</b>ear <b>e</b>arth <b>o</b>bjects (‘NEO’s) on a
collision course with the earth. But we're not defenseless. Surrounding the
earth we've launched multiple orbital defense platforms. It is your job to
control these platforms and defend earth.

## RULES

There are multiple objects (‘rocks’) spiralling toward the earth. Your orbital
defense platforms (‘ODP’s) have telescopes and railguns. The telescopes can
image the sky one ‘octant’ at a time. The railguns can fire ‘slugs’ to shoot
down the ‘rocks.’

- the earth is a point mass located at `(0, 0, 0)` in `(x, y, z)` space
- orbital defense platforms are located at `(0, 0, 0)` in `(x, y, z)` space
    - they orbit quickly enough that they can fire in any direction at any time
    - they orbit quickly enough that they can image the sky in any direction at any time
- each rock moves on a simple trajectory
    - these trajectories are ballistic and inertialess (no thrust)
    - these trajectories will spiral around the earth until impact
    - they are unaffected by gravitational forces
    - the trajectories are modelled by linear equations in spherical coördinates
- each slug moves on a linear (straight line) trajectory from the earth 
    - slugs can be aimed in any direction
    - these trajectories are ballistic and inertialess (no thrust)
    - slugs cannot turn; they move in straight lines only
    - the trajectories are modelled by linear equations in spherical coördinates
- slugs collide only with other rocks
    - slugs cannot collide other slugs, and rocks cannot collide other rocks
    - if the rock has a mass of 1, then collision with a slug vaporizes both
      the rock and slug immediately
    - if the rock has a mass greater than 1, then collision with a slug vaporizes the slug and rock but a rock fragment with smaller mass will be created

## JSON API

The orbital defense platforms can be controlled via JSON REST APIs. There are
two endpoints.

endpoint URL | HTTP verb | params | description 
-------------|-----------|--------|-------------
`/telescope/<int:octant>` | GET | `octant`, number from [0, 8] | images the specified `octant` (I - VIII) of the night sky and returns NEOs it sees
`/railgun` | POST | `name`, string<br>`phi`, number<br>`theta`, number | fires a slug named `name` at the specified angles `theta` and `phi`

The `/telescope` endpoint returns a JSON structure that looks like:
`{ "objects": [ obj, … ] }`

Each `obj` is a map with the following fields:

field | description
------|---------
type | the tye of object: rock or slug
name | the name of the object
mass | the mass of the object
fired | when the rock was fired at the earth or when the slug was fired into space
pos | the spherical coördinates of the object at observation time
cpos | the Caresian coördinates of the object at observation time
obs_time | the observation time
octant | the octant (I, II, III, IV, V, VI, VII, VIII) as an integer in which the object was spotted
age | the age of the object (how long it has been around since fired) in seconds 

### REST API EXAMPLE

Use `curl` or `http` (https://github.com/jakubroztocil/httpie/) to experiment with this API. Examples:

Take an image of octant I for search for objects.

```sh
$ http GET http://neocrisis.xyz/telescope/1
```

```http
HTTP/1.0 200 OK
Content-Length: 20
Content-Type: application/json
Date: Wed, 4 Jul 2018 09:00:00 EST
Server: Werkzeug/0.14.1 Python/3.6.6

{
    "objects": [
        {
            "age": 3600,
            "cpos": {
                "x": 0.0,
                "y": 0.0,
                "z": 100.0,
            },
            "fired": "2018-07-04T08:00:00.000000-04:00",
            "mass": 2,
            "name": "99942 apophis",
            "obs_time": "2018-07-04T09:00:00.000000-04:00",
            "octant": 1,
            "pos": {
                "phi": 0.0,
                "r": 100.0,
                "theta": 0.0
            },
            "type": "rock"
        }
    ]
}
```

Fire a slug at 99942 apophis.

```sh
$ http POST http://localhost:5000/railgun name='100 @ apophis' theta:=0 phi:=0
```

```http
HTTP/1.0 200 OK
Content-Length: 73
Content-Type: application/json
Date: Wed, 4 Jul 2018 09:00:01 EST
Server: Werkzeug/0.14.1 Python/3.6.6

{
    "slug": {
        "name": "100 @ apophis",
        "phi": 0.0,
        "theta": 0.0
    }
}
```

Image octant I again to see both the rock and the slug.

```sh
$ http GET http://neocrisis.xyz/telescope/1
```

```http
HTTP/1.0 200 OK
Content-Length: 20
Content-Type: application/json
Date: Wed, 4 Jul 2018 09:00:05 EST
Server: Werkzeug/0.14.1 Python/3.6.6

{
    "objects": [
        {
            "age": 3600,
            "cpos": {
                "x": 0.0,
                "y": 0.0,
                "z": 95.0,
            },
            "fired": "2018-07-04T08:00:00.000000-04:00",
            "mass": 2,
            "name": "99942 apophis",
            "obs_time": "2018-07-04T09:00:05.000000-04:00",
            "octant": 1,
            "pos": {
                "phi": 0.0,
                "r": 95.0,
                "theta": 0.0
            },
            "type": "rock"
        },
        {
            "age": 4,
            "cpos": {
                "x": 0.0,
                "y": 0.0,
                "z": 4.0,
            },
            "fired": "2018-07-04T09:00:01.000000-04:00",
            "mass": 1,
            "name": "100 @ apophis",
            "obs_time": "2018-07-04T09:00:05.000000-04:00",
            "octant": 1,
            "pos": {
                "phi": 0.0,
                "r": 4.0,
                "theta": 0.0
            },
            "type": "slug"
        }
    ]
}
```

## TRAJECTORIES and SPHERICAL COÖRDINATES

See [docs/trajectories.pdf](docs/trajectories.pdf) for more information.

The position of slugs and rocks can be described in terms of Cartesian
coördinates `(x, y, z)` or spherical coördinates `(r, θ, φ)`.

Our convention for Cartesian coördinates `(x, y, z)` is as follows:

Cartesian coördinate | measures | range & units | directional convention
---------------------|----------|---------------|-----------------------
`x`                  | distance | [0, ∞) meters | from the earth's core toward the 0° Prime Meridian (Greenwich, UK)
`y`                  | distance | [0, ∞) meters | from the earth's core toward the 90° meridian (Memphis, TN)
`z`                  | distance | [0, ∞) meters | from the earth's core toward 0° latitutde (North Pole)

Our convention for spherical coördinates `(r, θ, φ)` is as follows:

sperical coördinate      | measures | range & units   | directional convention
-------------------------|----------|-----------------|-----------------------
`r` ‘radius’             | distance | [0, ∞) meters   | from the earth's core  toward outer space
`θ` ‘theta’, ‘azimuth’   | *angle*  | [0, 2π] radians | <b>east-to-west</b> (longitudinally) from the 0° Prime Meridian (Greenwich, UK) toward the 90° meridian (Memphis, TN)
`φ` ‘phi’, ‘inclination’ | *angle*  | [0, π] radians  | <b>north-to-south</b> (latitudinally) from the North Pole to the South Pole

The trajectories of rocks and slugs follow the below equations.  The position
of an object is determined only by its parameters and `t`, time.

NEO   | params | r | phi | theta
------|--------|---|-----|-------
slugs | `v` velocity<br>`phi` fixed at fire time<br>`theta` fixed at fire time | `r = v × t` | `phi` | `theta`
rocks | `v` velocity<br>`r₀`initial radius<br><code>m<sub>φ</sub></code> phi-slope<br><code>b<sub>φ</sub></code> phi-intercept<br><code>m<sub>θ</sub></code> theta-slope<br><code>b<sub>θ</sub></code> theta-intercept | `r = v × t + r₀` | <code>phi = m<sub>φ</sub> × t + b<sub>φ</sub></code> | <code>theta = m<sub>θ</sub> × t + b<sub>θ</sub></code>

### MATH HELP and HINTS

Hints:
- the above equations are independent of each other: r, phi, and theta do not affect each other
- for the rocks, each equation has only two unknowns; therefore, you only need to talk two measurements to determine the unknowns

To compute the trajectory of a rock, take two measurements of its position in spherical coördinates `(r, θ, φ)`.
1. Two measurements are taken at <code>t<sub>1</sub></code> and <code>t<sub>2</sub></code>.
   - call them <code>(r<sub>1</sub>, phi<sub>1</sub>, theta<sub>1</sub>)</code> and <code>(r<sub>2</sub>, phi<sub>2</sub>, theta<sub>2</sub>)</code>
2. We want to solve for `v` and <code>r<sub>0</sub></code>.
   - we know that <code>r<sub>1</sub> = v × t<sub>1</sub> + r<sub>0</sub></code> and <code>r<sub>2</sub> = v × t<sub>2</sub> + r<sub>0</sub></code>
   - <b>therefore, <code>v = (r<sub>1</sub> - r<sub>2</sub>) ÷ (t<sub>1</sub> - t<sub>2</sub>)</code></b>
   - <b>therefore, <code>r<sub>0</sub> = r<sub>1</sub> - v × t<sub>1</sub></code></b> or <b><code>r<sub>0</sub> = r<sub>2</sub> - v × t<sub>2</sub></code></b>
3. We also want to solve for <code>m<sub>φ</sub></code> and <code>b<sub>φ</sub></code>.
   - we know that <code>phi<sub>1</sub> = m<sub>φ</sub> × t<sub>1</sub> + b<sub>φ</sub></code> and <code>phi<sub>2</sub> = m<sub>φ</sub> × t<sub>2</sub> + b<sub>φ</sub></code>
   - <b>therefore, <code>m<sub>φ</sub> = (phi<sub>1</sub> - phi<sub>2</sub>) ÷ (t<sub>1</sub> - t<sub>2</sub>)</code></b>
   - <b>therefore, <code>b<sub>φ</sub> = phi<sub>1</sub> - m<sub>φ</sub> × t<sub>1</sub></code></b> or <b><code>b<sub>φ</sub> = phi<sub>2</sub> - m<sub>φ</sub> × t<sub>2</sub></code></b>
4. Finally, we want to solve for <code>m<sub>θ</sub></code> and <code>b<sub>θ</sub></code>.
   - we know that <code>theta<sub>1</sub> = m<sub>θ</sub> × t<sub>1</sub> + b<sub>θ</sub></code> and <code>theta<sub>2</sub> = m<sub>θ</sub> × t<sub>2</sub> + b<sub>θ</sub></code>
   - <b>therefore, <code>m<sub>θ</sub> = (phi<sub>1</sub> - phi<sub>2</sub>) ÷ (t<sub>1</sub> - t<sub>2</sub>)</code></b>
   - <b>therefore, <code>b<sub>θ</sub> = phi<sub>1</sub> - m<sub>θ</sub> × t<sub>1</sub></code></b> or <b><code>b<sub>θ</sub> = phi<sub>2</sub> - m<sub>θ</sub> × t<sub>2</sub></code></b>
5. We need to compute direction in which to fire the slug; its `phi` and `theta` angles
   - we're given the slug's `v` velocity
   - we know the slug's `r` and the rock's `r` are the same at collision time <code>r<sub>slug</sub> = r<sub>rock</sub></code>
   - we know <code>r<sub>rock, collide</sub> = v<sub>rock</sub> × t<sub>collide</t> + r<sub>0</sub></code> and <code>r<sub>slug, collide</sub> = v<sub>slug</sub> × t<sub>collide</t></code>
   - <b>therefore, <code>t<sub>collide</t> = r<sub>0</sub> ÷ (v<sub>rock</sub> - v<sub>slug</sub>)</code></b>
   - knowing the collision time, we can determine the firing angles
   - <b>therefore, <code>phi<sub>collide</sub> = m<sub>φ</sub> × t<sub>collide</sub> + b<sub>φ</sub></code> and <code>theta<sub>collide</sub> = m<sub>0</sub> × t<sub>collide</sub> + b<sub>0</sub></code></b>

Altogether:
<pre>
    # solve for v and r<sub>0</sub>

    v = (r<sub>1</sub> - r<sub>2</sub>) ÷ (t<sub>1</sub> - t<sub>2</sub>)
    r<sub>0</sub> = r<sub>1</sub> - v × t<sub>1</sub>
    r<sub>0</sub> = r<sub>2</sub> - v × t<sub>2</sub>

    # solve for m<sub>φ</sub> and b<sub>φ</sub> 

    m<sub>φ</sub> = (phi<sub>1</sub> - phi<sub>2</sub>) ÷ (t<sub>1</sub> - t<sub>2</sub>)
    b<sub>φ</sub> = phi<sub>1</sub> - m<sub>φ</sub> × t<sub>1</sub>, b<sub>φ</sub> = phi<sub>2</sub> - m<sub>φ</sub> × t<sub>2</sub>

    # solve for m<sub>θ</sub> and b<sub>θ</sub> 

    m<sub>θ</sub> = (phi<sub>1</sub> - phi<sub>2</sub>) ÷ (t<sub>1</sub> - t<sub>2</sub>)
    b<sub>θ</sub> = phi<sub>1</sub> - m<sub>θ</sub> × t<sub>1</sub>, b<sub>θ</sub> = phi<sub>2</sub> - m<sub>θ</sub> × t<sub>2</sub>

    # solve for t<sub>collide</sub> 

    t<sub>collide</sub> = r<sub>0</sub> ÷ (v<sub>rock</sub> - v<sub>slug</sub>)

    # solve for phi<sub>collide</sub> and theta<sub>collide</sub> 

    phi<sub>collide</sub> = m<sub>φ</sub> × t<sub>collide</sub> + b<sub>φ</sub>
    theta<sub>collide</sub> = m<sub>0</sub> × t<sub>collide</sub> + b<sub>0</sub>
</pre>

## CODE and IMPLEMENTATOIN

#### game engine

The game engine lives entirely in the data model of a Postgres database.
- the data model is at [sql/model.sql](sql/model.sql)
- sample (test) data can be found at [sql/data.sql](sql/data.sql) 
- simple smoke tests (using the sample data) can be found at [sql/checks.sql](sql/checks.sql)

#### REST API

The REST API is a single file `flask` (https://github.com/pallets/flask) app.

You can find it at [api/api.py](api/api.py).

#### sample scripts

You can find some sample scripts in [scripts/](scripts/).
- [scripts/observer.py](scripts/observer.py) images the night sky in a loop and
  reports what it finds
- [scripts/autofire.py](scripts/autofire.py) is a sample automated defense system
  that scans and automatically fires at every object it sees

## MEETUPS

`neocrisis` is a collaborative coding game created by the folks behind NYC
Python! It has been played at the following events:

- ["Collaborative Code Night: NEO Crisis" (Aug 2, 2018)](https://www.meetup.com/nycpython/events/252249497/)

*Submit a PR to list any events where you've played NEO Crisis.*

## CREDITS and COPYRIGHT

\echo 'NEO-Crisis'
\echo 'http://github.com/dutc/neocrisis'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

begin;
    set search_path = game, public;

    select * from rocks;
    select * from slugs;

    select
        r.name
      , s.name
      , collision(r.fired, r.params, s.fired, s.params)
    from rocks as r, slugs as s;

    select
        r.name
      , s.name
      , r.fired
      , (collision(r.fired, r.params, s.fired, s.params)).t as collided
      , age(r.fired, (collision(r.fired, r.params, s.fired, s.params)).t) as t
    from rocks as r, slugs as s
    where (collision(r.fired, r.params, s.fired, s.params)).miss is null;

    select * from collisions;
    select * from active_collisions;
    select * from real_collisions;
    select * from fragments;
    select * from fragment_collisions;
    select * from active_fragment_collisions;
    select * from real_fragment_collisions;
end;

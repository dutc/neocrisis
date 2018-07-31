\echo 'NEO-Crisis <http://github.com/dutc/neocrisis>'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

begin;
    set search_path = api, game, public;

    select rock, slug, (collision).miss from collisions;
    select rock, slug from hits;
end;

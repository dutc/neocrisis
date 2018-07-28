\echo 'NEO-Crisis'
\echo 'http://github.com/dutc/neocrisis'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

do language plpgsql $$ declare
    exc_message text;
    exc_context text;
    exc_detail text;
begin

raise notice 'populating game data';
do $data$ begin
    set search_path = game, public;

    insert into rocks (name, fired, mass, params) values (
        'ceres'
        , date_trunc('day', now())
        , 9
        , row(0, 0, 0, 0, c() * 10, 0)
    );

    insert into rocks (name, mass, params) values (
        'eros'
        , 4
        , row(0, pi(), 0, pi(), c() * 10, 0)
    );

    insert into rocks (name, params) values (
        'tycho'
        , row(.1, pi(), 0, pi(), c() * 10, -c())
    );

    insert into rocks (name, params) values (
        'ganymede'
        , row(0, pi()/4, 0, pi()/4, c() * 10, 0)
    );

    insert into rocks (name, params) values (
        'luna'
        , row(0, 3, 0, 3, c() * 3600, 0)
    );

    insert into slugs (name, params) values (
        '100 @ ceres (hit)'
        , row(0, 0, c())
    );

    insert into slugs (name, params) values (
        '200 @ ceres (miss)'
        , row(0, 0, 0)
    );

    insert into slugs (name, params) values (
        '300 @ ceres (miss)'
        , row(1, 1, c())
    );

    insert into slugs (name, params) values (
        '400 @ eros (hit)'
        , row(pi() + 3 * 2 * pi(), pi() + 3 * 2 * pi(), c())
    );

    insert into slugs (name, params) values (
        '500 @ tycho (miss - late)'
        , row(.1 * 20/3 + pi(), pi(), c()/2)
    );

    insert into slugs (name, params) values (
        '600 @ tycho (hit)'
        , row(.1 * 5 + pi(), pi(), c())
    );

    insert into slugs (name, params) values (
        '700 @ ceres (miss - late)'
        , row(0, 0, .1 * c())
    );

end $data$;

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

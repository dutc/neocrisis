-- vim: set foldmethod=marker
\echo 'NEO-Crisis <http://github.com/dutc/neocrisis>'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

set transaction isolation level read uncommitted;

do language plpgsql $$ declare
    exc_message text;
    exc_context text;
    exc_detail text;
begin

create function pg_temp.insert_rock( -- {{{
    name text
    , params rock_params
    , fired timestamp with time zone default now()
    , mass integer default 4
    )
returns void as $func$
begin
    insert into rocks (name, fired, mass, params)
    values (name, fired, mass, params);
end;
$func$ language plpgsql; -- }}}

create function pg_temp.insert_slug( -- {{{
    name text
    , params slug_params
    , fired timestamp with time zone default now()
    )
returns void as $func$
begin
    insert into slugs (name, fired, params)
    values (name, fired, params);
end;
$func$ language plpgsql; -- }}}

raise info 'populating game data';
do $data$ begin
    set search_path = game, public;

    -- {{{ rocks
    raise info 'populating rocks';
    perform pg_temp.insert_rock(
        'ceres'
        , row(0, 0, 0, 0, c() * 10, 0)
        , date_trunc('day', now())
        , 9
    );
    perform pg_temp.insert_rock('eros', row(0, pi_(), 0, pi_(), c() * 10, 0));
    perform pg_temp.insert_rock('tycho', row(.1, pi_(), 0, pi_(), c() * 10, -c()));
    perform pg_temp.insert_rock('ganymede', row(0, pi_()/4, 0, pi_()/4, c() * 10, 0));
    perform pg_temp.insert_rock('luna', row(0, 3, 0, 3, c() * 3600, 0));
    -- }}}

    -- {{{ slugs
    raise info 'populating slugs';
    perform pg_temp.insert_slug('100 @ ceres (hit)', row(0, 0, c()));
    perform pg_temp.insert_slug('200 @ ceres (miss)', row(0, 0, 0));
    perform pg_temp.insert_slug('300 @ ceres (miss)', row(1, 1, c()));
    perform pg_temp.insert_slug('400 @ eros (hit)', row(pi_() + 3 * 2 * pi_(), pi_() + 3 * 2 * pi_(), c()));
    perform pg_temp.insert_slug('500 @ tycho (miss - late)', row(.1 * 20/3 + pi_(), pi_(), c()/2));
    perform pg_temp.insert_slug('600 @ tycho (hit)', row(.1 * 5 + pi_(), pi_(), c()));
    perform pg_temp.insert_slug('700 @ ceres (miss - late)', row(0, 0, .1 * c()));
    -- }}}

end $data$;

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

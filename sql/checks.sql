\echo 'NEO-Crisis <http://github.com/dutc/neocrisis>'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

create function pg_temp.check_hits(num integer) -- {{{
returns void as $func$
begin
    assert array_length(array(select 1 from hits), 1) = num, 'too many/few hits';
    assert array_length(array(select distinct rock from hits), 1) = num
        , 'repeated rock';
    assert array_length(array(select distinct slug from hits), 1) = num
        , 'repeated slug';
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

do $$
begin
    set search_path = game, public;

    raise info 'check initial';
    perform pg_temp.check_hits(4);
    assert (array(select slug from api.hits where rock = 'ceres'))[1]
        = '100 @ ceres (hit)', 'wrong hit for ceres';
    assert (array(select slug from api.hits where rock = 'ceres I'))[1]
        = '700 @ ceres (miss - late)', 'wrong hit for ceres I';
    assert (array(select slug from api.hits where rock = 'tycho'))[1]
        = '600 @ tycho (hit)', 'wrong hit for tycho';

    raise info 'check insert slug';
    perform pg_temp.insert_slug('800 @ luna (hit)', row(3, 3, c()));
    perform pg_temp.check_hits(5);
    assert (array(select slug from api.hits where rock = 'luna'))[1]
        = '800 @ luna (hit)', 'wrong hit for luna';

    raise info 'check insert slug miss';
    perform pg_temp.insert_slug('900 @ ganymede (miss)', row(pi_()/4, pi_()/4, 0));
    perform pg_temp.check_hits(5);
    assert (array(select slug from api.hits where rock = 'ganymede'))[1]
        is null, 'wrong hit for ganymede';

    raise info 'check update slug (miss → hit)';
    update slugs
    set name = '900 @ ganymede (hit)', params.v = c()
    where name = '900 @ ganymede (miss)';
    perform pg_temp.check_hits(6);
    assert (array(select slug from api.hits where rock = 'ganymede'))[1]
        = '900 @ ganymede (hit)', 'wrong hit for ganymede';

    raise info 'check delete slug';
    delete from slugs
    where name = '900 @ ganymede (hit)';
    perform pg_temp.check_hits(5);
    assert (array(select slug from api.hits where rock = 'ganymede'))[1]
        is null, 'wrong hit for ganymede';

    raise info 'check update slug (hit → faster hit)';
    update slugs
    set params.v = 100 * c(), name = '700 @ ceres (hit)'
    where name = '700 @ ceres (miss - late)';
    perform pg_temp.check_hits(5);
    assert (array(select slug from api.hits where rock = 'ceres'))[1]
        = '700 @ ceres (hit)', 'wrong hit for ceres';
    assert (array(select slug from api.hits where rock = 'ceres I'))[1]
        = '100 @ ceres (hit)', 'wrong hit for ceres I';

    raise info 'check update rock (lower mass)';
    update rocks
    set mass = 1
    where name = 'ceres';
    perform pg_temp.check_hits(4);
    assert (array(select slug from api.hits where rock = 'ceres'))[1]
        = '700 @ ceres (hit)', 'wrong hit for ceres';

    raise info 'check update rock (increase mass)';
    update rocks
    set mass = 4
    where name = 'ceres';
    perform pg_temp.check_hits(5);

    raise info 'check update rock (move → miss)';
    update rocks
    set params.b_theta = (params).b_theta + pi_() / 8
    where name = 'eros';
    perform pg_temp.check_hits(4);
    assert (array(select slug from api.hits where rock = 'eros'))[1]
        is null, 'wrong hit for eros';
    assert array_length(array(select name from rocks where name like 'eros%'), 1)
        = 1, 'incorrect eros fragments';

    raise info 'check update rock (move → hit)';
    update rocks
    set params.b_theta = (params).b_theta - pi_() / 8
    where name = 'eros';
    perform pg_temp.check_hits(5);
    assert (array(select slug from api.hits where rock = 'eros'))[1]
        = '400 @ eros (hit)', 'wrong hit for eros';
    assert array_length(array(select name from rocks where name like 'eros%'), 1)
        = 2, 'incorrect eros fragments';
end $$;

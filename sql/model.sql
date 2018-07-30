-- vim: set foldmethod=marker
\echo 'NEO-Crisis <http://github.com/dutc/neocrisis>'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

do language plpgsql $$ declare
    exc_message text;
    exc_context text;
    exc_detail text;
begin

-- {{{ setup
raise info 'initial setup';
do $setup$ begin
create extension if not exists intarray;

raise info 'dropping schemas'; -- {{{
drop schema if exists game cascade;
drop schema if exists api cascade;
-- }}}

raise info 'creating schemas'; -- {{{
create schema if not exists game;
create schema if not exists api;
-- }}}

raise info 'removing public functions'; -- {{{
drop function if exists public.c cascade;
drop function if exists public.pi_ cascade;
drop function if exists public.error cascade;
-- }}}

raise info 'populating public functions'; -- {{{
create or replace function public.c() returns numeric
immutable language sql as 'select 299792458.0';

create or replace function public.pi_() returns numeric
immutable language sql as 'select pi()::numeric';

create or replace function public.error() returns trigger as $func$
begin
    raise exception 'error: %', tg_argv[0];
end;
$func$ immutable language plpgsql;
-- }}}

end $setup$; -- }}}

-- {{{ types
raise info 'populating types';
do $types$ begin
    set search_path = game, public;

    drop type if exists rock_params cascade;
    drop type if exists slug_params cascade;
    drop type if exists pos cascade;
    drop type if exists mtype cascade;
    drop type if exists collision cascade;

    create type rock_params as ( -- {{{
        m_theta   numeric
        , b_theta numeric
        , m_phi   numeric
        , b_phi   numeric
        , r_0     numeric
        , v       numeric
    ); -- }}}

    create type slug_params as ( -- {{{
        theta numeric
        , phi numeric
        , v   numeric
    ); -- }}}

    create type pos as ( -- {{{
        r numeric
        , theta numeric
        , phi numeric
    ); -- }}}

    create type mtype as enum ('r', 'theta', 'phi');

    create type collision as ( -- {{{
        t timestamp with time zone
        , pos pos
        , miss mtype[]
    ); -- }}}

end $types$; -- }}}

-- {{{ built-in functions
raise info 'extending built-in functions';
do $funcs$ begin

    create or replace function round(v pos, s int) -- {{{
    returns pos as $func$
    begin
        return (round((v.r), s), round((v.theta), s), round((v.phi), s))::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function round(v rock_params, s int) -- {{{
    returns rock_params as $func$
    begin
        return (round((v.r), s), round((v.theta), s), round((v.phi), s))::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function round(v slug_params, s int) -- {{{
    returns slug_params as $func$
    begin
        return (round((v.r), s), round((v.theta), s), round((v.phi), s))::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

end $funcs$; -- }}}

-- {{{ custom functions
raise info 'populating custom functions';
do $funcs$ begin
    set search_path = game, public;

    drop function if exists normalize cascade;
    drop function if exists pos cascade;
    drop function if exists collide cascade;
    drop function if exists collisions cascade;
    drop function if exists hits cascade;
    drop function if exists predicted_hits cascade;

    drop type if exists uniq_hits_t cascade;
    drop function if exists uniq_hits_sfunc cascade;
    drop aggregate if exists uniq_hits (integer) cascade;

    create or replace function normalize(v pos) -- {{{
    returns pos as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi_()), mod((v).phi, pi_()))::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function normalize(v rock_params) -- {{{
    returns rock_params as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi_()), mod((v).phi, pi_()))::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function normalize(v slug_params) -- {{{
    returns slug_params as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi_()), mod((v).phi, pi_()))::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function pos( -- {{{
        fired timestamp with time zone
        , params rock_params
        , t_now timestamp with time zone
        , delay boolean = false
        )
    returns pos as $func$
    declare
        t numeric;
        r numeric;
        theta numeric;
        phi numeric;
    begin
        t := extract(epoch from t_now - fired);
        if delay is true then
            r := (params).r_0 + (params).v * t;
            t := t - r / c();
        end if;
        r := (params).r_0 + (params).v * t;
        theta := (params).m_theta * t + (params).b_theta;
        phi := (params).m_phi * t + (params).b_phi;
        return (r, theta, phi)::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function pos( -- {{{
        fired timestamp with time zone
        , params slug_params
        , t_now timestamp with time zone
        , delay boolean = false
        )
    returns pos as $func$
    declare
        t numeric;
        r numeric;
        theta numeric;
        phi numeric;
    begin
        t := extract(epoch from t_now - fired);
        if delay is true then
            r := (params).v * t;
            t := t - r / c();
        end if;
        r := (params).v * t;
        theta = (params).theta;
        phi = (params).phi;
        return (r, theta, phi)::pos;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function collide( -- {{{
        rock_fired timestamp with time zone
        , rock       rock_params
        , slug_fired timestamp with time zone
        , slug       slug_params
        )
    returns collision as $func$
    declare
        rock_t_0 numeric;
        slug_t_0 numeric;
        rel_v numeric;
        rock_pos pos;
        slug_pos pos;
        t timestamp with time zone;
        m mtype[];
    begin
        rock_t_0 := extract(epoch from rock_fired);
        slug_t_0 := extract(epoch from slug_fired);
        rel_v := (slug).v - (rock).v;
        if rel_v <> 0 then
            t := timestamp with time zone 'epoch' + interval '1 second' *
                 (((rock).r_0 + (slug).v * slug_t_0 - (rock).v * rock_t_0)
                 / rel_v);
            if t >= rock_fired and t >= slug_fired then
                rock_pos := pos(rock_fired, rock, t);
                slug_pos := pos(slug_fired, slug, t);

                rock_pos := round(normalize(rock_pos), 4);
                slug_pos := round(normalize(slug_pos), 4);

                if (rock_pos).theta <> (slug_pos).theta then
                    m := m || 'theta'::mtype;
                end if;
                if (rock_pos).phi <> (slug_pos).phi then
                    m := m || 'phi'::mtype;
                end if;
            else
                m := m || 'r'::mtype;
            end if;
        else
            m := m || 'r'::mtype;
        end if;
        return (t, slug_pos, m)::collision;
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function collisions( -- {{{
        slug_id integer
        , slug_fired timestamp with time zone
        , slug_params slug_params
        )
    returns table (
        rock integer
        , slug integer
        , collision collision
        ) as $func$
    begin
        return query
        select
            r.id
            , slug_id
            , collide(r.fired, r.params, slug_fired, slug_params)
        from rocks as r;
    end;
    $func$ stable language plpgsql; -- }}}

    create or replace function collisions( -- {{{
        rock_id integer
        , rock_fired timestamp with time zone
        , rock_params rock_params
        )
    returns table (
        rock integer
        , slug integer
        , collision collision
        ) as $func$
    begin
        return query
        select
            rock_id
            , s.id
            , collide(rock_fired, rock_params, s.fired, s.params)
        from slugs as s;
    end;
    $func$ stable language plpgsql; -- }}}

    create type uniq_hits_t as ( -- {{{
        uniq boolean
        , rocks integer[]
        , slugs integer[]
    ); -- }}}

    create or replace function uniq_hits_sfunc( -- {{{
        acc uniq_hits_t
        , rock integer
        , slug integer
    )
    returns uniq_hits_t as $func$
    begin
        return case
            when (acc).rocks @> array[rock] or (acc).slugs @> array[slug]
            then (false, (acc).rocks, (acc).slugs)
            else (true, (acc).rocks || array[rock], (acc).slugs || array[slug])
        end;
    end;
    $func$ immutable language plpgsql; -- }}}

    create aggregate uniq_hits (integer, integer) ( -- {{{
        sfunc = uniq_hits_sfunc
        , stype = uniq_hits_t
        , initcond = '(,{},{})'
    ); -- }}}

    create or replace function hits() -- {{{
    returns table (
        rock integer
        , slug integer
        , collision collision
    ) as $func$
    begin
        return query
        select x.rock, x.slug, x.collision
        from (
            select
                c.rock
                , c.slug
                , c.collision
                , uniq_hits(c.rock, c.slug) over win
            from game.collisions as c
            where (c.collision).miss is null
            window win as (
                partition by 1
                order by (c.collision).t, c.id
                rows between unbounded preceding and current row
            )
        ) as x
        where (x.uniq_hits).uniq is true;
    end;
    $func$ stable language plpgsql; -- }}}

end $funcs$; -- }}}

-- {{{ triggers
raise info 'populating trigger functions';
do $funcs$ begin
    set search_path = game, public;

    drop function if exists slugs_trigger;
    drop function if exists rocks_trigger;
    drop function if exists hits_trigger;
    drop function if exists const_id;

    create or replace function slugs_trigger() -- {{{
    returns trigger as $trig$
    begin
        raise info 'trigger: %.%.% % ("%")', tg_table_schema, tg_table_name, tg_name, tg_op, new.name;

        if tg_op = 'INSERT' then
            insert into collisions
                (rock, slug, collision)
                select * from game.collisions(new.id, new.fired, new.params);
        elsif tg_op = 'UPDATE' and new <> old then
            update collisions set
                collision = collide(r.fired, r.params, new.fired, new.params)
            from rocks as r
            where r.id = rock and new.id = slug;
        end if;
        return new;
    end;
    $trig$ language plpgsql; -- }}}

    create or replace function rocks_trigger() -- {{{
    returns trigger as $trig$
    begin
        raise info 'trigger: %.%.% % ("%")', tg_table_schema, tg_table_name, tg_name, tg_op, new.name;

        if tg_op = 'INSERT' then
            insert into collisions
                (rock, slug, collision)
                select * from game.collisions(new.id, new.fired, new.params);
        elsif tg_op = 'UPDATE' and new <> old then
            if new.mass <> old.mass then
                -- mass changed: may affect fragmenting behavior
                delete from rocks where source_rock = new.id;
                delete from game.hits where rock = new.id;
            end if;
            update collisions set
                collision = collide(new.fired, new.params, s.fired, s.params)
            from slugs as s
            where s.id = slug and new.id = rock;
        end if;

        return new;
    end;
    $trig$ language plpgsql; -- }}}

    create or replace function collisions_trigger() -- {{{
    returns trigger as $trig$
    declare
        _rock text;
        _slug text;
    begin
        _rock := (select name from rocks where id = new.rock limit 1);
        _slug := (select name from slugs where id = new.slug limit 1);
        raise info 'trigger: %.%.% % (%, %)', tg_table_schema, tg_table_name, tg_name, tg_op, _rock, _slug;

        with
            before as (select rock, slug, collision from game.hits)
            , after as (select rock, slug, collision from hits())
            , diff as (select * from before except select * from after)
        delete from hits where rock in (select rock from diff);

        with
            before as (select rock, slug, collision from game.hits)
            , after as (select rock, slug, collision from hits())
            , diff as (select * from after except select * from before)
        insert into hits (rock, slug, collision) select * from diff;

        return new;
    end;
    $trig$ language plpgsql; -- }}}

    create or replace function hits_trigger() -- {{{
    returns trigger as $trig$
    declare
        src_name text;
        src_mass integer;
        src_params rock_params;
        count integer;

        _rock text;
        _slug text;
    begin
        _rock := (select name from rocks where id = new.rock limit 1);
        _slug := (select name from slugs where id = new.slug limit 1);
        raise info 'trigger: %.%.% % ("%", "%")', tg_table_schema, tg_table_name, tg_name, tg_op, _rock, _slug;

        src_name := (select coalesce(source_name, name) from rocks where id = new.rock limit 1);
        src_mass := (select mass from rocks where id = new.rock limit 1);
        src_params := (select params from rocks where id = new.rock limit 1);
        count := (select count(*) from rocks where source_name = src_name or name = src_name);

        if src_mass <= 1 then
            return new;
        end if;

        insert into rocks (
            source_name
            , source_rock
            , source_hit
            , name
            , mass
            , fired
            , params
            )
        values (
            src_name
            , new.rock
            , new.id
            , src_name || to_char(count, ' FMRN')
            , src_mass / 2
            , (new.collision).t
            , (
                (src_params).m_theta / 2
                , (src_params).b_theta + (src_params).m_theta / 2 * extract(epoch from (new.collision).t)
                , (src_params).m_phi / 2
                , (src_params).b_phi + (src_params).b_phi / 2 * extract(epoch from (new.collision).t)
                , (new.collision).pos.r + 1
                , (src_params).v
            )::rock_params
        );
        return new;
    end;
    $trig$ language plpgsql; -- }}}

end $funcs$; -- }}}

-- {{{ tables
raise info 'populating tables';
do $tables$
begin
    set search_path = game, public;

    drop table if exists slugs cascade;
    drop table if exists rocks cascade;
    drop table if exists collisions cascade;
    drop table if exists hits cascade;

    create table if not exists slugs ( -- {{{
        id serial primary key
        , name text not null
        , fired timestamp with time zone default now()
        , params slug_params not null default (0, 0, 0)
            check (
                (params).theta is not null
                and (params).phi is not null
                and (params).v is not null
            )
    ) with oids;
    -- }}}

    create table if not exists rocks ( -- {{{
        id serial primary key
        , name text not null
        , mass integer not null default 4
        , fired timestamp with time zone default now()
        , params rock_params not null default (0, 0, 0, 0, 0, 0)
            check (
                (params).m_theta is not null
                and (params).b_theta is not null
                and (params).m_phi is not null
                and (params).b_phi is not null
                and (params).r_0 is not null
                and (params).v is not null
            )
    ) with oids;
    create index rocks_id on rocks (id);
    -- }}}

    create table if not exists collisions ( -- {{{
        id serial primary key
        , rock integer not null references rocks (id) on delete cascade
        , slug integer not null references slugs (id) on delete cascade
        , collision collision
    ) with oids;
    create index collisions_rock on collisions (rock);
    create index collisions_collision on collisions (collision) where not collision is null;
    create index collisions_collision_t on collisions (((collision).t));
    create index collisions_collision_miss on collisions (((collision).miss));
    -- }}}

    create table if not exists hits ( -- {{{
        id serial primary key
        , rock integer not null references rocks (id) on delete cascade
        , slug integer not null references slugs (id) on delete cascade
        , collision collision
        , phase timestamp with time zone not null default now()
    );
    alter table rocks add column source_name text default null;
    alter table rocks add column source_rock integer default null references rocks (id) on delete cascade;
    alter table rocks add column source_hit integer default null references hits (id) on delete cascade;
    -- }}}

    drop trigger if exists slugs_trigger on slugs;
    drop trigger if exists rocks_trigger on rocks;
    drop trigger if exists collisions_trigger on collisions;
    drop trigger if exists hits_trigger on hits;

    drop trigger if exists slugs_id_trigger on slugs;
    drop trigger if exists rocks_id_trigger on rocks;
    drop trigger if exists collisions_id_trigger on collisions;
    drop trigger if exists hits_id_trigger on hits;

    create trigger slugs_trigger after insert or update on slugs
        for each row execute procedure slugs_trigger();
    create trigger rocks_trigger after insert or update on rocks
        for each row execute procedure rocks_trigger();
    create trigger collisions_trigger after insert or update on collisions
        for each row execute procedure collisions_trigger();
    create trigger hits_trigger after insert on hits
        for each row execute procedure hits_trigger();

    create trigger slugs_id_trigger before update of id on slugs
        for each statement execute procedure error('cannot change id');
    create trigger rocks_id_trigger before update of id on rocks
        for each statement execute procedure error('cannot change id');
    create trigger collisions_id_trigger before update of id on collisions
        for each statement execute procedure error('cannot change id');
    create trigger hits_id_trigger before update of id on hits
        for each statement execute procedure error('cannot change id');

end $tables$; -- }}}

-- {{{ views
raise info 'populating api views';
do $views$
begin
    set search_path = api, game, public;

    drop view if exists api.collisions;
    drop view if exists api.hits;

    create or replace view collisions as ( -- {{{
        select
            c.id
            , r.name as rock
            , s.name as slug
            , c.collision
        from game.collisions as c
        inner join rocks as r on (c.rock = r.id)
        inner join slugs as s on (c.slug = s.id)
    ); -- }}}

    create or replace view hits as (-- {{{
        select
            h.id
            , r.name as rock
            , s.name as slug
            , h.collision
        from game.hits as h
        inner join rocks as r on (h.rock = r.id)
        inner join slugs as s on (h.slug = s.id)
    ); -- }}}

end $views$; -- }}}

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

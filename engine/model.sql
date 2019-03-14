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
drop function if exists public.sin_ cascade;
drop function if exists public.cos_ cascade;
drop function if exists public.error cascade;
-- }}}

raise info 'populating public functions'; -- {{{
create or replace function public.c() returns numeric
immutable language sql as 'select 299792458.0';

create or replace function public.pi_() returns numeric
immutable language sql as 'select pi()::numeric';

create or replace function public.sin_(numeric) returns numeric
immutable language sql as 'select sin($1)::numeric';

create or replace function public.cos_(numeric) returns numeric
immutable language sql as 'select cos($1)::numeric';

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

    create type cpos as ( -- {{{
        x numeric
        , y numeric
        , z numeric
    ); -- }}}

    create type mtype as enum ('r', 'theta', 'phi');

    create type collision as ( -- {{{
        t timestamp with time zone
        , pos pos
        , mdiff pos
        , miss mtype[]
    ); -- }}}

end $types$; -- }}}

-- {{{ built-in functions
raise info 'extending built-in functions';
do $funcs$ begin

    create or replace function round(v pos, s int) -- {{{
    returns pos as $func$
    begin
        return (round((v).r, s), round((v).theta, s), round((v).phi, s));
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function round(v rock_params, s int) -- {{{
    returns rock_params as $func$
    begin
        return (
            round((v).m_theta, s)
            , round((v).b_theta, s)
            , round((v).m_phi, s)
            , round((v).b_phi, s)
            , round((v).r_0, s)
            , round((v).v, s)
        );
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function round(v slug_params, s int) -- {{{
    returns slug_params as $func$
    begin
        return (round((v).r, s), round((v).theta, s), round((v).phi, s));
    end;
    $func$ immutable language plpgsql; -- }}}

end $funcs$; -- }}}

-- {{{ custom functions
raise info 'populating custom functions';
do $funcs$ begin
    set search_path = game, public;

    drop function if exists normalize cascade;
    drop function if exists pos2cpos cascade;
    drop function if exists octant cascade;
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
        return ((v).r, mod((v).theta, 2*pi_()), mod((v).phi, pi_()));
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function normalize(v rock_params) -- {{{
    returns rock_params as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi_()), mod((v).phi, pi_()));
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function normalize(v slug_params) -- {{{
    returns slug_params as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi_()), mod((v).phi, pi_()));
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function pos2cpos(v pos) -- {{{
    returns cpos as $func$
    begin
        return (
            (v).r * sin_((v).phi) * cos_((v).theta)
            , (v).r * sin_((v).phi) * sin_((v).theta)
            , (v).r * cos_((v).phi)
        );
    end;
    $func$ immutable language plpgsql; -- }}}

    create or replace function octant(v pos) -- {{{
    returns integer as $func$
    declare
        c game.cpos;
    begin
        c := game.pos2cpos(v);
        return case
            when (c).x >= 0 and (c).y >= 0 and (c).z >= 0 then 1
            when (c).x <  0 and (c).y >= 0 and (c).z >= 0 then 2
            when (c).x <  0 and (c).y <  0 and (c).z >= 0 then 3
            when (c).x >= 0 and (c).y <  0 and (c).z >= 0 then 4
            when (c).x >= 0 and (c).y >= 0 and (c).z <  0 then 5
            when (c).x <  0 and (c).y >= 0 and (c).z <  0 then 6
            when (c).x <  0 and (c).y <  0 and (c).z <  0 then 7
            when (c).x >= 0 and (c).y <  0 and (c).z <  0 then 8
            else null
        end;
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
        return (r, theta, phi);
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
        return (r, theta, phi);
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
        rock_pos game.pos;
        slug_pos game.pos;
        t timestamp with time zone;
        m game.mtype[];
    begin
        rock_t_0 := extract(epoch from rock_fired);
        slug_t_0 := extract(epoch from slug_fired);
        rel_v := (slug).v - (rock).v;
        if rel_v <> 0 then
            t := timestamp with time zone 'epoch' + interval '1 second' *
                 (((rock).r_0 + (slug).v * slug_t_0 - (rock).v * rock_t_0)
                 / rel_v);
            if t >= rock_fired and t >= slug_fired then
                rock_pos := game.pos(rock_fired, rock, t);
                slug_pos := game.pos(slug_fired, slug, t);

                rock_pos := game.round(game.normalize(rock_pos), 4);
                slug_pos := game.round(game.normalize(slug_pos), 4);

                if (rock_pos).theta <> (slug_pos).theta then
                    m := m || 'theta'::game.mtype;
                end if;
                if (rock_pos).phi <> (slug_pos).phi then
                    m := m || 'phi'::game.mtype;
                end if;
            else
                m := m || 'r'::game.mtype;
            end if;
        else
            m := m || 'r'::game.mtype;
        end if;
        return (
            t
            , slug_pos
            , (
                (rock_pos).r - (slug_pos).r
                , (rock_pos).theta - (slug_pos).theta
                , (rock_pos).phi - (slug_pos).phi
            )::game.pos
            , m
        );
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
            , game.collide(r.fired, r.params, slug_fired, slug_params)
        from game.rocks as r;
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
            , game.collide(rock_fired, rock_params, s.fired, s.params)
        from game.slugs as s;
    end;
    $func$ stable language plpgsql; -- }}}

    create type uniq_hits_t as ( -- {{{
        uniq boolean
        , rocks integer[]
        , slugs integer[]
    ); -- }}}

    create or replace function uniq_hits_sfunc( -- {{{
        acc game.uniq_hits_t
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
                , game.uniq_hits(c.rock, c.slug) over win
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
            insert into game.collisions
                (rock, slug, collision)
                select * from game.collisions(new.id, new.fired, new.params);
        elsif tg_op = 'UPDATE' and new <> old then
            update game.collisions set
                collision = game.collide(r.fired, r.params, new.fired, new.params)
            from game.rocks as r
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
            insert into game.collisions
                (rock, slug, collision)
                select * from game.collisions(new.id, new.fired, new.params);
        elsif tg_op = 'UPDATE' and new <> old then
            if new.mass <> old.mass then
                -- mass changed: may affect fragmenting behavior
                delete from game.rocks where source_rock = new.id;
                delete from game.hits where rock = new.id;
            end if;
            update game.collisions set
                collision = game.collide(new.fired, new.params, s.fired, s.params)
            from game.slugs as s
            where s.id = slug and new.id = rock;
        end if;

        return new;
    end;
    $trig$ language plpgsql; -- }}}

    create or replace function collisions_trigger() -- {{{
    returns trigger as $trig$
    begin
        raise info 'trigger: %.%.% %', tg_table_schema, tg_table_name, tg_name, tg_op;

        with
            before as (select rock, slug, collision from game.hits)
            , after as (select rock, slug, collision from game.hits())
            , diff as (select * from before except select * from after)
        delete from game.hits where rock in (select rock from diff);

        if tg_op <> 'DELETE' then
            with
                before as (select rock, slug, collision from game.hits)
                , after as (select rock, slug, collision from game.hits())
                , diff as (select * from after except select * from before)
            insert into game.hits (rock, slug, collision) select * from diff;
        else
            -- NOTE|dutc: processing a delete sometimes inadvertently leads to
            --            inserts on non-existent rocks (invalid fragments);
            --            add subselect to eliminate these
            with
                before as (select rock, slug, collision from game.hits)
                , after as (select rock, slug, collision from game.hits())
                , diff as (select * from after except select * from before)
            insert into game.hits (rock, slug, collision)
            select * from diff where rock in (select id from game.rocks);
        end if;

        return new;
    end;
    $trig$ language plpgsql; -- }}}

    create or replace function hits_trigger() -- {{{
    returns trigger as $trig$
    declare
        src_name text;
        src_mass integer;
        src_params game.rock_params;
        count integer;

        _rock text;
        _slug text;
    begin
        _rock := (select name from game.rocks where id = new.rock limit 1);
        _slug := (select name from game.slugs where id = new.slug limit 1);
        raise info 'trigger: %.%.% % ("%", "%")', tg_table_schema, tg_table_name, tg_name, tg_op, _rock, _slug;

        src_name := (select coalesce(source_name, name) from game.rocks where id = new.rock limit 1);
        src_mass := (select mass from game.rocks where id = new.rock limit 1);
        src_params := (select params from game.rocks where id = new.rock limit 1);
        count := (select count(*) from game.rocks where source_name = src_name or name = src_name);

        if src_mass <= 1 then
            return new;
        end if;

        insert into game.rocks (
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
            )::game.rock_params
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
        , target text
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
        , target text
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
    alter table collisions add constraint collisions_uniq_rock_slug unique(rock, slug);
    create index collisions_rock on collisions (rock);
    create index collisions_collision on collisions (collision) where not collision is null;
    create index collisions_collision_t on collisions (((collision).t));
    create index collisions_collision_miss on collisions (((collision).miss));
    -- }}}

    create table if not exists hits ( -- {{{
        id serial primary key
        , rock integer unique not null references rocks (id) on delete cascade
        , slug integer unique not null references slugs (id) on delete cascade
        , collision collision
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
    -- NOTE|dutc: collisions_trigger is STATEMENT level
    create trigger collisions_trigger after insert or update or delete on collisions
        for each statement execute procedure collisions_trigger();
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

    drop view if exists api.rocks;
    drop view if exists api.slugs;
    drop view if exists api.all_neos;
    drop view if exists api.neos;
    drop view if exists api.collisions;
    drop view if exists api.hits;

    create or replace view rocks as (
        select
            r.id
            , r.name
            , r.target
            , r.mass
            , r.fired
            , (h.collision).t as collided
            , r.params
            , (h.collision)
            , pos(r.fired, r.params, now())
            , pos(r.fired, r.params, now(), true) as delay_pos
            , pos2cpos(pos(r.fired, r.params, now())) as cpos
            , pos2cpos(pos(r.fired, r.params, now(), true)) as delay_cpos
            , octant(pos(r.fired, r.params, now()))
            , octant(pos(r.fired, r.params, now(), true)) as delay_octant
            , now() as t
            , now() - r.fired as age
        from game.rocks as r
        left outer join game.hits as h
           on (r.id = h.rock)
    );

    create or replace view slugs as (
        select
            s.id
            , s.name
            , s.target
            , s.fired
            , (h.collision).t as collided
            , s.params
            , (h.collision)
            , pos(s.fired, s.params, now())
            , pos(s.fired, s.params, now(), true) as delay_pos
            , pos2cpos(pos(s.fired, s.params, now())) as cpos
            , pos2cpos(pos(s.fired, s.params, now(), true)) as delay_cpos
            , octant(pos(s.fired, s.params, now()))
            , octant(pos(s.fired, s.params, now(), true)) as delay_octant
            , now() as t
            , now() - s.fired as age
        from game.slugs as s
        left outer join game.hits as h
           on (s.id = h.slug)
    );

    create or replace view all_neos as (
            select
                'rocks'::regclass
                , id
                , name
                , target
                , mass
                , fired
                , collided
                , params as rock_params
                , null as slug_params
                , collision
                , pos
                , delay_pos
                , cpos
                , delay_cpos
                , octant
                , delay_octant
                , t
                , age
            from rocks
        union
            select
                'slugs'::regclass
                , id
                , name
                , target
                , 1 as mass
                , fired
                , collided
                , null as rock_params
                , params as slug_params
                , collision
                , pos
                , delay_pos
                , cpos
                , delay_cpos
                , octant
                , delay_octant
                , t
                , age
            from slugs
    );

    create or replace view neos as (
        select *
        from all_neos
        where fired <= now()
            and (collided is null or collided > now())
            and ((pos).r >= 0)
    );

    create or replace view collisions as ( -- {{{
        select
            c.id
            , r.name as rock
            , s.name as slug
            , c.collision
        from game.collisions as c
        inner join game.rocks as r on (c.rock = r.id)
        inner join game.slugs as s on (c.slug = s.id)
    ); -- }}}

    create or replace view hits as (-- {{{
        select
            h.id
            , r.name as rock
            , s.name as slug
            , h.collision
        from game.hits as h
        inner join game.rocks as r on (h.rock = r.id)
        inner join game.slugs as s on (h.slug = s.id)
    ); -- }}}

    create or replace view misses as (-- {{{
        with misses as (
            select distinct id from game.rocks
                except
            select distinct rock as id from game.hits
        )
        select
            r.name as rock
            , r.fired as fired
            , (
                r.fired + interval '1 second' * ((r).params.r_0 / -(r).params.v)
                , normalize(game.pos(r.fired, r.params,
                    r.fired + interval '1 second' * ((r).params.r_0 / -(r).params.v)))
                , (0, 0, 0)::pos
                , null
            )::collision as collision
            , r.target
        from game.rocks as r
        inner join misses as m on (m.id = r.id)
        where r.fired + interval '1 second' * ((r).params.r_0 / -(r).params.v) < now()
    ); -- }}}

end $views$; -- }}}

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

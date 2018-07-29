-- vim: set foldmethod=marker
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

-- {{{ setup
raise notice 'initial setup';
do $setup$ begin
create extension if not exists intarray;

raise notice 'dropping schemas'; -- {{{
drop schema if exists game cascade;
drop schema if exists api cascade;
-- }}}

raise notice 'creating schemas'; -- {{{
create schema if not exists game;
create schema if not exists api;
-- }}}

raise notice 'removing public functions'; -- {{{
drop function if exists public.c cascade;
drop function if exists public.pi_ cascade;
drop function if exists public.error cascade;
-- }}}

raise notice 'populating public functions'; -- {{{
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
raise notice 'populating types';
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
raise notice 'extending built-in functions';
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
raise notice 'populating custom functions';
do $funcs$ begin
    set search_path = game, public;

    drop function if exists normalize cascade;
    drop function if exists pos cascade;
    drop function if exists collide cascade;
    drop function if exists collisions cascade;
    drop function if exists hits cascade;
    drop function if exists predicted_hits cascade;

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

    create or replace function hits() -- {{{
    returns table (
        rock integer
        , slug integer
        , collision collision
    ) as $func$
    begin
        return query
        select
        distinct on (h.slug)
        *
        from (
            select
                c.rock
                , (array_agg(c.slug order by (c.collision).t))[1] as slug
                , (array_agg(c.collision order by (c.collision).t))[1] as collision
            from (
                select *
                from game.collisions as c
                where (c.collision).miss is null
                ) as c
            group by c.rock
            ) as h
        order by h.slug, (h.collision).t, h.rock;
    end;
    $func$ stable language plpgsql; -- }}}

    create or replace function predicted_hits( -- {{{
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
        distinct on (h.slug)
        *
        from (
            select
                c.rock
                , (array_agg(c.slug order by (c.collision).t))[1] as slug
                , (array_agg(c.collision order by (c.collision).t))[1] as collision
            from (
                    select c.rock, c.slug, c.collision
                    from game.collisions as c
                    where c.slug <> slug_id and (c.collision).miss is null
                union
                    select c.rock, c.slug, c.collision
                    from game.collisions(slug_id, slug_fired, slug_params) as c
                    where (c.collision).miss is null
                ) as c
            group by c.rock
            ) as h
        order by h.slug, (h.collision).t, h.rock;
    end;
    $func$ stable language plpgsql; -- }}}

    create or replace function predicted_hits( -- {{{
        rock_id integer
        , rock_fired timestamp with time zone
        , rock_params rock_params
    ) returns table (
        rock integer
        , slug integer
        , collision collision
    ) as $func$
    begin
        return query
        select
        distinct on (h.slug)
        *
        from (
            select
                c.rock
                , (array_agg(c.slug order by (c.collision).t))[1] as slug
                , (array_agg(c.collision order by (c.collision).t))[1] as collision
            from (
                    select c.rock, c.slug, c.collision
                    from game.collisions as c
                    where c.rock <> rock_id and (c.collision).miss is null
                union
                    select c.rock, c.slug, c.collision
                    from game.collisions(rock_id, rock_fired, rock_params) as c
                    where (c.collision).miss is null
                ) as c
            group by c.rock
            ) as h
        order by h.slug, (h.collision).t, h.rock;
    end;
    $func$ stable language plpgsql; -- }}}

end $funcs$; -- }}}

-- {{{ triggers
raise notice 'populating trigger functions';
do $funcs$ begin
    set search_path = game, public;

    drop function if exists slugs_trigger;
    drop function if exists rocks_trigger;
    drop function if exists hits_trigger;
    drop function if exists const_id;

    create or replace function slugs_trigger() -- {{{
    returns trigger as $trig$
    declare
        _rec record;
    begin
        raise notice 'trigger: %.%.% ("%")', tg_table_schema, tg_table_name, tg_name, new.name;

        with
            before as (select * from hits())
            , after as (select * from predicted_hits(new.id, new.fired, new.params))
            , diff as (select * from before except select * from after)
        delete from hits where rock in (select rock from diff);

        raise notice '    --- new ---';
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug
            from before as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    bef: %, %', _rec.rock, _rec.slug;
        end loop;
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug
            from after as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    aft: %, %', _rec.rock, _rec.slug;
        end loop;
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug
            from diff as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    new: %, %', _rec.rock, _rec.slug;
        end loop;

        -- NOTE|dutc: the insert into/update collisions must happen before
        --            the insert into hits
        if tg_op = 'INSERT' then
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
                , _ as (
                    insert into collisions
                        (rock, slug, collision)
                        select * from game.collisions(new.id, new.fired, new.params)
                )
            insert into hits (rock, slug, collision) select * from diff;
        elsif tg_op = 'UPDATE' and new <> old then
            if new.id <> old.id then raise exception 'cannot change id'; end if;
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
                , _ as (
                    update collisions set
                        collision = collide(r.fired, r.params, new.fired, new.params)
                    from rocks as r
                    where r.id = rock and new.id = slug
                )
            insert into hits (rock, slug, collision) select * from diff;
        end if;
        return new;
    end;
    $trig$ language plpgsql; -- }}}

    create or replace function rocks_trigger() -- {{{
        returns trigger as $trig$
    declare
        _rec record;
    begin
        raise notice 'trigger: %.%.% ("%")', tg_table_schema, tg_table_name, tg_name, new.name;

        delete from hits where rock = new.id;

        raise notice '    --- new ---';
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug
            from before as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    bef: %, %', _rec.rock, _rec.slug;
        end loop;
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug
            from after as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    aft: %, %', _rec.rock, _rec.slug;
        end loop;
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug
            from diff as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    new: %, %', _rec.rock, _rec.slug;
        end loop;

        -- NOTE|dutc: the insert into/update collisions must happen before
        --            the insert into hits
        if tg_op = 'INSERT' then
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
                , _ as (
                    insert into collisions
                        (rock, slug, collision)
                        select * from game.collisions(new.id, new.fired, new.params)
                )
            insert into hits (rock, slug, collision) select * from diff;
        elsif tg_op = 'UPDATE' and new <> old then
            if new.id <> old.id then raise exception 'cannot change id'; end if;
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
                , _ as (
                    update collisions set
                        collision = collide(new.fired, new.params, s.fired, s.params)
                    from slugs as s
                    where s.id = slug and new.id = rock
                )
            insert into hits (rock, slug, collision) select * from diff;
        end if;

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
    begin
        src_name := (select coalesce(source_name, name) from rocks where id = new.rock limit 1);
        src_mass := (select mass from rocks where id = new.rock limit 1);
        src_params := (select params from rocks where id = new.rock limit 1);
        count := (select count(*) from rocks where source_name = src_name or name = src_name);

        if src_mass < 1 then
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
                , (new.collision).pos.r
                , (src_params).v
            )::rock_params
        );
        return new;
    end;
    $trig$ language plpgsql; -- }}}

end $funcs$; -- }}}

-- {{{ tables
raise notice 'populating tables';
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
    drop trigger if exists hits_trigger on hits;

    drop trigger if exists slugs_id_trigger on slugs;
    drop trigger if exists rocks_id_trigger on rocks;
    drop trigger if exists collisions_id_trigger on collisions;
    drop trigger if exists hits_id_trigger on hits;

    create trigger slugs_trigger after insert or update on slugs
        for each row execute procedure slugs_trigger();
    create trigger rocks_trigger after insert or update on rocks
        for each row execute procedure rocks_trigger();
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
raise notice 'populating api views';
do $views$
begin
    set search_path = api, game, public;

    drop view if exists api.collisions;
    drop view if exists api.hits;

    create or replace view collisions as ( -- {{{
        select
            r.name as rock
            , s.name as slug
            , c.collision
        from game.collisions as c
        inner join rocks as r on (c.rock = r.id)
        inner join slugs as s on (c.slug = s.id)
    ); -- }}}

    create or replace view hits as (-- {{{
        select
            r.name as rock
            , s.name as slug
            , c.collision
        from game.hits as c
        inner join rocks as r on (c.rock = r.id)
        inner join slugs as s on (c.slug = s.id)
    ); -- }}}

end $views$; -- }}}

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

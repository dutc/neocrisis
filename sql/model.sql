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

create extension if not exists intarray;

raise notice 'dropping schemas';
drop schema if exists game cascade;

raise notice 'creating schemas';
create schema if not exists game;

drop function if exists public.c cascade;
create or replace function public.c() returns numeric
immutable language sql as 'select 299792458.0';

raise notice 'populating game models';
do $game$ begin
    set search_path = game, public;

    drop type if exists rock_params cascade;
    create type rock_params as (
        m_theta   numeric
        , b_theta numeric
        , m_phi   numeric
        , b_phi   numeric
        , r_0     numeric
        , v       numeric
    );

    drop type if exists slug_params cascade;
    create type slug_params as (
        theta numeric
        , phi numeric
        , v   numeric
    );

    drop type if exists pos cascade;
    create type pos as (
        r numeric
        , theta numeric
        , phi numeric
    );
    create or replace function round(
        v pos
        , s int
        ) returns pos as $func$
    begin
        return (round((v.r), s), round((v.theta), s), round((v.phi), s))::pos;
    end;
    $func$ language plpgsql immutable;
    create or replace function normalize(
        v pos
        ) returns pos as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi()::numeric), mod((v).phi, pi()::numeric))::pos;
    end;
    $func$ language plpgsql immutable;

    drop function if exists rock_pos cascade;
    create or replace function rock_pos(
        fired timestamp with time zone
        , params rock_params
        , t_now timestamp with time zone
        , delay boolean = false
        ) returns pos as $func$
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
    $func$ language plpgsql immutable;

    drop function if exists slug_pos cascade;
    create or replace function slug_pos(
        fired timestamp with time zone
        , params slug_params
        , t_now timestamp with time zone
        , delay boolean = false
        ) returns pos as $func$
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
    $func$ language plpgsql immutable;

    drop type if exists mtype cascade;
    create type mtype as enum ('r', 'theta', 'phi');
    drop type if exists collision cascade;
    create type collision as (
        t timestamp with time zone
        , pos pos
        , miss mtype[]
    );

    drop function if exists collision cascade;
    create or replace function collision(
        rock_fired timestamp with time zone
        , rock       rock_params
        , slug_fired timestamp with time zone
        , slug       slug_params
        ) returns collision as $func$
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

            rock_pos := rock_pos(rock_fired, rock, t);
            slug_pos := slug_pos(slug_fired, slug, t);

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
        return (t, slug_pos, m)::collision;
    end;
    $func$ language plpgsql immutable;

    drop table if exists slugs;
    create table if not exists slugs (
        id serial primary key
        , name text not null
        , fired timestamp with time zone default now()
        , params slug_params not null default (0, 0, 0)
            check ((params).theta is not null
               and (params).phi   is not null
               and (params).v     is not null)
    ) with oids;

    drop table if exists rocks;
    create table if not exists rocks (
        id serial primary key
        , name text not null
        , mass integer not null default 2
        , fired timestamp with time zone default now()
        , params rock_params not null default (0, 0, 0, 0, 0, 0)
            check ((params).m_theta is not null
               and (params).b_theta is not null
               and (params).m_phi   is not null
               and (params).b_phi   is not null
               and (params).r_0     is not null
               and (params).v       is not null)
    ) with oids;
    create index rocks_id on rocks (id);

    drop table if exists collisions;
    create table if not exists collisions (
        id serial primary key
        , rock integer not null references rocks (id) on delete cascade
        , slug integer not null references slugs (id) on delete cascade
        , collision collision
    ) with oids;
    create index collisions_rock on collisions (rock);
    create index collisions_collision on collisions (collision) where not collision is null;
    create index collisions_collision_t on collisions (((collision).t));
    create index collisions_collision_miss on collisions (((collision).miss));

    drop function if exists slug_collisions;
    create or replace function slug_collisions()
        returns trigger as $trig$
    begin
        if tg_op = 'INSERT' then
            insert into collisions (rock, slug, collision)
            select
                r.id
                , new.id
                , collision(r.fired, r.params, new.fired, new.params)
            from rocks as r;
        elsif tg_op = 'UPDATE' and new <> old then
            update collisions set
                collision = collision(r.fired, r.params, new.fired, new.params)
                from rocks as r
                where r.id = rock and new.id = slug;
        end if;
        return new;
    end;
    $trig$ language plpgsql;
    drop trigger if exists slug_fired on slugs;
    create trigger slug_fired after insert or update on slugs
        for each row execute procedure slug_collisions();

    drop function if exists rock_collisions;
    create or replace function rock_collisions()
        returns trigger as $trig$
    begin
        if tg_op = 'INSERT' then
            insert into collisions (rock, slug, collision)
            select
                new.id
                , s.id
                , collision(new.fired, new.params, s.fired, s.params)
            from slugs as s;
        elsif tg_op = 'UPDATE' and new <> old then
            update collisions set
                collision = collision(new.fired, new.params, s.fired, s.params)
                from slugs as s
                where s.id = slug and new.id = rock;
        end if;
        return new;
    end;
    $trig$ language plpgsql;
    drop trigger if exists rock_fired on rocks;
    create trigger rock_fired after insert or update on rocks
        for each row execute procedure rock_collisions();

    drop function if exists changed_collisions;
    {% if materialized %}
    create or replace function changed_collisions()
        returns trigger as $trig$
    begin
        refresh materialized view active_collisions;
        refresh materialized view real_collisions;

        refresh materialized view fragments;
        refresh materialized view fragment_collisions;
        refresh materialized view active_fragment_collisions;
        refresh materialized view real_fragment_collisions;

        return new;
    end;
    $trig$ language plpgsql;
    drop trigger if exists collisions_change on collisions;
    create trigger collisions_change after insert or update or delete on collisions
        for each statement execute procedure changed_collisions();
    {% endif %}

    drop view if exists active_collisions;
    create {{ 'materialized' if materialized else '' }} view active_collisions as (
        select
            rock
            , (array_agg(slug order by (collision).t) filter (where (collision).miss is null))[1] as slug
            , (array_agg(collision order by (collision).t) filter (where (collision).miss is null))[1] as collision
        from collisions
        group by rock
    );
    {% if materialized %}
    create index active_collisions_collision on active_collisions (collision) where not collision is null;
    {% endif %}

    drop view if exists real_collisions;
    create {{ 'materialized' if materialized else '' }} view real_collisions as (
        select
            rock
            , slug
            , collision
        from active_collisions
        where not collision is null
    );
    {% if materialized %}
    create index real_collisions_rock on real_collisions (rock);
    {% endif %}

    drop view if exists fragments;
    create {{ 'materialized' if materialized else '' }} view fragments as (
        with recursive objects (idx) as (
            select
                1
                , r.mass / 2 as mass_left
                , r.name as orig_name
                , 1 as mass
                , (c.collision).t as fired
                , 2 as m_factor
                , pi() / 4 as b_nudge
                , (c.collision).pos.r as r
                , (r.params).v as v
                , params
            from real_collisions as c
                inner join rocks as r on (c.rock = r.id)
            union all
            select
                idx + 2
                , mass_left / 2 as mass_left
                , orig_name
                , mass
                , fired
                , m_factor / 2 as m_factor
                , b_nudge * 2 as b_nudge
                , r
                , v
                , params
            from objects
            where mass_left > 1
        )
        select
            -- (row_number() over ()) * 2 + 1 as id
            null as id
            , orig_name || to_char(idx, ' FMRN') as name
            , mass
            , fired
            , (  (params).m_theta * m_factor
               , (params).b_theta + b_nudge
               , (params).m_phi * m_factor
               , (params).b_phi + b_nudge
               , r
               , v
            )::rock_params as params
        from objects
        union
        select
            -- (row_number() over ()) * 2 + 1 as id
            null as id
            , orig_name || to_char(idx + 1, ' FMRN') as name
            , mass
            , fired
            , (  (params).m_theta * m_factor
               , (params).b_theta - b_nudge
               , (params).m_phi * m_factor
               , (params).b_phi - b_nudge
               , r
               , v
            )::rock_params as params
        from objects
    );

    drop view if exists fragment_collisions;
    create {{ 'materialized' if materialized else '' }} view fragment_collisions as (
        select
            f.id as fragment
            , s.id as slug
            , collision(f.fired, f.params, s.fired, s.params) as collision
        from fragments as f, slugs as s
    );

    drop view if exists active_fragment_collisions;
    create {{ 'materialized' if materialized else '' }} view active_fragment_collisions as (
        select
            fragment
            , (array_agg(slug order by (collision).t) filter (where (collision).miss is null))[1] as slug
            , (array_agg(collision order by (collision).t) filter (where (collision).miss is null))[1] as collision
        from fragment_collisions
        group by fragment
    );

    drop view if exists real_fragment_collisions;
    create {{ 'materialized' if materialized else '' }} view real_fragment_collisions as (
        select
            fragment
            , slug
            , collision
        from active_fragment_collisions
        where not collision is null
    );

end $game$;

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

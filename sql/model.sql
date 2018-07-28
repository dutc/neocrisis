\echo 'NEO-Crisis'
\echo 'http://github.com/dutc/neocrisis'
\echo 'James Powell <james@dontusethiscode.com>'
\echo 'NOTE: This is a jinja-fied SQL file! Use jinja2-cli to process.'
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
    $func$ immutable language plpgsql;
    create or replace function normalize(
        v pos
        ) returns pos as $func$
    begin
        return ((v).r, mod((v).theta, 2*pi()::numeric), mod((v).phi, pi()::numeric))::pos;
    end;
    $func$ immutable language plpgsql;

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
    $func$ immutable language plpgsql;

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
    $func$ immutable language plpgsql;

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
            if t >= rock_fired and t >= slug_fired then
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
        else
            m := m || 'r'::mtype;
        end if;
        return (t, slug_pos, m)::collision;
    end;
    $func$ immutable language plpgsql;

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
        , mass integer not null default 4
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

    drop table if exists hits;
    create table if not exists hits (
        id serial primary key
        , rock integer unique not null references rocks (id) on delete cascade
        , slug integer references slugs (id) on delete cascade
        , collision collision
    );
    alter table rocks add column source_name text default null;
    alter table rocks add column source_rock integer default null references rocks (id) on delete cascade;
    alter table rocks add column source_hit integer default null references hits (id) on delete cascade;

    drop function if exists compute_collisions;
    create or replace function compute_collisions(
        slug_id integer
        , slug_fired timestamp with time zone
        , slug_params slug_params
    ) returns table (
        rock integer
        , slug integer
        , collision collision
    ) as $func$
    begin
        return query
            select
                r.id
                , slug_id
                , collision(r.fired, r.params, slug_fired, slug_params)
            from rocks as r;
    end;
    $func$ stable language plpgsql;
    create or replace function compute_collisions(
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
                rock_id
                , s.id
                , collision(rock_fired, rock_params, s.fired, s.params)
            from slugs as s;
    end;
    $func$ stable language plpgsql;

    drop function if exists compute_hits;
    create or replace function compute_hits() returns table (
        rock integer
        , slug integer
        , collision collision
    ) as $func$
    begin
        return query
        select distinct on (h.slug) * from (
            select
                c.rock
                , (array_agg(c.slug order by (c.collision).t))[1] as slug
                , (array_agg(c.collision order by (c.collision).t))[1] as collision
            from (select * from collisions as c where (c.collision).miss is null) as c
            group by c.rock
        ) as h order by h.slug, (h.collision).t;
    end;
    $func$ language plpgsql;

    drop function if exists predict_hits;
    create or replace function predict_hits(
        slug_id integer
        , slug_fired timestamp with time zone
        , slug_params slug_params
    ) returns table (
        rock integer
        , slug integer
        , collision collision
    ) as $func$
    begin
        return query
        select distinct on (h.slug) * from (
            select
                c.rock
                , (array_agg(c.slug order by (c.collision).t))[1] as slug
                , (array_agg(c.collision order by (c.collision).t))[1] as collision
            from (
                select c.rock, c.slug, c.collision from collisions as c where c.slug <> slug_id and (c.collision).miss is null
                union
                select c.rock, c.slug, c.collision from compute_collisions(slug_id, slug_fired, slug_params) as c where (c.collision).miss is null
            ) as c
            group by c.rock
        ) as h order by h.slug, (h.collision).t;
    end;
    $func$ stable language plpgsql;
    create or replace function predict_hits(
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
        select distinct on (h.slug) * from (
            select
                c.rock
                , (array_agg(c.slug order by (c.collision).t))[1] as slug
                , (array_agg(c.collision order by (c.collision).t))[1] as collision
            from (
                select c.rock, c.slug, c.collision from collisions as c where c.rock <> rock_id and (c.collision).miss is null
                union
                select c.rock, c.slug, c.collision from compute_collisions(rock_id, rock_fired, rock_params) as c where (c.collision).miss is null
            ) as c
            group by c.rock
        ) as h order by h.slug, (h.collision).t;
    end;
    $func$ stable language plpgsql;

    drop function if exists slug_collisions;
    create or replace function slug_collisions()
        returns trigger as $trig$
    begin
        with
            before as (select * from compute_hits())
            , after as (select * from predict_hits(new.id, new.fired, new.params))
            , diff as (select * from before except select * from after)
        delete from hits where rock in (select rock from diff);

        with
            before as (select * from compute_hits())
            , after as (select * from predict_hits(new.id, new.fired, new.params))
            , diff as (select * from after except select * from before)
        insert into hits (rock, slug, collision) select * from diff;

        if tg_op = 'INSERT' then
            insert into collisions (rock, slug, collision)
            select * from compute_collisions(new.id, new.fired, new.params);
        elsif tg_op = 'UPDATE' and new <> old then
            if new.id <> old.id then raise exception 'cannot change id'; end if;
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
        raise notice 'rocks changed %', new;
        delete from hits where rock = new.id;

        with
            before as (select * from compute_hits())
            , after as (select * from predict_hits(new.id, new.fired, new.params))
            , diff as (select * from after except select * from before)
        insert into hits (rock, slug, collision) select * from diff;

        if tg_op = 'INSERT' then
            insert into collisions (rock, slug, collision)
            select * from compute_collisions(new.id, new.fired, new.params);
        elsif tg_op = 'UPDATE' and new <> old then
            if new.id <> old.id then raise exception 'cannot change id'; end if;
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

    drop function if exists changed_hits;
    create or replace function changed_hits()
        returns trigger as $trig$
    declare
        src_name text;
        src_mass integer;
        src_params rock_params;
        count integer;
    begin
        raise notice 'hits changed %', new;
        src_name := (select coalesce(source_name, name) from rocks where id = new.rock limit 1);
        src_mass := (select mass from rocks where id = new.rock limit 1);
        src_params := (select params from rocks where id = new.rock limit 1);
        count := (select count(*) from rocks where source_name = src_name or name = src_name);
        if src_mass < 1 then
            return new;
        end if;
        insert into rocks (source_name, source_rock, source_hit, name, mass, fired, params) values (
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
    $trig$ language plpgsql;
    create trigger changed_hits after insert on hits
        for each row execute procedure changed_hits();

end $game$;

exception when others then
	get stacked diagnostics exc_message = message_text;
    get stacked diagnostics exc_context = pg_exception_context;
    get stacked diagnostics exc_detail = pg_exception_detail;
    raise exception E'\n------\n%\n%\n------\n\nCONTEXT:\n%\n', exc_message, exc_detail, exc_context;
end $$;

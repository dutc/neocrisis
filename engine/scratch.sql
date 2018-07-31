
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

select distinct on (slug) * from (
select
    c.rock
    , (array_agg(c.slug order by (c.collision).t))[1] as slug
    , (array_agg(c.collision order by (c.collision).t))[1] as collision
from (select * from collisions as c where (c.collision).miss is null) as c
group by c.rock
)as _ order by slug, (collision).t;

insert into slugs (name, params) values ( '100 @ ceres (hit)' , row(0, 0, c()));

        raise notice 'trigger: %.%.% ("%")', tg_table_schema, tg_table_name, tg_name, new.name;
        -- for _rec in select * from rocks order by name loop
        --      raise notice '   %', _rec.name;
        -- end loop;
        for _rec in
        select r.name as rock, s.name as slug from hits as h inner join rocks as r on (h.rock = r.id) inner join slugs as s on (h.slug = s.id)
        loop
            raise notice '    hit (bef): %, %', _rec.rock, _rec.slug;
        end loop;

        raise notice '    ---';
        for _rec in
        select r.name as rock, s.name as slug from hits as h inner join rocks as r on (h.rock = r.id) inner join slugs as s on (h.slug = s.id) where rock = new.id
        loop
            raise notice '    hit (old): %, %', _rec.rock, _rec.slug;
        end loop;


        raise notice '    ---';
        for _rec in
        select r.name as rock, s.name as slug from hits() as h inner join rocks as r on (h.rock = r.id) inner join slugs as s on (h.slug = s.id)
        loop
            raise notice '    hit (h()): %, %', _rec.rock, _rec.slug;
        end loop;
        raise notice '    ---';
        for _rec in
        select r.name as rock, s.name as slug from predicted_hits(new.id, new.fired, new.params) as h inner join rocks as r on (h.rock = r.id) inner join slugs as s on (h.slug = s.id)
        loop
            raise notice '    hit (p()): %, %', _rec.rock, _rec.slug;
        end loop;
        raise notice '    ---';
        for _rec in
        select r.name as rock, s.name as slug from game.collisions as c inner join rocks as r on (c.rock = r.id) inner join slugs as s on (c.slug = s.id)
        loop
            raise notice '    hit (col): %, %', _rec.rock, _rec.slug;
        end loop;
        raise notice '    ---';
        for _rec in
        select r.name as rock, h.slug from predicted_hits2(new.id, new.fired, new.params) as h inner join rocks as r on (h.rock = r.id)
        loop
            raise notice '    hit (p2 ): %, %', _rec.rock, _rec.slug;
        end loop;
        raise notice '    ---';
        for _rec in
            with
                before as (select * from hits())
                , after as (select * from predicted_hits(new.id, new.fired, new.params))
                , diff as (select * from after except select * from before)
            select r.name as rock, s.name as slug from diff as h inner join rocks as r on (h.rock = r.id) inner join slugs as s on (h.slug = s.id)
        loop
            raise notice '    hit (new): %, %', _rec.rock, _rec.slug;
        end loop;

        -- with
        --     before as (select * from hits())
        --     , after as (select * from predicted_hits(new.id, new.fired, new.params))
        --     , diff as (select * from after except select * from before)
        -- insert into hits (rock, slug, collision) select * from diff;

        -- raise notice '    ---';
        -- for _rec in
        -- select r.name as rock, s.name as slug from hits as h inner join rocks as r on (h.rock = r.id) inner join slugs as s on (h.slug = s.id)
        -- loop
        --     raise notice '    hit (aft): %, %', _rec.rock, _rec.slug;
        -- end loop;

        raise notice 'trigger: %.%.% ("%")', tg_table_schema, tg_table_name, tg_name, new.name;

        _rock text;
        _slug text;

        _rock := (select name from rocks where id = new.rock limit 1);
        _slug := (select name from slugs where id = new.slug limit 1);
        raise notice 'trigger: %.%.% ("%", "%")', tg_table_schema, tg_table_name, tg_name, _rock, _slug;





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








        delete from hits where rock = new.id;


        with
            before as (select * from hits())
            , after as (select * from predicted_hits(new.id, new.fired, new.params))
            , diff as (select * from before except select * from after)
        delete from hits where rock in (select rock from diff);

        with
            before as (select * from hits())
            , after as (select * from predicted_hits(new.id, new.fired, new.params))
            , diff as (select * from after except select * from before)
        insert into hits (rock, slug, collision) select * from diff;













        raise notice '    --- bef ---';
        for _rec in
            with
                before as (select rock, slug, collision from game.hits)
                , after as (select * from predicted_hits(new.rock, new.slug, new.collision))
                , diff as (select * from before except select * from after)
            select r.name as rock, s.name as slug
            from before as x
                inner join rocks as r on (r.id = x.rock)
                inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    bef: %, %', _rec.rock, _rec.slug;
        end loop;

        raise notice '    --- aft ---';
        for _rec in
            with
                before as (select rock, slug, collision from game.hits)
                , after as (select * from predicted_hits(new.rock, new.slug, new.collision))
                , diff as (select * from after except select * from before)
                select r.name as rock, s.name as slug
                from after as x
                    inner join rocks as r on (r.id = x.rock)
                    inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    aft: %, %', _rec.rock, _rec.slug;
        end loop;

        raise notice '    --- bef ---';
        for _rec in
            with
                before as (select rock, slug, collision from game.hits)
                , after as (
                    select *
                    from predicted_hits(new.rock, new.slug, new.collision)
                    -- where new.slug is not null and (new.collision).miss is null
                )
                , diff as (select * from before except select * from after)
                , uniq as (
                    select
                        (array_agg(d.rock order by d.rock, (d.collision).t))[1] as rock
                        , d.slug as slug
                        , (array_agg(d.collision order by d.rock, (d.collision).t))[1] as collision
                    from diff as d
                    group by d.slug
                )
                select r.name as rock, s.name as slug, x.collision
                from before as x
                    inner join rocks as r on (r.id = x.rock)
                    inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    bef: %, %, %', _rec.rock, _rec.slug, (_rec.collision).t;
        end loop;

        raise notice '    --- aft ---';
        for _rec in
            with
                before as (select rock, slug, collision from game.hits)
                , after as (
                    select
                        (array_agg(d.rock order by d.rock, (d.collision).t))[1] as rock
                        , d.slug as slug
                        , (array_agg(d.collision order by d.rock, (d.collision).t))[1] as collision
                    from (
                        select *
                        from predicted_hits(new.rock, new.slug, new.collision)
                        where new.slug is not null and (new.collision).miss is null
                    ) as d
                    group by d.slug
                )
                , diff as (select * from before except select * from after)
                , uniq as (
                    select
                        (array_agg(d.rock order by d.rock, (d.collision).t))[1] as rock
                        , d.slug as slug
                        , (array_agg(d.collision order by d.rock, (d.collision).t))[1] as collision
                    from diff as d
                    group by d.slug
                )
                select r.name as rock, s.name as slug, x.collision
                from after as x
                    inner join rocks as r on (r.id = x.rock)
                    inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    aft: %, %, %', _rec.rock, _rec.slug, (_rec.collision).t;
        end loop;

        raise notice '    --- del ---';
        for _rec in
            with
                before as (select rock, slug, collision from game.hits)
                , after as (
                    select *
                    from predicted_hits(new.rock, new.slug, new.collision)
                    where new.slug is not null and (new.collision).miss is null
                )
                , diff as (select * from before except select * from after)
                , uniq as (
                    select
                        (array_agg(d.rock order by d.rock, (d.collision).t))[1] as rock
                        , d.slug as slug
                        , (array_agg(d.collision order by d.rock, (d.collision).t))[1] as collision
                    from diff as d
                    group by d.slug
                )
                select r.name as rock, s.name as slug, x.collision
                from uniq as x
                    inner join rocks as r on (r.id = x.rock)
                    inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    del: %, %, %', _rec.rock, _rec.slug, (_rec.collision).t;
        end loop;

        raise notice '    --- ins ---';
        for _rec in
            with
                before as (select rock, slug, collision from game.hits)
                , after as (
                    select
                        (array_agg(d.rock order by d.rock, (d.collision).t))[1] as rock
                        , d.slug as slug
                        , (array_agg(d.collision order by d.rock, (d.collision).t))[1] as collision
                    from (
                        select *
                        from predicted_hits(new.rock, new.slug, new.collision)
                        where new.slug is not null and (new.collision).miss is null
                    ) as d
                    group by d.slug
                )
                , diff as (select * from after except select * from before)
                select r.name as rock, s.name as slug, x.collision
                from diff as x
                    inner join rocks as r on (r.id = x.rock)
                    inner join slugs as s on (s.id = x.slug)
        loop
            raise notice '    ins: %, %, %', _rec.rock, _rec.slug, (_rec.collision).t;
        end loop;




























    create or replace function predicted_hits( -- {{{
        rock_id integer
        , slug_id integer
        , new_collision collision
        )
    returns table (
        rock integer
        , slug integer
        , collision collision
        ) as $func$
    begin
        return query
        select
            c.rock
            , (array_agg(c.slug order by (c.collision).t))[1] as slug
            , (array_agg(c.collision order by (c.collision).t))[1] as collision
        from (
                select c.rock, c.slug, c.collision
                from game.collisions as c
            union
                select rock_id as rock, slug_id as slug, new_collision as collision
            ) as c
        group by c.rock;
    end;
    $func$ language plpgsql; -- }}}

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
    $func$ language plpgsql; -- }}}

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
    $func$ language plpgsql; -- }}}





















with
    hits as (
        select * from api.collisions as c where (c.collision).miss is null
    )
    , by_slug as (
        select
            h.*
            , count(*) over (partition by h.slug)
            , row_number() over (partition by h.slug order by (h.collision).t, h.rock, h.slug, h.id)
        from hits as h
    )
    , by_rock as (
        select
            h.*
            , count(*) over (partition by h.rock)
            , row_number() over (partition by h.rock order by (h.collision).t, h.rock, h.slug, h.id)
        from hits as h
    )
    , by_both as (
        select
            h.*
            , row_number() over (partition by h.slug order by (h.collision).t, h.rock, h.slug, h.id) = row_number() over (partition by h.rock order by (h.collision).t, h.rock, h.slug, h.id) as first
            , row_number() over (partition by h.slug order by (h.collision).t, h.rock, h.slug, h.id)
            , row_number() over (partition by h.rock order by (h.collision).t, h.rock, h.slug, h.id)
        from hits as h
        order by h.rock, h.slug
    )
    , uniqs as (
        select
            h.*
        from hits as h
            inner join by_slug as s on (h.id = s.id)
            inner join by_rock as r on (h.id = r.id)
            inner join by_both as b on (h.id = b.id)
        where (
            (s.count = 1 and r.count = 1)
            or
            (s.count = 1 and r.count > 1 and r.row_number = 1)
            or
            (r.count = 1 and s.count > 1 and s.row_number = 1)
            or
            (r.count > 1 and s.count > 1 and b.first is true)
        )
    )
select * from by_both;







-- vim: set foldmethod=marker
\echo '---- NEO-Crisis <http://github.com/dutc/neocrisis> ----'
\echo '---- James Powell <james@dontusethiscode.com>      ----'

\set VERBOSITY terse
\set ON_ERROR_STOP true

do $$
begin
    set search_path = public;
    set client_min_messages to warning;

    drop table if exists t cascade;
    drop view if exists v cascade;
    drop function if exists q();
    drop table if exists rv cascade;

    drop type if exists uniq_hits_t cascade;
    drop function if exists uniq_hits_sfunc cascade;
    drop aggregate if exists uniq_hits (integer) cascade;

    create table if not exists t (
        r integer not null
        , s integer not null
        , rn text not null
        , sn text not null
    );
    insert into t (r, rn, s, sn) values (1, 'ceres',   1, '100');
    insert into t (r, rn, s, sn) values (1, 'ceres',   7, '700');
    insert into t (r, rn, s, sn) values (2, 'eros',    4, '400');
    insert into t (r, rn, s, sn) values (3, 'tycho',   5, '500');
    insert into t (r, rn, s, sn) values (3, 'tycho',   6, '600');
    insert into t (r, rn, s, sn) values (4, 'ceres I', 7, '700');
    insert into t (r, rn, s, sn) values (4, 'ceres I', 1, '100');

    create or replace view v as (
        select *  from t order by random()
    );

    create type uniq_hits_t as (
        uniq boolean
        , rocks integer[]
        , slugs integer[]
    );

    create or replace function uniq_hits_sfunc(
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

    $func$ immutable language plpgsql;
    create aggregate uniq_hits (integer, integer) (
        sfunc = uniq_hits_sfunc
        , stype = uniq_hits_t
        , initcond = '(,{},{})'
    );

    create or replace function q()
    returns table (
        r integer
        , s integer
        , rn text
        , sn text
    ) as $func$
    begin
        return query
        select x.r, x.s, x.rn, x.sn
        from (
            select
                v.*
                , uniq_hits(v.r, v.s) over win as uniq
            from v
            window win as (
                partition by 1
                order by v.r, v.s
                rows between unbounded preceding and current row
            )
        ) as x
        where (x.uniq).uniq is true;
    end;
    $func$ language plpgsql;

    create table if not exists rv (like t);

end $$;

begin;
    \pset footer off

    \echo '-- data --'
    select * from v;

    \echo '-- query --'
    select * from q();

    \echo '-- rv --'
    insert into rv select r, s from q();
    select * from rv;
end;

do $$
declare
begin
    assert array_length(array(select 1 from rv), 1) = 4, 'too many/few rows';
    assert array_length(array(select distinct r from rv), 1) = 4, 'repeated r';
    assert array_length(array(select distinct s from rv), 1) = 4, 'repeated s';
end $$;

begin;
    drop table if exists t cascade;
    drop view if exists v cascade;
    drop function if exists q() cascade;
    drop table if exists rv cascade;
end;


\echo 'NEO-Crisis'
\echo 'http://github.com/dutc/neocrisis'
\echo 'James Powell <james@dontusethiscode.com>'
\set VERBOSITY terse
\set ON_ERROR_STOP true

do $test$
declare
begin
    set search_path = api, game, public;

    /* select * from hits; */
end $test$;

begin;
    set search_path = api, game, public;

    select rock, slug from hits;
end;

/* begin; */
/*     set search_path = game, public; */

/*     \echo 'before insert - @ luna' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'luna'; */

/*     insert into slugs (name, params) values ( '800 @ luna (hit)' , row(3, 3, c())); */

/*     \echo 'after insert - @ luna' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'luna'; */
/* end; */

/* begin; */
/*     \echo 'before insert - @ ganymede' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'ganymede'; */

/*     create temporary table id as */
/*         with id as ( */
/*             insert into slugs (name, params) values ( '900 @ ganymede (miss)' , row(pi()/4, pi()/4, 0)) returning id */
/*         ) select * from id; */

/*     \echo 'after insert - @ ganymede' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'ganymede'; */

/*     update slugs set name = '900 @ ganymede (hit)', params.v = c() where id in (select * from id); */

/*     \echo 'after update - @ ganymede' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'ganymede'; */

/*     delete from slugs where id in (select * from id); */

/*     \echo 'after delete - @ ganymede' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'ganymede'; */

/*     \echo 'before update - @ ceres (miss - late)' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'ceres'; */
/*     select r.name as rock, s.name as slug */
/*     from rocks as r */
/*         inner join hits as h on (h.id = r.source_hit) */
/*         inner join slugs as s on (h.slug = s.id) */
/*     where r.source_hit is not null */
/*     and r.source_name = 'ceres'; */

/*     /1* update slugs set params.v = 100 * c(), name = '700 @ ceres (hit!)' where name = '700 @ ceres (miss - late)'; *1/ */

/*     \echo 'after update - @ ceres (miss - late)' */
/*     select r.name as rock, s.name as slug, h.collision */
/*     from hits as h */
/*         inner join rocks as r on (r.id = h.rock) */
/*         inner join slugs as s on (s.id = h.slug) */
/*     where r.name = 'ceres'; */
/*     select r.name as rock, s.name as slug */
/*     from rocks as r */
/*         inner join hits as h on (h.id = r.source_hit) */
/*         inner join slugs as s on (h.slug = s.id) */
/*     where r.source_hit is not null */
/*     and r.source_name = 'ceres'; */

/*     create view hits2 as ( */
/*         select r.name as rock, s.name as slug, h.collision */
/*         from hits as h */
/*             inner join rocks as r on (r.id = h.rock) */
/*             inner join slugs as s on (s.id = h.slug) */
/*     ); */
/* end; */

-- Portfolio 2 - runs every workload query under EXPLAIN (ANALYZE, BUFFERS).
-- ANALYZE really executes the query and reports actual rows and timings;
-- BUFFERS shows how many 8 kB pages came from cache (hit) or disk (read).
\set EXPLAIN 'EXPLAIN (ANALYZE, BUFFERS)'
\ir 02_queries.sql

-- 47-contest_parse_rejects.sql — the QSO lines the parser could not read
--
-- A VIEW OVER BRONZE, NOT A TABLE (Judge, 2026-09-23). Until then this was a side
-- table: the ingester skipped a line it could not read and wrote a capped sample of
-- it here, with the uncapped count in ingest_log.skipped_rows. Now bronze takes every
-- QSO: line, and an unreadable one lands there with parse_error set and raw_line
-- holding its content. Nothing is sampled, nothing is capped, and there is one place
-- to look.
--
-- Why it matters is unchanged: three real parser defects -- stopping at the first
-- END-OF-LOG, cutting compound callsigns at the slash, refusing 7Q1 -- each dropped
-- QSOs silently until skips were kept. What shows up here should be genuine junk in
-- the source logs. A jump after an ingester change is the regression signal.
--
-- reason is derived from the parser's error prefix, a fixed small set, so the
-- grouping below stays useful; detail is the full error with the offending value.
--
-- MIGRATION: on a host that still has the old table, drop it once before applying:
--   DROP TABLE contest.parse_rejects

CREATE OR REPLACE VIEW contest.parse_rejects AS
SELECT
    file_path,
    line_no,
    multiIf(startsWith(parse_error, 'bad freq'),      'bad frequency',
            startsWith(parse_error, 'bad timestamp'), 'bad timestamp',
            startsWith(parse_error, 'too few fields'), 'too few fields',
            position(parse_error, 'no their_call') > 0, 'no worked station',
            'other')                                   AS reason,
    parse_error                                        AS detail,
    raw_line,
    contest,
    source,
    declared_year
FROM contest.bronze
WHERE parse_error != '';

-- The review query: which reasons, and is any one of them concentrated somewhere?
-- A reason spread thinly across many files is bad source data. A reason concentrated
-- in one contest or one publisher is a parser assumption that does not hold there.
CREATE OR REPLACE VIEW contest.v_parse_rejects_by_reason AS
SELECT
    reason,
    contest,
    count()                AS lines,
    uniqExact(file_path)   AS files,
    any(raw_line)          AS sample_line,
    any(detail)            AS sample_detail
FROM contest.parse_rejects
GROUP BY reason, contest
ORDER BY lines DESC;

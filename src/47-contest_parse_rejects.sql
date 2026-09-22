-- 47-contest_parse_rejects.sql — every QSO line the parser could not read
--
-- WHY THIS EXISTS
--
-- contest-ingest counted skipped lines and threw them away. A run over 823,467
-- files printed one aggregate "QSOs Skipped: N" to stdout and kept nothing: not
-- which file, not which line, not why. So a skip was invisible unless someone
-- happened to be watching the terminal, and the only way to find out what had been
-- dropped was to re-derive it from the archive afterwards.
--
-- That is how three real defects hid for as long as they did. The parser stopped at
-- the first END-OF-LOG and dropped 179 whole logs; it kept everything before the
-- first "/" and dropped 1,607,413 compound callsigns; and it required a trailing
-- letter, which discarded every QSO with 7Q1 -- a licensed Malawi station -- in it.
-- None of those announced themselves. Each file parsed, reported no error, and
-- quietly contributed fewer QSOs than the archive held.
--
-- A skip is now a record, not a counter. The rule: if the parser cannot read a
-- line, it skips it AND writes it here for review.
--
-- WHAT BELONGS HERE VS IN contest.quarantine
--
--   quarantine     a QSO that PARSED and then failed a rule (dated outside its
--                  declared year). It is a well-formed row being held.
--   parse_rejects  a line that did not parse at all. There is no QSO to hold, so
--                  the raw text is kept instead.
--
-- Both are "held for review". Neither is a deletion.
--
-- PER-FILE CAP. A systematically mis-parsed contest could otherwise write tens of
-- millions of rows and turn a diagnostic into an outage. The ingester caps how many
-- lines it records per file and records the true total in
-- contest.ingest_log.skipped_rows, so the count is never lost even when the samples
-- are. A file at its cap is itself the signal: that is not a bad line, it is a bad
-- assumption about the file.
--
-- REASON IS A CATEGORY, DETAIL IS THE TEXT. The parser's error carries the offending
-- value -- bad freq "notafreq": strconv.ParseFloat: parsing "notafreq" -- so using it
-- directly as reason would mint a new distinct string per bad value and make
-- LowCardinality actively worse than String, while making the grouping view below
-- useless. reason is therefore a fixed small set and detail holds the full error.
--
-- EXPECTED TO BE SMALL AND TO STAY SMALL. After the four parser fixes, worked-station
-- resolution measured 99.9703% over a 15,198,848-field sample. What lands here should
-- be genuine junk in the source logs. A sudden increase after an ingester change is
-- the regression signal this table exists to provide.

CREATE TABLE IF NOT EXISTS contest.parse_rejects (
    file_path    String                  COMMENT 'Relative path: cq-ww/2005cw/k1abc.log',
    line_no      UInt32                  COMMENT 'Line number within the file, 1-based',
    contest      LowCardinality(String)  COMMENT 'Contest ID from the directory, e.g. CQ-WW-CW',
    reason       LowCardinality(String)  COMMENT 'Category: bad frequency, bad timestamp, no their_call, ...',
    detail       String                  COMMENT 'The parser error in full, including the offending value',
    raw_line     String                  COMMENT 'The line as it appeared, truncated',
    hostname     LowCardinality(String)  COMMENT 'Host that performed the load',
    ingested_at  DateTime DEFAULT now()  COMMENT 'When the reject was recorded (UTC)'
) ENGINE = ReplacingMergeTree(ingested_at)
ORDER BY (file_path, line_no)
SETTINGS index_granularity = 8192
COMMENT 'Contest QSO lines the parser could not read — skipped and kept for review';

-- The review query: which reasons, and is any one of them concentrated somewhere?
-- A reason spread thinly across many files is bad source data. A reason concentrated
-- in one contest or one publisher is a parser assumption that does not hold there.
CREATE OR REPLACE VIEW contest.v_parse_rejects_by_reason AS
SELECT
    reason,
    contest,
    count()                AS lines,
    uniqExact(file_path)   AS files,
    min(ingested_at)       AS first_seen,
    max(ingested_at)       AS last_seen,
    any(raw_line)          AS sample_line,
    any(detail)            AS sample_detail
FROM contest.parse_rejects
GROUP BY reason, contest
ORDER BY lines DESC;

-- 37-contest_quarantine.sql — Holding table for contest QSOs that fail date validation
--
-- WHY THIS EXISTS
--
-- Upstream contest sites do not always publish what their directory name claims.
-- cqwpxrtty.com/publiclogs/2018/ serves 3,146 logs that are actually 2017
-- submissions: fetch 2017/aa7v.log and 2018/aa7v.log and you get byte-identical
-- 2017-02-11/12 QSOs. contest-download mirrors the site faithfully, so those QSOs
-- land twice under two source keys, and contest.bronze is a plain MergeTree that
-- collapses nothing. That is 533,506 duplicated rows from a single event.
--
-- Separately, a small number of operator-submitted logs carry corrupted year
-- fields — 2007-10-27 recorded as 2027-10-07, 2008-11-29 as 2088-11-29 — plus a
-- handful of unparseable dates that default to the Unix epoch.
--
-- Both classes are caught by one rule at ingest: a QSO's timestamp must fall
-- inside the year its source directory declares, with two days of slack at each
-- boundary. The slack is not decoration — ARRL RTTY Roundup runs the first
-- weekend of January and arrl-rtty/2021 legitimately holds 190,174 QSOs dated
-- 2021-01-02.
--
-- The rule deliberately does NOT know when any contest was held. Contest dates,
-- log publication dates, and the date a file appears on a website are three
-- different things, and a hardcoded calendar of 15 series across 20 years would
-- be one wrong entry away from silently rejecting a good year.
--
-- NOTHING IS DELETED. Rows land here instead of contest.bronze so the corpus
-- stays clean while the data stays recoverable. A row misjudged by the rule can
-- be replayed; a row dropped at ingest cannot. Re-admit with:
--
--   INSERT INTO contest.bronze SELECT parseDateTimeBestEffort(timestamp),
--     frequency, band, mode, call_1,
--     call_2, rst_sent, exch_sent, rst_rcvd, exch_rcvd, contest, source
--   FROM contest.quarantine WHERE source = '...';
--
-- WHY timestamp IS A STRING
--
-- ClickHouse DateTime spans 1970-01-01 to 2106-02-07. Eight rows already in
-- contest.bronze fall outside that window, and a corrupted Cabrillo year can
-- land anywhere. Storing the suspect value in DateTime would clamp or wrap the
-- exact thing this table exists to preserve, which would make the evidence
-- agree with the defect. Text holds whatever was parsed, intact.
--
-- Replay converts on the way out:
--   parseDateTimeBestEffortOrNull(timestamp)
--
-- Expected population on first full replay: ~536,022 rows of 234M (0.229%).

CREATE DATABASE IF NOT EXISTS contest;

CREATE TABLE IF NOT EXISTS contest.quarantine (
    timestamp     String                COMMENT 'QSO timestamp as parsed, RFC3339 text - NOT DateTime, see note',
    frequency     UInt32                  COMMENT 'Frequency kHz',
    band          Int32                   COMMENT 'ADIF band ID',
    mode          LowCardinality(String)  COMMENT 'CW, PH, RY, DG, FM',
    call_1        String                  COMMENT 'Logging station callsign',
    call_2        String                  COMMENT 'Worked station callsign',
    rst_sent      String                  COMMENT 'RST/signal report sent',
    exch_sent     String                  COMMENT 'Sent exchange (raw, space-joined)',
    rst_rcvd      String                  COMMENT 'RST/signal report received',
    exch_rcvd     String                  COMMENT 'Received exchange (raw, space-joined)',
    contest       LowCardinality(String)  COMMENT 'Contest ID from CONTEST header',
    source        LowCardinality(String)  COMMENT 'Source key (cq-wpx-rtty/2018)',
    file_path     String                  COMMENT 'Log file this QSO came from, for replay',
    declared_year UInt16                  COMMENT 'Year the source directory claims',
    reason        LowCardinality(String)  COMMENT 'Why it was held back (off-declared-year)',
    quarantined_at DateTime DEFAULT now() COMMENT 'When ingest set it aside'
) ENGINE = MergeTree()
-- Deliberately NOT partitioned by toYYYYMM(timestamp): these timestamps are the
-- suspect value. Partitioning on them would scatter 548k rows across partitions
-- from 1970 to 2088. The table is small; one partition is correct.
PARTITION BY tuple()
ORDER BY (source, timestamp, call_1, call_2)
SETTINGS index_granularity = 8192;

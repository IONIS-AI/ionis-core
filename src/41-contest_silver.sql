-- =============================================================================
-- File.........: 41-contest_silver.sql
-- Description..: contest.bronze with exact duplicate rows removed
-- Engine.......: MergeTree
-- Population...: scripts/populate_contest_silver.sh, after every contest reload
--
-- TWO SOURCES OF TRUTH, AND THIS IS NEITHER OF THEM (Judge, 2026-09-22):
--
--   archive side   /mnt/contest-logs/_v2   what the publishers actually served
--   data side      contest.bronze          a faithful ingest of those files
--
-- Everything else, this table included, is derived and rebuildable. That split is
-- why bronze is NOT cleansed: a publisher serving a malformed file is a fact about
-- the publisher, and bronze is where facts about sources live. Clean at ingest and
-- the evidence is gone.
--
-- THE ONE RULE: a duplicate is an EXACT match on every column.
--
-- Judge's definition, and it is exactly right for contest data. Hams work dupes on
-- purpose -- if the first exchange was busted it is faster to work the station again
-- than argue about it -- so a repeat contact is real data and often the interesting
-- kind: same two stations, same band and mode, DIFFERENT TIME. Those differ in
-- `timestamp`, so they are not exact matches and this table keeps every one.
--
-- What it removes is rows identical in all twelve columns, which cannot arise from
-- operating. Measured on the 2026-09-22 reload: 161,369 rows, 0.042% of 384,429,893.
--
-- WHERE THEY COME FROM. Not from re-reading a file -- contest.ingest_log is keyed per
-- file path and a --full run truncates it, so 823,467 files in means 823,467 read
-- once. They come from duplicated CONTENT in the corpus itself. The case that
-- exposed it: iaru-hf/2025/r0hq.log is two Cabrillo logs concatenated, carrying
-- CALLSIGN: R4HQ and CALLSIGN: R9HQ one after the other, so R4HQ's 3,272 QSOs also
-- exist in r4hq.log. `source` is the DIRECTORY, not the filename, so both copies
-- carry source='iaru-hf/2025' and match on all twelve columns.
--
-- WHY IT MATTERS MORE THAN 0.042% SUGGESTS. The error is concentrated, not smeared.
-- 168 stations in IARU-HF 2025 alone, and they are HQ multi-op stations with
-- thousands of QSOs each -- R4HQ 3.26K doubled, 8N2HQ 3.23K, B1HQ 1.42K. Every grid
-- pair those stations contributed to carries 2x spot_count in contest.signatures,
-- and spot_count feeds reliability. A path is not 0.04% wrong, it is twice wrong.
--
-- THIS LAYER HAS A CONSUMER, which is the test wspr.silver failed. That table was
-- documented for months, written by an unpackaged hand-run job, read by nothing, and
-- was dropped on 2026-09-22 holding zero rows. This one is read by
-- contest.signatures and exists to apply one stated rule. If that stops being true,
-- retire it the same way.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS contest;

CREATE TABLE IF NOT EXISTS contest.silver
(
    timestamp  DateTime                COMMENT 'QSO timestamp UTC',
    frequency  UInt32                  COMMENT 'Frequency kHz',
    band       Int32                   COMMENT 'ADIF band ID',
    mode       LowCardinality(String)  COMMENT 'CW, PH, RY, DG, FM',
    call_1     String                  COMMENT 'Logging station callsign',
    call_2     String                  COMMENT 'Worked station callsign',
    rst_sent   String                  COMMENT 'RST/signal report sent',
    exch_sent  String                  COMMENT 'Sent exchange (raw, space-joined)',
    rst_rcvd   String                  COMMENT 'RST/signal report received',
    exch_rcvd  String                  COMMENT 'Received exchange (raw, space-joined)',
    contest    LowCardinality(String)  COMMENT 'Canonical label, from the source directory',
    source     LowCardinality(String)  COMMENT 'Source key (cq-ww/2005cw) - the DIRECTORY, not the file'
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, band, call_1, call_2)
SETTINGS index_granularity = 8192;

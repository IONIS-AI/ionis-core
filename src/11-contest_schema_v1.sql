-- 11-contest_schema_v1.sql — contest.bronze: every QSO: line upstream served
--
-- BRONZE GETS EVERYTHING (Judge, 2026-09-23). Ingest is packaging. The archive at
-- /mnt/contest-logs/_v2 is upstream's tarball -- the same bytes their sites serve,
-- kept local so they need not be downloaded again -- and it is never edited. Every
-- QSO: line in it becomes exactly one row here, good, bad or otherwise:
--
--   archive QSO: lines == count() FROM contest.bronze          (verify_contest_ingest.sh)
--
-- Nothing is skipped and nothing is held in a side table. What it took to get a line
-- in is recorded on the row, the way a package carries its patches:
--
--   raw_line     the line exactly as the file holds it. The evidence: every typed
--                column below can be re-derived from it.
--   patches      named normalisations applied to read the line -- glued-qso-tag,
--                glued-mode, band-designator -- and facts found on the way:
--                off-declared-year (dated outside the directory's year, stored as
--                sent), timestamp-unrepresentable (a year DateTime cannot hold, so
--                timestamp is NULL), parse-failed.
--   parse_error  non-empty when no patch could make the line read. The typed columns
--                are then NULL or empty and raw_line carries the content.
--
-- NOT CORRECTED. A patch makes a line READ; it never changes what it says. An
-- off-year QSO keeps the date its log gave it. Choosing what to do with it, and
-- removing duplicates -- the same QSO in both stations' logs, a log a publisher
-- serves under two years -- is silver's job.
--
-- GRID LOCATORS (Watson, 2026-09-26). bronze stores QSO lines only; a log's GRID-LOCATOR:
-- header is read by contest-ingest solely for the optional -enrich write to
-- wspr.callsign_grid, and there it accepts 4- or 6-character grids after upper-casing
-- (so case is never a reason to drop one). An 8- or 10-character header grid is not
-- accepted. Header-only, not per-QSO data, and not in bronze -- recorded so it is known.
--
-- Physical order is archive order: (source, file_path, line_no) reads a log back the
-- way the file holds it. Partitioned by the year the directory declares, so a year
-- can be reloaded or dropped on its own.

CREATE DATABASE IF NOT EXISTS contest;

CREATE TABLE IF NOT EXISTS contest.bronze (
    timestamp     Nullable(DateTime)      COMMENT 'QSO timestamp UTC as sent; NULL when unreadable or outside DateTime range (see patches)',
    frequency     Nullable(UInt32)        COMMENT 'Frequency kHz; band designators (2.3G) map to the band lower edge; NULL when unreadable',
    band          Nullable(Int32)         COMMENT 'ADIF band ID; NULL when unreadable',
    mode          LowCardinality(String)  COMMENT 'CW, PH, RY, DG, FM; empty when unreadable',
    call_1        String                  COMMENT 'Logging station callsign',
    call_2        String                  COMMENT 'Worked station callsign',
    rst_sent      String                  COMMENT 'RST/signal report sent',
    exch_sent     String                  COMMENT 'Sent exchange (raw, space-joined)',
    rst_rcvd      String                  COMMENT 'RST/signal report received',
    exch_rcvd     String                  COMMENT 'Received exchange (raw, space-joined)',
    contest       LowCardinality(String)  COMMENT 'Canonical label, from the source directory',
    source        LowCardinality(String)  COMMENT 'Source key (cq-ww/2005cw) - the DIRECTORY',
    file_path     String                  COMMENT 'Log file relative to the archive root: cq-ww/2005cw/k1abc.log',
    line_no       UInt32                  COMMENT 'Line number within the file, 1-based, counting every line',
    declared_year UInt16                  COMMENT 'Year the source directory claims; 0 when it names none',
    raw_line      String                  COMMENT 'The line exactly as the file holds it',
    patches       Array(LowCardinality(String)) COMMENT 'Normalisations applied and facts found; empty when the line read as-is',
    parse_error   String                  COMMENT 'Parser error when the line could not be read; empty otherwise'
) ENGINE = MergeTree()
PARTITION BY declared_year
ORDER BY (source, file_path, line_no)
SETTINGS index_granularity = 8192;

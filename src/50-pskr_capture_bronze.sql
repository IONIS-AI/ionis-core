-- 50-pskr_capture_bronze.sql — the PSK Reporter feed as pskr-capture recorded it
--
-- SOURCE. pskr-capture (ionis-apps >= 4.7.0) writes $IONIS_PSKR_DATA_DIR/capture/
-- YYYY/MM/DD/capture-HHMMSS.jsonl.gz: one line per MQTT message with the payload's exact
-- bytes, the receive time and the topic, plus event lines (connected, subscribed,
-- connection_lost, reconnecting, dropped, stopped). Nothing is filtered. It replaced
-- pskr-collector on 2026-09-26, which filtered and rewrote the feed (IONIS-AI/ionis-apps#37);
-- pskr.bronze holds that older, filtered capture and is left as it is.
--
-- WHAT THE ARCHIVE CAN AND CANNOT PROVE. PSKR has no upstream archive: what the feed
-- sent is gone once it passes. So the audit proves CAPTURE == BRONZE (every line of every
-- capture file is a row here). Completeness of the capture against the live feed cannot
-- be proven after the fact. What can be measured is loss: PSK Reporter numbers every
-- message (sq), so missing sequence numbers, connection events and dropped counts are
-- reported by verify_pskr_capture_ingest.sh as coverage -- never folded into a zero.
--
-- BRONZE GETS EVERYTHING (DATA-DICTIONARY §0). One row per file line, message or
-- event. Every payload field has a column, named as PSK Reporter names it; a field the
-- feed adds later lands in `extra` rather than being dropped. band_adif is DERIVED from
-- f (the ADIF band id), named as such. A line that cannot be read -- e.g. the cut-off last
-- line of a crashed hour -- is kept with raw_line and parse_error.

CREATE DATABASE IF NOT EXISTS pskr;

CREATE TABLE IF NOT EXISTS pskr.capture_bronze (
    file_path     LowCardinality(String) COMMENT 'Relative to the capture root: YYYY/MM/DD/capture-HHMMSS.jsonl.gz[.partial]',
    line_no       UInt32                 COMMENT 'Line number in the file, 1-based',
    rx            Nullable(DateTime64(9, 'UTC')) COMMENT 'When pskr-capture received the message (its clock)',
    topic         String                 COMMENT 'MQTT topic the message arrived on; empty for event lines',
    event         LowCardinality(String) COMMENT 'Event line kind (connected, connection_lost, dropped, ...); empty for messages',
    event_detail  String                 COMMENT 'Event detail as written',
    event_count   Nullable(UInt64)       COMMENT 'For dropped: how many messages the full buffer lost',
    sq            Nullable(UInt64)       COMMENT 'PSK Reporter sequence number',
    f             Nullable(UInt64)       COMMENT 'Frequency, Hz',
    md            LowCardinality(String) COMMENT 'Mode',
    rp            Nullable(Int16)        COMMENT 'Report (SNR dB)',
    t             Nullable(DateTime('UTC')) COMMENT 't: time of the report (epoch seconds as sent)',
    t_tx          Nullable(DateTime('UTC')) COMMENT 't_tx: time of the transmission',
    sc            String                 COMMENT 'Sender callsign',
    sl            String                 COMMENT 'Sender locator, as sent (4-10 characters, not validated)',
    rc            String                 COMMENT 'Receiver callsign',
    rl            String                 COMMENT 'Receiver locator, as sent',
    sa            Nullable(UInt16)       COMMENT 'Sender ADIF DXCC entity',
    ra            Nullable(UInt16)       COMMENT 'Receiver ADIF DXCC entity',
    b             LowCardinality(String) COMMENT 'Band label as sent (e.g. 20m)',
    extra         Map(String, String)    COMMENT 'Any payload field not listed above, JSON-encoded value -- a new feed field is kept, not dropped',
    band_adif     Nullable(Int32)        COMMENT 'DERIVED: ADIF band id from f (bands.GetBand); not a feed field',
    payload_text  String                 COMMENT 'Payload kept as text when it was not compact JSON (see pskr-capture)',
    raw_line      String                 COMMENT 'The line as the file holds it -- set only when parse_error is',
    parse_error   String                 COMMENT 'Why the line could not be read; empty when it was',
    ingested_at   DateTime DEFAULT now()
) ENGINE = MergeTree
PARTITION BY toYYYYMM(ifNull(rx, toDateTime64(0, 9, 'UTC')))
ORDER BY (file_path, line_no)
COMMENT 'PSK Reporter MQTT feed exactly as pskr-capture recorded it (2026-09-26-). Every line of every capture file.';

-- Watermark for pskr-capture-ingest: one row per capture file loaded. Same shape as the
-- other *.ingest_log tables with skipped_rows (internal/watermark). The older
-- pskr.ingest_log belongs to pskr-ingest and the filtered pskr.bronze.
CREATE TABLE IF NOT EXISTS pskr.capture_ingest_log (
    file_path    String                  COMMENT 'Relative to the capture root',
    file_size    UInt64                  COMMENT 'File size in bytes at load time',
    row_count    UInt64                  COMMENT 'Rows loaded (= lines in the file)',
    skipped_rows UInt64 DEFAULT 0        COMMENT 'Always 0: an unreadable line is a row with parse_error',
    loaded_at    DateTime DEFAULT now()  COMMENT 'When loaded (UTC)',
    elapsed_ms   UInt32                  COMMENT 'Processing time ms',
    hostname     LowCardinality(String)  COMMENT 'Host that performed the load'
) ENGINE = ReplacingMergeTree(loaded_at)
ORDER BY (file_path)
SETTINGS index_granularity = 256
COMMENT 'pskr-capture-ingest watermark: tracks loaded capture files';

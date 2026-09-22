# IONIS Data Dictionary

**Every table in the lab's ClickHouse, what writes it, what reads it, and how it is derived.**

This file is authoritative. If another document disagrees with it, that document is wrong —
and the reason this file exists is that several of them were. An audit on 2026-09-22 found a
table documented as holding 4.4 billion rows that held none, a view that silently changes what
"all WSPR spots" means, and five tables in the live database with no DDL in any repository.
A downstream product is only as honest as the lineage behind it.

Verified against `10.60.1.1:9000` on 2026-09-22. Row counts move; lineage does not.

## How to read this

- **Source** — where the bytes originate outside the lab.
- **Written by** — the one thing that inserts. If two things write a table, that is a finding.
- **Read by** — what consumes it. A table nothing reads is a candidate for retirement.
- **DDL** — the file in `ionis-core/src/` that creates it. `src/*.sql` is globbed by
  `Makefile` and by `ionis-core.spec`, so **every file in that directory is applied**. Deleting a
  table without deleting its DDL means the next schema apply brings it back.

---

## 0. Two sources of truth, and the layers between them

**Judge, 2026-09-22.** This is the default shape for every table unless a specific use case
does not fit it.

| | |
|---|---|
| **archive side SOT** | the files on disk — `/mnt/contest-logs/_v2`, `/mnt/wspr-data`, `/mnt/pskr-data`, … What the upstream actually served. |
| **data side SOT** | `*.bronze` — a faithful ingest of those files. |

Everything else is derived and rebuildable:

- **bronze** — faithful. Not cleansed, not corrected, not deduplicated. A publisher serving a
  malformed file is a *fact about the publisher*, and bronze is where facts about sources live.
  Clean at ingest and the evidence is gone.
- **silver** — cleansed, by one stated rule per table. The rule is written in that table's DDL,
  not inferred from the code that builds it.
- **gold** — the final curation, and whatever "curation" means for that table. The published
  artifacts come from here.

**Each layer must have a stated job and a reader.** That is not decoration, it is the test
`wspr.silver` failed: documented for months, written by an unpackaged hand-run CUDA job, read by
nothing, found holding zero rows and dropped on 2026-09-22 (§5c). The pattern was never the
problem — a layer with no rule and no consumer was. A silver table that cannot say what it
removes, or name what reads it, should be retired rather than explained.

### Where the current tables sit

| Source | bronze | silver | gold |
|---|---|---|---|
| contest | `contest.bronze` | `contest.silver` — exact all-column duplicates removed | `contest.signatures` |
| WSPR | `wspr.bronze` | — | `wspr.signatures_v*`, `wspr.gold_*` |
| RBN | `rbn.bronze` | — | `rbn.signatures` |
| PSKR | `pskr.bronze` | — | `pskr.signatures` |
| solar | `solar.bronze`, `solar.dscovr` | — | `solar.iri_lookup` |

Only contest has a silver layer today, because contest is the only source so far with a defect
that needs one. **Open question, not yet answered:** whether the `*.signatures` tables are
already playing the silver role for the others — they filter, they do not merely aggregate — in
which case the gold column above is misnamed rather than the silver column being empty.

## 1. Bronze — raw ingest, one row per observation

Nothing derives these. They are what the upstream gave us, normalised only in field layout.

| Table | Rows | Source | Written by | DDL |
|---|---:|---|---|---|
| `wspr.bronze` | 12.68B | wsprnet.org monthly CSV archives + `wspr.live` stream | `wspr-turbo`, `wspr-shredder`, `wspr-ingest`, `wspr-parquet-*`, `wspr-backfill` (all `-ch-table bronze`) | `01-wspr_schema_v2.sql` |
| `pskr.bronze` | 7.10B | PSK Reporter MQTT live feed | `pskr-ingest` | `22-pskr_schema_v1.sql` |
| `rbn.bronze` | 2.37B | Reverse Beacon Network daily ZIPs | `rbn-ingest` | `10-rbn_schema_v1.sql` |
| `contest.bronze` | 234.28M | Cabrillo logs (CQ WW, CQ WPX, ARRL, …) | `contest-ingest` | `11-contest_schema_v1.sql` |
| `solar.bronze` | 78.33K | NOAA SWPC daily indices (SFI, Kp, Ap, sunspot) | `solar-ingest` (daily), `solar-backfill` (history), `solar-history-load.sh` | `02-solar_indices.sql` |
| `solar.dscovr` | 231.89K | NOAA SWPC RTSW (DSCOVR/ACE L1 solar wind, 1-minute) | `dscovr-ingest` | `33-solar_dscovr.sql` |

**Coverage as measured 2026-09-22:**

| Table | Earliest | Latest | Note |
|---|---|---|---|
| `wspr.bronze` | 2008-03-11 | 2026-09-21 | see §5 — the first 10 minutes of each hour are incomplete for 2023-10 … 2025-04 |
| `pskr.bronze` | 1970-01-01 | 2026-09-22 | 74 rows at epoch zero — malformed upstream timestamps, not a gap |
| `rbn.bronze` | 2009-02-21 | 2026-09-20 | |
| `contest.bronze` | 1970-01-01 | **2088-11-30** | 86 rows outside any plausible window. Real span is 1996-11-25 … 2025-08-31 |
| `solar.bronze` | 2000-01-01 | 2026-09-21 | |
| `solar.dscovr` | | 2026-09-22 05:25 | live |

Two of those windows are wrong on their face. A `max(timestamp)` of 2088 is a parser accepting
a year it should reject, and any query that does `WHERE timestamp > X` without an upper bound
inherits it. Tracked with the contest reload.

## 2. Signatures — physics features joined to solar state

One row per propagation observation, enriched with the solar conditions at that moment. This is
the layer models actually train on. Each is built by a populate script that joins a bronze table
to `solar.bronze`; none of them use an intermediate layer.

| Table | Rows | Derived from | Built by | DDL |
|---|---:|---|---|---|
| `wspr.signatures_v1` | 93.62M | `wspr.bronze` + `solar.bronze` + `wspr.callsign_grid` | `populate_signatures.sh` | `12-signatures_v1.sql` |
| `wspr.signatures_v2_terrestrial` | 93.60M | `wspr.signatures_v1` minus balloons (`wspr.balloon_callsigns_v2`) | `populate_signatures_v2_terrestrial.sh` | `20-signatures_v2_terrestrial.sql` |
| `rbn.signatures` | 67.35M | `rbn.bronze` + `solar.bronze` | `populate_rbn_signatures.sh` | `24-rbn_signatures.sql` |
| `pskr.signatures` | 8.45M | `pskr.bronze` + `solar.bronze` | `populate_pskr_signatures.py` | `36-pskr_signatures.sql` |
| `contest.signatures` | 5.74M | `contest.bronze` + `solar.bronze` | `populate_contest_signatures.sh` | `23-contest_signatures.sql` |
| `rbn.dxpedition_signatures` | 260.47K | `rbn.bronze` windowed by `dxpedition.catalog` | `populate_dxpedition_paths.sh` | `29-rbn_dxpedition_signatures.sql` |

## 3. Gold — model training sets

Sampled from bronze, **not** from the signatures tables. All three are 10M rows by design; the
size is the sampling target, not a coincidence.

| Table | Rows | Derived from | Built by | DDL |
|---|---:|---|---|---|
| `wspr.gold_stratified` | 10.00M | `wspr.bronze` ⋈ `solar.bronze`, stratified sample | `populate_stratified.sh` | `13-training_stratified.sql` |
| `wspr.gold_continuous` | 10.00M | `wspr.bronze` ⋈ `solar.bronze`, continuous-time sample | `populate_continuous.sh` | `14-training_continuous.sql` |
| `wspr.gold_v6` | 10.00M | `wspr.gold_continuous`, cleaned | `populate_v6_clean.sh` | `15-training_v6_clean.sql` |

**There is no silver layer, and the pipeline is `bronze → gold`.** `wspr.silver` was dropped
2026-09-22 holding zero rows.

It was probably not always empty — `ionis-docs` recorded a clean-slate QA rebuild on 2026-02-07
producing 4,430,000,000 rows. ClickHouse's `part_log` and `query_log` only retain back to
2026-09-06, so when or how it emptied cannot be established now. **That a table could shed four
billion rows and go unnoticed for seven months is the finding, not a gap in it.** It could,
because nothing read it: the only writer was a hand-run CUDA job that is not packaged and has no
unit, and not one gold script referenced it. The medallion diagram in several documents described
a design, not the build.

## 4. Reference and lookup

| Table | Rows | Purpose | Written by | DDL |
|---|---:|---|---|---|
| `wspr.callsign_grid` | 3.68M | Best-known grid square per callsign; resolves missing grids in signature builds | `populate_callsign_grid.sh`, `contest-ingest` | `07-callsign_grid.sql` |
| `solar.iri_lookup` | 319.46M | Pre-computed IRI ionospheric model output, keyed by grid/hour/month/SFI | `populate_iri_lookup.py` | `34-solar_iri_lookup.sql` |
| `wspr.balloon_callsigns_v2` | 1.50K | Balloon/airborne callsigns excluded from terrestrial training | `populate_balloon_callsigns.sh` | `21-balloon_callsigns_v2.sql` |
| `dxpedition.catalog` | 346 | DXpedition callsigns and date windows | `populate_dxpedition_catalog.sh` | `19-dxpedition_synthesis.sql` |
| `contest.log_metadata` | 495.98K | Per-log station metadata (logger software, category, operator class) | `ingest_log_metadata.py` (ionis-devel) | `40-contest_log_metadata.sql` |
| `validation.mode_thresholds` | 30 | SNR thresholds per mode; decides FT8/CW/RTTY/SSB viability | seeded by its own DDL | `27-mode_thresholds.sql` |
| `wspr.live_conditions` | 1.21K | Current SFI/Kp/Ap/X-ray snapshot for dashboards and MCP | `solar-live-update.sh` | `25-live_conditions.sql` |

## 5. `wspr.bronze_uniform` — read this before any time-series query on WSPR

```sql
CREATE VIEW wspr.bronze_uniform AS SELECT * FROM wspr.bronze WHERE toMinute(timestamp) >= 10
```

Since 2023-10-16 wsprnet.org's monthly CSV export has omitted most spots in the first ~10 minutes
of every hour — an upload-latency cutoff, not a truncation. Retention measured per 2-minute slot:
`:00` 0.9%, `:02` 0.8%, `:04` 1.4%, `:06` 13.3%, `:08` 69.1%, `:10+` 100.0%. It hid for roughly
three years because hourly totals look completely normal; the deficit only appears when grouping
by minute-of-hour.

`wspr-backfill` recovers the missing spots from `wspr.live`. **It is finished, and it was not
enough.** `wspr.live` did not escape the defect for that era either — sampling the 15th of each
affected month, its own minute 0–9 retention matches ours to the percentage point:

| Month | `wspr.live` | Ours |
|---|---:|---:|
| 2023-11 | 27.7% | 27.7% |
| 2024-02 | 21.1% | 21.1% |
| 2024-06 | 22.3% | 22.3% |
| 2024-08 | 15.5% | 15.5% |
| 2024-12 | 16.7% | 16.7% |
| 2025-03 | 17.2% | 17.2% |
| 2025-04 | 22.2% | 22.2% |

Confirmed at **id level**, not by count: backfill dry runs on four separate months each returned
`new=0, already-held=everything`.

So roughly **392 million spots across 2023-10-16 … 2025-05-31 no longer exist anywhere we can
reach** — 206.09M held in minute 0–9 against a 597.68M reference from minute 10–19. Month by
month, minute 0–9 volume as a percentage of minute 10–19:

| Period | State |
|---|---|
| ≤ 2023-09 | complete — predates the defect |
| 2023-10 | 63.5% — defect starts mid-month (2023-10-16) |
| 2023-11 … 2024-12 | **15.2 – 26.8% — permanently short** |
| 2025-01 | complete |
| 2025-02 | 88.6% |
| 2025-03, 2025-04 | **18.8 – 38.2% — permanently short** |
| 2025-05 | 85.9% |
| 2025-06 onward | complete — live ingest path, unaffected |

**So for 2023-10 … 2025-05, `wspr.bronze` under-counts the first ten minutes of every hour, and
always will.** Any hour-of-day or seasonal analysis over that span is skewed unless it uses
`wspr.bronze_uniform` or restricts to `toMinute(timestamp) >= 10`. This is not a backlog — it is
a permanent property of the corpus, and the view is a permanent fixture rather than a stopgap.

Totals and coverage figures are unaffected; they were never minute-sensitive.

This view had no DDL and no documentation until this file. It is the single most consequential
undocumented object in the database, because it does not fail — it quietly answers a different
question than the one asked.

## 6. Operational and audit tables

| Table | Rows | Purpose |
|---|---:|---|
| `wspr.ingest_log` | 465 | Per-file ingest record — file, size, rows, elapsed, host |
| `rbn.ingest_log` | 6.41K | as above |
| `pskr.ingest_log` | 5.36K | as above; written by `pskr-ingest` |
| `contest.ingest_log` | 495.99K | as above; one row per Cabrillo log |
| `contest.quarantine` | 0 | Rejected contest logs. Empty because the reload that populates it has not run. |
| `training.runs` | 22 | One row per training run — hyperparameters, outcome |
| `training.epochs` | 913 | Per-epoch loss/metric trace for those runs |
| `validation.model_results` | 33.47M | Per-path model predictions vs actuals. **All v22, latest 2026-02-27.** Written on the M3 by `ionis-training`, which is not checked out on this host. |
| `validation.quality_test_paths` | 100.00K | Held-out path set for quality gates |
| `validation.dxpedition_contest_paths` | 81.52K | DXpedition + contest paths for cross-source validation |
| `validation.sfi_audit_runs` | 7 | SFI clamp audit runs (recipe, clamp bounds, RMSE, TST-900 pass count). see §7 |
| `validation.tst900_results` | 43 | Per-test TST-900 physics-gate outcomes. see §7 |
| `data_mgmt.lab_versions` | 0 | Intended schema/version ledger; `ionis-db-init` writes it. Empty. |
| `data_mgmt.config` | 0 | Intended config store. Nothing reads or writes it. |
| `messages.inbox` | 865 | Agent message queue (IBX). Owned by `shared-context/agent-message-queue.sql`, not ionis-core. |
| `akb.*` (7 tables) | 0–3 | Agent knowledge base. Owned by `fiducial-mesh/core/python/akb/schema/ddl/`, not ionis-core. |

## 7. Objects that had no DDL — closed 2026-09-22

Five objects existed in the live database, created by nothing under version control. They
survived only because nobody dropped them: a rebuild from `ionis-core` would have produced a
database without them, and whatever read them would then fail against a schema calling itself
complete. All five are now resolved.

| Object | Origin | Resolution |
|---|---|---|
| `wspr.bronze_uniform` | created by hand 2026-09-05 during the backfill work | DDL added — `38-wspr_bronze_uniform.sql`. §5 explains why it matters. |
| `validation.sfi_audit_runs` | created 2026-02-23 during the SFI clamp work | DDL added — `39-validation_sfi_audit.sql`; 7 rows of audit history preserved |
| `validation.tst900_results` | created 2026-02-23, same work | DDL added — `39-validation_sfi_audit.sql`; 43 gate results preserved |
| `contest.log_metadata` | DDL lived in `ionis-devel/contests/`, which nothing applies | moved to `40-contest_log_metadata.sql`; the old path is now a pointer |
| `wspr.dup_fix` | scratch table from the 2026-09-05 duplicate cleanup, 0 rows | **dropped** — the cleanup is finished |

`scripts/verify_schema_complete.sh` now makes this mechanical. It diffs `system.tables` against
`src/*.sql` in both directions and fails on either:

- **orphan** — live, created by no DDL here
- **ghost** — DDL here, no such table live (which matters, because `src/*.sql` is globbed by the
  `Makefile` *and* by `ionis-core.spec`, so the next apply recreates it)

Run it after any schema change. It was the hand-done diff that found all five of the above; it
takes seconds now instead of an afternoon. Verified in both directions against a deliberately
planted orphan and a planted ghost.

## 8. Empty tables and what that means

Empty is not automatically wrong. Each of these is empty for a different reason, and the reason
is the point:

| Table | Why empty | Action |
|---|---|---|
| `contest.quarantine` | reload has not run | fills on the contest reload |
| `data_mgmt.config` | never adopted | decide: use it or drop it |
| `data_mgmt.lab_versions` | `ionis-db-init` writes it, has not been run since the schema was applied | populate on next init |
| `validation.quality_test_voacap` | VOACAP comparison not yet run | pending |
| `validation.step_i_paths`, `step_i_voacap` | Step-I study complete, tables never populated | drop after confirming the study is closed |
| ~~`wspr.balloon_callsigns`~~ | superseded by `_v2` | **dropped 2026-09-22** with `17-balloon_callsigns.sql` |
| `akb.*` | AKB not yet deployed | expected |

## 9. Views

| View | Definition | Status |
|---|---|---|
| `wspr.bronze_uniform` | `wspr.bronze` where `minute >= 10` | **essential — see §5** |
| `wspr.v_schema_contract` | column/type contract for `wspr.bronze` | active guard |
| `wspr.v_data_integrity` | integrity counters over `wspr.bronze` | active guard |
| `solar.v_daily_indices` | daily rollup of `solar.bronze` | active. Created by `03-solar_silver.sql` — **the filename is a leftover from the retired silver concept; the view has nothing to do with it** |
| `data_mgmt.v_lab_versions_latest` | latest row per component from `lab_versions` | empty because its base table is |
| `geo.v_grid_validation_example` | worked example for the Maidenhead UDFs | documentation, not data |

## 10. The pipeline, as built

```
wsprnet CSV ──┐
wspr.live ────┴─▶ wspr.bronze ─────┬──▶ wspr.signatures_v1 ──▶ signatures_v2_terrestrial
                                   │         (⋈ solar.bronze, callsign_grid)
                                   ├──▶ wspr.gold_stratified   ┐
                                   ├──▶ wspr.gold_continuous ──┴─▶ wspr.gold_v6 ──▶ training
                                   └──▶ wspr.callsign_grid

PSK Reporter MQTT ─▶ pskr.bronze ─▶ pskr.signatures
RBN daily ZIPs ────▶ rbn.bronze  ─┬▶ rbn.signatures
                                  └▶ rbn.dxpedition_signatures  (windowed by dxpedition.catalog)
Cabrillo logs ─────▶ contest.bronze ─▶ contest.signatures
NOAA SWPC ─────────▶ solar.bronze ──▶ (joined into every signatures and gold table)
                     solar.dscovr ──▶ solar wind features
                     solar.iri_lookup ─▶ IRI features
```

Every arrow above is a script in `ionis-core/scripts/` or a Go binary in `ionis-apps/cmd/`. There
is no arrow that is not.

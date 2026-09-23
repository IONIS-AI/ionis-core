# IONIS Published Collection — v2 specification

**Status: DRAFT.** Nothing here is built. v1.0 remains the published collection until v2 ships.

This specifies the *next* cut of the published IONIS collection — the artifact that SourceForge
distributes and that the IONIS Propagation Atlas renders. It is a companion to
[`DATA-DICTIONARY.md`](DATA-DICTIONARY.md), which remains authoritative for what exists **now**.
Where this document and the dictionary disagree, the dictionary is describing the live lab and
this document is describing an intention.

## 0. What v2 is, in one line

**v2 is the Gold (BI) layer.**

`DATA-DICTIONARY.md` §0 names the gap directly: *"We have no Gold (BI) at all. Every dashboard
question today goes to bronze or to the signatures tables directly, which is why the Atlas and
Superset work keep re-deriving the same joins by hand."*

The published collection is precisely that missing layer — business-ready facts over conformed
dimensions, built once on the powerhouse and read by everything downstream. Framing v2 as a
packaging exercise undersells it; it closes a named architectural gap.

Two rules follow from §0 and are binding here:

- **Gold never reaches past silver into bronze.** v2 is generated from silver. Where a source has
  no silver yet, that silver is a prerequisite of v2, not an exception to it.
- **Each layer must have a stated job and a reader.** v2's reader is the Atlas plus every direct
  consumer of the published files. That is a real, running reader, not a planned one.

## 1. v2 is regenerated, not reshaped

v1.0 was cut on 2026-03-02 from roughly 8.9 billion WSPR rows. `wspr.bronze` now holds **12.68
billion**. Re-encoding the v1 aggregates would preserve a 30% shortfall for the sake of a format
change.

**v2 is a green-field regeneration from current bronze through silver.** That is the decision
(Judge, 2026-09-23) and it is what makes the rest of this document worth building.

Consequences, stated so they are scheduled rather than discovered:

| prerequisite | owner | state |
|---|---|---|
| `pskr_signatures` regenerated — v1 holds **month 2 only**, one month of eight collected | Bob | not started |
| `contest.bronze` rebuilt — **done**, `ionis-core` #19, 387,893,061 rows reconciling to zero residual | Bob | **landed 2026-09-23** |
| `contest.silver` + `contest.signatures` repopulated from the rebuilt bronze — both at **0 rows** | Bob | not started |
| WSPR silver that filters without aggregating (see §7) | open | not started |

v2 cannot be cut before those land. This specification can be finished now; its schedule is
downstream of them.

## 2. The defect that must not survive v1

`median_snr` carries **four incomparable quantities under one column name**, measured across the
v1 SQLite files:

| source | range | what it actually is |
|---|---|---|
| `wspr` | −99.0 … 58.5 | measured weak-signal SNR, dB |
| `rbn` | −8.0 … 80.0 | skimmer figure on a different scale |
| `contest` | 0.0 … 10.0 | **anchored proxy — "worked / worked easily". Not a signal report** |
| `pskr` | −30.0 … 30.0 | measured SNR, different receiver population |

Same name, same type, four meanings. A consumer who averages them, plots them on one axis, or
compares them across sources produces a number that means nothing — and has every reason to trust
a column called `median_snr` while doing it.

**v2 makes the incomparability structural.**

```
signal_metric   REAL      -- the value
metric_kind     ENUM      -- wspr_snr | rbn_skimmer | pskr_snr | qso_proxy
```

`metric_kind` is **mandatory and never defaulted**. Any aggregate spanning more than one
`metric_kind` is invalid by construction, and consumers are expected to refuse rather than render
it. This is the §0 discipline applied one layer up: silver is an extract and not a repair, so a
difference between sources is carried forward honestly rather than smoothed into a shared column.

**This constrains the Atlas.** Comparing *whether a path was open* across sources — presence,
`reliability`, `spot_count` — is sound and is the comparison worth building. Comparing *how
strong* it was across sources is not, and must be refused rather than rendered with a caveat.

## 3. Schema

One fact shape across all signature sources. Bob's measurement that the four v1 schemas are
byte-identical is an asset and is preserved.

| column | type | note |
|---|---|---|
| `tx_grid_4` | `CHAR(4)` | Maidenhead, fixed width |
| `rx_grid_4` | `CHAR(4)` | |
| `band` | `SMALLINT` | ADIF band id |
| `hour` | `SMALLINT` | UTC 0–23, climatology bucket |
| `month` | `SMALLINT` | 1–12, climatology bucket |
| `signal_metric` | `REAL` | was `median_snr` |
| `metric_kind` | `ENUM` | §2 — mandatory |
| `spot_count` | `INTEGER` | observations aggregated into this cell |
| `reliability` | `REAL` | 0.0–1.0 |
| `snr_std` | `REAL` | **open — see §7** |
| `avg_sfi` | `SMALLINT` | quantized, §4 |
| `avg_kp` | `SMALLINT` | quantized, §4 |

**`hour` and `month` are climatology buckets aggregated across each source's whole collection.**
They are not a date and not a live condition. Consumers must present them as such; `05:00 UTC,
month 6` is "typical conditions at that hour in that month", not a moment in time.

### 2.1 Columns removed

**`avg_distance` and `avg_azimuth` are dropped.** They are pure functions of
`(tx_grid_4, rx_grid_4)` — great-circle distance and initial bearing — and cost **263 MB in the
WSPR file alone (15.3% of it)**. A dozen lines of arithmetic in the consumer replaces them. They
were defensible when a desktop application read SQLite row-wise; they are not when a columnar
engine can compute them on the fly over a pruned result set.

## 4. Physical layout

Measured against v1's `wspr_signatures_v2.parquet` (93,596,266 rows, 1.72 GB, 90 row groups):

**Compression.** 1.98 GB uncompressed to 1.72 GB compressed — **a 13.2% reduction**, which is
close to no compression at all. v2 uses **ZSTD**.

**The float columns dominate.** Three of thirteen columns are **59% of the file**:

| column | size | share |
|---|---:|---:|
| `avg_sfi` | 350.4 MB | 20.4% |
| `snr_std` | 345.5 MB | 20.1% |
| `avg_kp` | 312.7 MB | 18.2% |
| *(all remaining nine)* | 712.6 MB | 41.3% |

`avg_sfi` is a bounded solar index; `avg_kp` runs 0–9 in thirds. Neither carries float-grade
information. **Both are quantized to scaled small integers** (value × 10), which dictionary- and
run-length-encode far better than FLOAT.

**Sort order is `band, hour, month`.** v1 is sorted band-then-hour, which prunes well for two of
the three filters and not at all for the third:

| filter | row groups read | bytes read |
|---|---:|---:|
| `band = 107` | 28 / 90 | 541 MB (31.5%) |
| `band = 107 AND hour = 5` | **4 / 90** | **76 MB (4.4%)** |
| `month = 6` | **90 / 90** | **1.72 GB (100%)** |

Every v1 row group spans months 1–12, so a month filter reads the entire file. `month` is a
first-class filter in the Atlas's hour × month view, and in a browser engine with a 4 GiB address
space a full-file scan is the query that runs the user out of memory. Adding `month` to the sort
costs nothing at generation time.

**Hive partitioning** by `metric_kind` and `band`:

```
collection/v2/signatures/metric_kind=wspr_snr/band=107/part-0000.parquet
```

Three reasons, only the first of which is about query speed:

1. Band pruning becomes structural rather than dependent on footer statistics.
2. **Partial download.** A user who only cares about 20 m fetches one directory, not 2–3 GB.
3. **Independent regeneration.** Re-cutting PSKR rewrites `metric_kind=pskr_snr/` and touches
   nothing else — which matters given PSKR must be regenerated anyway.

**Row-group size** targets ~1 M rows, matching v1's effective grouping, which measured well.

## 5. The coverage manifest

Four facts about v1 are discoverable only by looking for them:

- **The collection is HF only, and 278.6 M spots are outside it.** Signatures cover ADIF band ids
  102–111 — 160 m through 10 m, ten bands. `wspr.bronze` holds **278,565,341 rows (2.2%)** on
  bands the collection never publishes: **630 m alone is 216.4 M spots**, 2200 m is 20.9 M, and
  6 m / 4 m / 2 m / 70 cm total 31.0 M. Verified against `10.60.1.1` 2026-09-23; the band ids are
  correctly classified (`frequency` is integer MHz, so sub-1 MHz bands read as 0, which is
  rounding and not corruption). An operator looking for 630 m finds nothing and has no way to
  learn whether that means no data, no propagation, or a scope decision.
- **PSKR is February only** — one month of eight collected, while `pskr.bronze` is the
  second-largest table in the lab. It reads as a minor source; it is a one-month sample.
- **Contest timestamps span 1970 to 2088.** The bronze reload landed (#19) and now carries the
  whole archive — 387,893,061 rows across 18 contest labels, CQ-WW-CW running to 2025 — but a
  small number of rows sit outside any plausible window. A consumer computing an era from
  `min`/`max` gets 1970–2088 and presents it as fact.
- **v1.0 froze 2026-03-02** at ~8.9 B WSPR rows against 12.68 B live — correct behaviour that
  reads as a defect.

Every one of those is a way for a consumer to draw a false conclusion in good faith.

**v2 ships a machine-readable manifest per dataset** declaring at minimum: schema version, source,
`metric_kind`, row count, bands present, month span, era covered, freeze date, and the generating
`ionis-core` version. Consumers render coverage *from the manifest*, never from hardcoded
knowledge.

This is the dictionary's "read by" column applied to the published artifact: a blank is a finding,
not a detail. It is what makes the Atlas's three-state requirement — *not installed* / *no
observations for this climatology condition* / *observed closed* — satisfiable mechanically
instead of by a builder remembering.

## 6. What ships, and under what name

| artifact | format | consumer |
|---|---|---|
| signatures | **Parquet**, partitioned | Atlas, pandas, Polars, R, DuckDB, ClickHouse |
| signatures | SQLite | IONIS-AI MCP servers — a live consumer, retained |
| dimensions (`grid_lookup`, `solar_indices`, `dscovr`, `balloon_callsigns`) | Parquet + SQLite | shipped whole; 135 MB combined, cached once |
| manifests | JSON | every consumer |

**Naming fix carried from v1:** `balloon_callsigns_v2.sqlite` contains a table named
`balloon_callsigns`. File and table agree in v2.

**Schema version is declared in the manifest and is independent of the application version.** An
Atlas release must be able to read an older collection and say plainly when it cannot, rather than
forcing an application release for every data regeneration.

**Two licences, stated separately.** Code is Apache-2.0; the collection carries its own data
licence. They are different artifacts with different terms and are not to be conflated in one
LICENSE reference.

## 7. Open

- **Does `snr_std` survive?** It is 345.5 MB — the third-largest column in the file — and earns
  its place only if a consumer renders dispersion or error bars. If nothing does, it is the
  largest unjustified cost in the schema.
- **WSPR silver.** `wspr.signatures_v2_terrestrial` both filters (balloon exclusion, quality
  gates) and aggregates, which is two layers in one table. v2's own rule — gold extracts from
  silver — requires a WSPR silver that filters without aggregating. Not started.
- **Grid resolution.** Looking a grid up is a join to a conformed dimension and belongs in gold;
  dropping rows whose grid cannot be resolved is a filter and belongs in silver. Agreed but not
  yet written into `DATA-DICTIONARY.md` §0. **Do not build to either reading until it is.**
- **Does v2 stay HF-only?** 630 m carries 216.4 M bronze spots — more observations than the
  entire contest signature output — and LF/MF propagation is a genuinely different regime worth
  studying. Publishing it is a scope decision, not a technical obstacle; partitioning by band
  means adding it costs nothing structurally. Declaring the exclusion is mandatory either way.
- **Dimension and rule-input categories.** Three of the nine published datasets are dimensions
  (`grid_lookup`, solar indices, DSCOVR) and one is a rule input (`balloon_callsigns`). Neither
  category exists in §0's model, which describes fact data only.

## 8. Generation and acceptance

**Generated on the 9975 in ClickHouse.** That is where bronze and silver live, it is the only
engine in the lab that writes well-encoded Parquet, and the work is a batch job rather than a
service. Compute once on the powerhouse; the artifact is then inert and renders anywhere.

v2 is not published until:

1. Every dataset has a manifest and every manifest validates against its schema.
2. Row counts reconcile to the generating silver with **zero residual**.
3. No `metric_kind` is null, and no shipped aggregate spans more than one.
4. A `band + hour` query against the published Parquet reads **under 10% of the file**, measured
   rather than assumed.
5. Published checksums verify from a clean download.
6. `DATA-DICTIONARY.md` is updated in the same change — a published artifact with no dictionary
   entry is the exact failure this collection exists to avoid.

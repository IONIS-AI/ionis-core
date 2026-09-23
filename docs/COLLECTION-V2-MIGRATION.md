# IONIS Collection v2 — migration plan

**Companion to [`COLLECTION-V2-SPEC.md`](COLLECTION-V2-SPEC.md).** The spec says what v2 *is*;
this says how we get there, in what order, and how each step is known to be finished.

**Worked top to bottom. A phase is not started until the one above it is verified.** Every phase
has a gate that is measured, not asserted — the point is that "done" is observable by someone who
was not in the room.

Nothing in v1.0 changes while this runs. v1.0 stays the published collection until v2 replaces it.

## The live board

**https://claude.ai/artifact/DRngCtf22nyFkCqKW4qAyq** — Judge's status view of this plan.

**This file is the record; the board is the window.** When they disagree, this file wins and the
board is corrected. Specs, gates and sign-offs are reviewed and versioned here, in git, because
that is where chain of custody lives — a hosted page has no diff, no PR, and no signed authorship.

**Updating it:** republish to that URL. An agent that publishes a new board without passing this
URL creates a *second* artifact, and Judge's bookmark then silently tracks a stale page. The link
lives in this file so any session can find it.

---

## Status board

| phase | what | owner | gate | state |
|---|---|---|---|---|
| **0** | Bronze is trustworthy | Bob | every source audits archive = bronze, 0 residual | **in progress** |
| **1** | Decide what v2 contains | Judge | every table classified; no "undecided" | not started |
| **2** | Name everything | Watson → Bob | every dataset has a name and a grain sentence | not started |
| **3** | Silver where it is missing | Bob | every published gold extracts from a silver | not started |
| **4** | Schema and DDL | Watson → Bob | DDL applies clean; schema matches spec §3 | not started |
| **5** | Generate | Bob | artifacts exist on the 9975 | not started |
| **6** | Verify | Watson | spec §9 acceptance, all six criteria | not started |
| **7** | Publish | Bob + Judge | downloadable, checksums verify from clean fetch | not started |
| **8** | Dictionary and lab migration | Bob | dictionary matches reality; lab names migrated | not started |
| **9** | Atlas consumes v2 | Watson | Atlas runs against v2 on both paths | not started |

---

## Phase 0 — Bronze is trustworthy

**Not part of v2, and v2 cannot start without it.** This is Bob's existing download → ingest →
bronze plan, reproduced here only so the dependency is visible.

The binding constraint: **item 3 changes bronze row counts.** Making the WSPR, RBN and PSKR
ingesters keep every record and reloading them will move the numbers, the way contest moved from
234 M documented to 387,893,061 actual. Cutting v2 before that finishes repeats precisely the v1
mistake — freezing a published collection from a bronze that was about to be corrected.

| | state |
|---|---|
| Contest download → ingest → bronze | **done** — 387,893,061 rows, 0 missing, ~1 min reload, audit packaged |
| Solar bronze rebuild — Kp, SFI, SSN own tables | **done** |
| Solar kept current — schedule the new pairs, retire dead units | in progress |
| Solar history backfill — DSCOVR to 2016-07-26, GOES X-ray archive | queued |
| WSPR / RBN / PSKR — audit, keep-every-record, reload to 0 | queued, PSKR first |
| Contest download scheduling | queued |

**Two additions to Bob's item 1, from verification on 2026-09-23:**

- **`solar-live-update` is healthy — do not retire it.** It writes `wspr.live_conditions` (1,366
  rows, newest 21:00:08 UTC), not the dropped `solar.bronze`. Only `solar-backfill` and
  `solar-history-load` are actually failed.
- **`solar.v_daily_indices` is broken and will come back if only dropped.** It selects
  `FROM solar.bronze FINAL` and errors `UNKNOWN_TABLE`; the dictionary still lists it as *active*.
  It is created by `src/03-solar_silver.sql`, and `src/*.sql` is globbed by the `Makefile` and
  `ionis-core.spec`, so **every schema apply re-creates it**. The DDL file must go with the view.

Verified on the 9975, 2026-09-23 21:00 UTC:

```
systemctl --failed
  llm@bench70.service         failed   LLM instance - bench70
  solar-backfill.service      failed   Solar GFZ Potsdam backfill (SSN/Kp/Ap)
  solar-history-load.service  failed   Solar history load (7-day X-ray/Kp/SFI refresh)

solar-live-update.timer   ran 21:00:03, next 21:15   -> healthy, writes wspr.live_conditions
wspr.live_conditions      1,366 rows, newest 2026-09-23 21:00:08
```

**One request on item 3, and it is nearly free.** That item creates new tables — the raw copy and
the tags. **Those should be born with the naming convention** of spec §6 rather than inheriting
the current vocabulary. Naming a table correctly at `CREATE` costs nothing; renaming it later is a
migration with a blast radius across every populate script, MCP server and dashboard. This is the
moment where the accretion either stops or gets one layer deeper.

**PSKR-first is right, and for a second reason Bob did not name.** Its published signatures are
already wrong — `pskr_signatures` covers **February only**, one month of eight collected, while
`pskr.bronze` is the second-largest table in the lab at 7.16 B rows. It is the one source where
the bronze defect has already reached the published collection.

**One thing that is not a defect:** contest bronze spanning 1970–2088. Bronze is faithful; a
publisher serving a malformed line is a fact about the publisher, and filtering belongs in silver.
Contest is genuinely finished, and the 86 out-of-window rows should be left alone.

### Gate 0

Every source has an audit proving **archive records = bronze rows, zero residual**, and the audit
is packaged and runnable. Solar tables receive fresh rows on a schedule and no unit is failed.

---

## Phase 1 — Decide what v2 contains

**The largest open question, and the one that blocks everything.** The spec's dataset list
currently inherits v1's nine, which nobody chose. The live database holds **62 tables across 12
databases**.

### 1a. Classify every table

Every one of the 62 gets exactly one label: **publish**, **do not publish**, or — only
temporarily — **undecided**. The gate is that no table is left undecided.

**Already in v1 (9):** the four source path-climatologies, DXpedition, solar indices, DSCOVR,
balloon callsigns, grid lookup.

**New candidates that change what the collection is:**

| table | rows | the question it raises |
|---|---:|---|
| `solar.iri_lookup` | 319,455,360 | Publishing a *model* beside the observations makes this a different artifact — one that lets someone compare prediction to measurement without running IRI. It is also bigger than everything in v1 except WSPR. |
| `validation.model_results` | 33,467,572 | IONIS predictions against observation. This is the scientific claim in data form. Publishing it invites checking — which is the point, and also the risk. |
| `wspr.gold_v6` + two samples | 10 M each | The actual training sets. Publishing them is what makes the model reproducible rather than described. |
| `solar.ssn_bronze` | 76,214 | Sunspot number back to **1818**. Not an IONIS derivative — a curated archive of definitive data, valuable independent of propagation. |
| `solar.kp_bronze` | 276,784 | Kp/ap back to **1932**, zero incomplete months in 94 years. Same argument. |

**Plausible:** `rbn.dxpedition_paths` (3.89 M), `wspr.callsign_grid` (3.68 M),
`contest.log_metadata` (824,859 — logger market share, category distribution),
`validation.quality_test_paths` (100 K), `dxpedition.catalog` (346).

**Never:** `messages.inbox`, `akb.*`, `data_mgmt.*`, all `ingest_log`, `_tmp_history_load`,
`bronze_pre_rebuild_20260922`, `training.*`.

### 1b. Settle the four open scope questions

| question | why it must be answered here | evidence |
|---|---|---|
| **Does v2 stay HF-only?** | 630 m carries **216,354,913** bronze spots — more observations than the entire contest signature output — and 2200 m another 20,889,694. VHF/UHF adds 31 M. Band partitioning means including them is structurally free. | 278,565,341 rows, 2.2% of `wspr.bronze`, outside the published 102–111 |
| **Does `snr_std` survive?** | 345.5 MB — the third-largest column — earning its place only if something renders dispersion | 20.1% of the WSPR file |
| **Does v2 publish model output?** | `solar.iri_lookup` and `validation.model_results` change the collection's character from observation to observation+model | 353 M rows combined |
| **Where does `grid_lookup` come from?** | 31,658 rows in the v1 SQLite and **no table behind it anywhere in ClickHouse**. An artifact with no traceable source cannot be regenerated. | absent from all 62 tables |

### Gate 1

Every table is labelled publish or do-not-publish with **no undecided remaining**, all four scope
questions are answered, and `grid_lookup`'s origin is identified or the dataset is dropped.

---

## Phase 2 — Name everything

Applies spec §6. Cheap now, expensive later, and the whole reason this is its own phase is that
naming after generation means regenerating.

For **every** dataset that Phase 1 marked publish:

1. A v2 name following `<domain>.<layer>_<grain>[_v<n>]`
2. **A grain sentence** — what one row is, in one sentence a stranger understands
3. `dim_` or `rule_` instead of a layer where it is not fact data

**The grain sentence is the real test.** A dataset whose grain cannot be stated is not understood
well enough to publish, whatever its row count. That is a finding to resolve, not a naming problem
to work around.

**Bob reviews the grain vocabulary before it is fixed.** He lives in these tables; if
`path_climatology` is the wrong word, now is when it costs nothing to change.

### Gate 2

Every published dataset has a v2 name and a grain sentence, both reviewed by Bob. Zero datasets
carry the word *signatures*.

---

## Phase 3 — Silver where it is missing

Spec §0's rule is binding: **gold extracts from silver, and never reaches past it into bronze.**
Today only contest has a silver, and it holds zero rows.

| source | silver state | needed |
|---|---|---|
| contest | exists, **0 rows** | repopulate from rebuilt bronze |
| WSPR | **none** | `signatures_v2_terrestrial` both filters (balloon exclusion, quality gates) and aggregates — two layers in one table. Needs a silver that filters without aggregating. |
| RBN | **none** | same pattern |
| PSKR | **none** | same pattern, plus full regeneration — v1 is one month of eight |
| solar | `solar.silver`, 276,784 rows, nine readers | done |

**Three doctrine gaps must close here**, because gold cannot be built correctly while they are
open. Each goes into `DATA-DICTIONARY.md` §0 as an amendment, not into this plan as a workaround:

1. **The grid-resolution split** — looking a grid up is a join to a conformed dimension and belongs
   in gold; dropping rows whose grid cannot be resolved is a filter and belongs in silver. Agreed,
   never written down. **Do not build to either reading until §0 says so.**
2. **Dimension and rule-input categories** — §0 describes fact data only, and four of v1's nine
   datasets are not fact data.
3. **No layer without a running reader, at CREATE** — already satisfied by `solar.silver`, and
   worth stating as the rule rather than the anecdote.

### Gate 3

Every source that v2 publishes has a silver with a stated filter rule in its DDL and a running
reader. All three §0 amendments are merged. No gold build reads bronze directly.

---

## Phase 4 — Schema and DDL

Implements spec §3.

- `signal_metric` + **mandatory** `metric_kind` replaces `median_snr`
- `avg_distance` and `avg_azimuth` dropped — 263 MB, pure functions of the grid pair
- `avg_sfi` and `avg_kp` quantized to scaled small integers
- `CHAR(4)` grids, `SMALLINT` where a smallint suffices
- Manifest JSON schema written, including the grain sentence field from Phase 2

### Gate 4

DDL applies clean from a fresh schema. A round-trip test proves an aggregate spanning two
`metric_kind` values **fails** rather than returning a number.

---

## Phase 5 — Generate

**On the 9975, in ClickHouse.** That is where bronze and silver live, it is the only engine in the
lab that writes well-encoded Parquet, and it is a batch job rather than a service. Compute once on
the powerhouse; the artifact is inert afterwards and renders anywhere.

Per spec §4: `ORDER BY band, hour, month` · ZSTD · hive-partitioned by `metric_kind` and `band` ·
row groups ~1 M rows.

Then the companions: SQLite for the MCP servers, and the per-dataset manifests.

### Gate 5

Artifacts exist on the 9975 and the export is reproducible from a script in `ionis-core`, not from
a command someone remembers.

---

## Phase 6 — Verify

Spec §9's acceptance criteria, all six, measured:

1. Every dataset has a manifest; every manifest validates against its schema
2. Row counts reconcile to the generating silver with **zero residual**
3. No `metric_kind` is null and no shipped aggregate spans more than one
4. A `band + hour` query reads **under 10% of the file** — measured from the Parquet footer, the
   way v1 was measured
5. Published checksums verify from a clean download
6. Every manifest carries its grain sentence
7. `DATA-DICTIONARY.md` updated in the same change

**Criterion 4 is the one that proves the layout worked.** v1 reads 4.4% for band+hour and **100%
for month alone**. If v2 does not fix the month case, the sort did not take.

### Gate 6

All seven pass. A failure here returns to the phase that caused it — not a patch at this layer.

---

## Phase 7 — Publish

- SourceForge layout under `v2.0`, alongside `v1.0` which stays
- Parquet, SQLite, manifests, checksums
- **Two licences, stated separately** — Apache-2.0 for code, the data licence for the collection
- A citation, so the scientist has something to cite
- The freeze date stated plainly, in prose, on the collection and in every manifest

**v1.0 is not deleted.** It is what the Atlas and the MCP servers read until Phase 9 completes.

### Gate 7

A clean download on a machine that never saw the lab verifies checksums and opens every file.

---

## Phase 8 — Dictionary and lab migration

- `DATA-DICTIONARY.md` describes v2 as published, with the source/writer/reader/DDL row every
  table gets
- The ClickHouse rename from spec §6, **bridged by `CREATE VIEW <old> AS SELECT * FROM <new>`** so
  nothing breaks the day it lands
- Bridging views are removed only when nothing reads them, proven by query log rather than belief
- `solar.bronze_pre_rebuild_20260922` dropped once the rebuild is trusted

### Gate 8

No table in the dictionary disagrees with the live database. No published name contains a word
inherited from a retired engine.

---

## Phase 9 — Atlas consumes v2

Per `fleet-ops` Atlas spec. Both paths — hosted browser and container — read v2, and R12's parity
test proves the two drivers agree.

### Gate 9

The Atlas renders v2 on both paths, R7's three states come from the manifests rather than from
code, and R5 refuses a cross-`metric_kind` comparison rather than rendering one.

---

## What this plan deliberately does not do

**It does not run phases in parallel.** Every one of these depends on the one above it being
*correct*, not merely started. Phase 5 generating from a Phase 3 silver that turns out wrong costs
a regeneration of 175 M rows.

**It does not let a phase finish on assertion.** Each gate is something a person can check
afterwards without having been present.

**It does not touch v1.0.** The published collection keeps working until v2 replaces it.

> **Source of truth.** This file is the IONIS-AI data specification. It was moved here on 2026-09-26 from the Claude Doc "ADIF-Anchored Dimensions" (revision 43), unchanged. From now on it changes only by pull request to ionis-core; there is no other copy.

# ADIF-Anchored Dimensions

Sep 26, 2026 · @Greg

**Decided, under review.** Design record for the lab's reference-data tier: ADIF enumerations as controlled vocabulary in PostgreSQL, extended by IONIS-AI dimensions, consumed by ClickHouse as dictionaries. Decided unless marked Open. Everything here stands as the design; the few items still open are marked as such, each carrying a recommendation and an owner rather than a question. Patton's adversarial review ran against revisions 16–21 and all 15 of its findings are closed, along with two more it raised during the pass.

**The root cause is one thing, not six.** This week produced a grid regex that erased 6.75 billion grid pairs, a solar merge that turned absent readings into fake zeros, a timestamp rounding that collapsed 49 real observations, a success message that reported what it sent rather than what landed, contest headers dropped on ingest, and a DXpedition catalog with grids \~100 km from the island. They were fixed one at a time.

None of them would have existed against a specification. With nothing to build to, every ingester invented its own definition — of what a grid is, of how a missing value differs from a zero, of what a timestamp means, of what "inserted" asserts. The defects are not six failures sharing a shape. They are one failure with six manifestations.

Judge, 2026-09-26: *"Had we put this spec into place 7 months ago, we would not have lost 7 B rows of data."* PSKR collection began 2026-02-10; the erasure ran for the whole seven months.

So the corrective action is not a better regex or a coordinate column. It is the spec itself — ADIF 3.1.7 plus an IONIS-AI extension covering every field the lab downloads, ingests and stores — and this document is the design record for where it lives.

## The problem, measured

Every number below was measured against the live lab, not estimated. They are the evidence the design answers to.

| Finding | Scale | Root cause |
| --- | --- | --- |
| DXpedition grid wrong | 1 of 3 checked | No coordinates stored; grid hand-typed, unverifiable. Initially reported as 2 of 3 |
| PSKR rows with no grid pair | 6,746,970,499 | Collector regex erased uppercase subsquares, 8/10-char grids, and lowercase fields |
| — of those, one lookup from usable | 2,805,821,017 | Missing exactly one end; both callsigns present |
| WSPR frequency truncated to integer MHz | 3,485,092,305 | Every 20 m row reads `14`. Confirmed ours: the WSPRnet archive carries full decimal MHz and the ingester truncates it |
| "ADIF band ID" in the DDL | 102–111 | ADIF defines *no* numeric band ID. A lab convention documented as a standard |
| Contest corpus absent from archive | 328,885 of 824,862 | Bronze reconciled to zero against an archive missing 39.9% |

The last row is the one that generalises: **a clean audit against the wrong reference proves nothing.** Reference data is what audits measure against, so its integrity is load-bearing for every other check in the lab.

On the PSKR line, state precisely what was lost: **the rows exist; the grid pairs in them do not.** 6.75 billion rows carry no usable pair. Of those, 2,805,821,017 are missing exactly one end and both callsigns survive, so they are one lookup from usable — recoverable, not gone. The remainder has no recovery path from the stored row.

## Three layers, not one standard

The exercise began as "use ADIF." It is not that. Every source has its own published specification, and the profile is a mapping document between them.

| Layer | Role |
| --- | --- |
| The source's own spec | **Bronze is faithful to this.** WSPRnet archive CSV · PSK Reporter MQTT · RBN archive CSV · Cabrillo 2.x/3.0 · GFZ · DRAO/NRCan · SIDC/SILSO · NOAA NCEI GOES-R XRS netCDF · NOAA NCEI DSCOVR netCDF · NOAA SWPC RTSW JSON · GDXF |
| ADIF 3.1.7 | The **target vocabulary**. The profile defines the conversion from each source spec where an ADIF field exists |
| IONIS-AI extension | Everything no published spec defines — aggregates, derived geometry, and almost all of solar |

That framing is what makes a whole class of columns **correct rather than defective**: frequency in Hz or kHz where ADIF uses MHz, Cabrillo's `PH` where ADIF says `SSB`, PSKR's flat `FT4` where ADIF makes it a submode of `MFSK`, WSPR power in dBm where ADIF uses watts. Bronze is faithful to the source; the profile converts. Confusing those with defects would have produced a false defect list.

### The column census

641 ClickHouse columns, each carrying exactly one status. Views, backups, Fiducial Mesh and inbox tables excluded. The three indented rows are *components of* the ADIF group, not additions to it — a column we mutated is still an ADIF-defined column, and `band` is both.

| Group | Columns | Note |
| --- | --- | --- |
| Out of scope | 271 | 181 training/validation/ops · 90 provenance |
| Defined by ADIF | 146 | using **2**1 ADIF fields as stored today. Contains the three rows below |
| — as stored (`A`) | 39 | matches ADIF directly |
| — source's own form (`S`) | 21 | Hz/kHz, Cabrillo modes, dBm. **Correct, not defects** — the profile converts |
| — mutated by us (`M`) | 86 | **13 in source tables** — the defect list. 73 in derived tables |
| Defined by Cabrillo | 14 | contest header columns |
| Ours to define | 210 | 139 distinct names: **37 radio, 102 solar** |
| **Total** | **641** | 271 + 146 + 14 + 210 |

Recounted from Bob's `classified.tsv`, where the status codes are mutually exclusive, one per column: I 181, H 90, N 210, M 86, A 39, S 21, C 14. `classified-v2.tsv` is now 644 rows — M rises to 89 on the three added `SWL` rows — and reconciles the same way.

**The IONIS-AI extension is mostly a solar specification.** ADIF covers SFI, K-index and A-index and nothing else — no DSCOVR, no GOES X-ray, no SSN, no IRI. Nobody would have predicted that from the framing of this as a radio-data problem.

## The shape: two schemas in PG-1

**The `adif` schema** holds the ADIF enumerations loaded exactly as published — Band, Mode, Submode, DXCC Entity Code, Contest\_ID, Continent, Primary/Secondary Administrative Subdivision, Propagation Mode and the rest. **25 enumerations, 3,345 records** for 3.1.7. Never edited by us, and nothing of ours added to it.

Source is `adif-mcp`, which already packages the machine-readable spec for both 3.1.6 and 3.1.7 — 30 JSON files each, stamped with `Adif.Version`. So the base layer is generated from the spec rather than typed in, and the version is part of the provenance rather than an assumption. But `adif-mcp` is our own repackaging, not the published spec: generated-not-typed still means generated by us. Bob closed that gap in adif-mcp 1.1.2 — every upstream export's SHA-256 is pinned in test/data/adif\_upstream\_sha256.json, and the 3.1.6 set, which had been LF-converted at some point, is restored to ADIF's exact bytes.

*Why:* ADIF is authoritative, published, versioned and maintained by someone else. Anything we hand-type is a defect waiting to be found.

**The `ionis` schema** holds our own dimensions — DXpeditions and contests first, more later — with foreign keys into `adif`. A DXE row's entity must be a real DXCC code; a contest row's ID must exist. The database rejects anything else, so the check happens on entry rather than in a later audit.

*Why:* it moves integrity from convention to constraint. Every defect this week survived because a rule existed only as a comment or a habit.

### ClickHouse reads both as dictionaries

Joins happen against billions of spots, so the lookup must live inside ClickHouse. A range dictionary keyed on callsign with the operation window as the range answers *"what grid was this call at this moment"* directly. That removes a real hack: the catalog currently keys on `1A0C (2012)` — a callsign with a year glued on, because the present shape cannot express a time-varying fact.

Three mechanics the design has to name rather than assume:

- **`COMPLEX_KEY_RANGE_HASHED`, not `RANGE_HASHED`.** `RANGE_HASHED` takes a `UInt64` key; a string callsign requires the complex-key layout.
- **`range_lookup_strategy` must be stated.** Reused callsigns produce overlapping windows, and the dictionary otherwise picks one silently.
- **An overlap audit is part of the dimension, not optional.** Overlapping ranges are a data defect that the lookup itself will hide.

### Dictionary source: Postgres directly, not via the API

ClickHouse has a native `POSTGRESQL` dictionary source with built-in refresh. Sourcing dictionaries straight from PG-1 means a refresh does not depend on the API being up — EPYC can be down and 12-billion-row joins keep working. The API on EPYC serves everything that is *not* ClickHouse: Atlas, the MCP servers, notebooks, humans.

And ClickHouse does not consume OpenAPI. Its `HTTP` dictionary source expects a payload in a format it knows — `JSONEachRow`, `TabSeparated` — and will not read a spec. So OpenAPI serves every other consumer; ClickHouse needs plain endpoints at stable URLs. Two audiences, one app.

**The failure mode to name:** "PG-1 down, ClickHouse keeps serving the last copy" holds only while ClickHouse stays up. A ClickHouse restart while PG-1 is down leaves the dictionary unable to load, and every dependent query errors. Either that is accepted and documented, or the load snapshots a fallback source on disk.

**Decision: accept the outage and document it. No fallback snapshot.** A snapshot on disk lets ClickHouse come up serving reference data of unknown age with nothing marking it stale — which is the same defect as a dictionary silently picking one overlapping window, and the same defect as a zero that used to be a missing SFI reading. A query that errors is recoverable; a join that quietly returns last month's DXE windows is not, and it corrupts whatever it feeds.

The cost is bounded and the lab already takes this trade knowingly elsewhere — the M3 loses its uplink if the 9975 reboots, accepted and written down with a recovery command. Here the same shape applies: **PG-1 is a hard dependency for a ClickHouse cold start, and reference-dependent queries fail until it is back.** Two things make that safe rather than merely accepted: the failure is loud, and `system.dictionaries` exposes each dictionary's last successful update time, so any audit can assert freshness instead of assuming it.

## Versioning

### Key the `adif` tables on `(adif_version, code)` — never replace

"A new ADIF release replaces the tables" is a one-way door. If 3.1.8 retires a value that `ionis` rows reference, the replace either fails on the foreign key — blocking the upgrade — or cascades and silently changes meaning. Versioned tables make an upgrade additive, and both versions coexist.

The foreign keys must therefore carry the version too: `ionis.dxe(adif_version, entity_code)` → `adif.dxcc_entity_code(adif_version, entity_code)`.

*Evidence:* 3.1.6 → 3.1.7 changed only 2 of ADIF's 25 enumerations — `mode +OFDM`, `submode +FREEDATA, FT2, RIBBIT_PIX, RIBBIT_SMS`. Five rows. A lab release is a reviewable diff, not an act of faith — and if validation is pinned to 3.1.6, a station logging `FT2` gets a valid record rejected.

**Coexistence forces a question, and this record answers it.** Two versions side by side means every lookup must name one, and every `ionis` row is pinned to one. When 3.1.8 lands: do existing rows stay pinned forever, or migrate — and on what trigger? Which `adif_version` does a ClickHouse join select, and is that a per-query choice or a single lab-wide current pointer? Decided below: one lab-wide current pointer, with rows pinned at write.

### Structure moves with ADIF. Rows are data.

Adding a DXpedition or a contest date is a **new row**, not a new version — just as a new spot does not version `pskr.bronze`. Only our own schema changing bumps the revision.

Release label: `3.1.7-1`, `3.1.7-2`, restarting at `3.1.8-1` when ADIF moves. Upstream version plus downstream revision — the same convention the whole fleet already ships on (`ionis-apps-solar-4.5.2-1.el9`).

*Rejected:* semver build metadata (`3.1.7+ionis.2`). The spec is explicit that build metadata must be ignored when determining version precedence, so `+ionis.1` and `+ionis.2` compare as equal — the one thing a revision must not do. Pre-release (`-ionis.2`) orders *below* the release, which is also wrong.

### PROGRAMID: `IONIS-AI`

ADIF's `PROGRAMID` identifies the program that created or processed the content, and the spec notes a voluntary PROGRAMID Register exists to avoid clashes. Self-declaring is legitimate; registering is free collision insurance.

- Bare `IONIS` is a pharmaceutical trademark — ruled out for the same reason as the Docker namespace.
- `IONIS_AI` is ruled out: application fields are built as `APP_<PROGRAMID>_<FIELD>` and parsed on underscores, so `APP_IONIS_AI_PATH` is ambiguous.
- A hyphen is safe — the spec's user-defined field rule bars only comma, colon, angle brackets, curly brackets and leading/trailing space. `WSJT-X` is the most widely emitted PROGRAMID there is.
- `IONIS-AI` matches the GitHub org, the Docker namespace and the workspace folder. One identity everywhere.

*Caveat:* the `APP_` naming rules live in the spec's prose, which is not in the machine-readable set. The hyphen argument rests on the `USERDEF` rule plus precedent, not a direct citation. Worth confirming before anything emits a file.

## Rules that came out of failures

Each of these exists because something broke this week in exactly the way it prevents.

### No sentinel values — `dictGetOrNull` and `dictHas`

A ClickHouse dictionary miss returns the declared *default* — empty string, zero — indistinguishable from real data. A sentinel like `-1` or `'!!NO_MATCH'` was proposed and **rejected**: it is still a fake value sitting in a data column, it leaks into outputs and averages, and for DXCC it collides outright because ADIF defines code `0` as "none".

`dictGetOrNull()` returns NULL on a miss and `dictHas()` tests membership. Audits then assert `countIf(x IS NULL) = 0` wherever a match is required — the same shape as the SSN audit already built and proven.

*Precedent:* this is the zero-filled SFI defect generalised. `solar.bronze` merged with a LEFT JOIN and no `join_use_nulls`, so absent readings became `0` and were indistinguishable from measurements. The model trained on them.

### The CI gate is an allowlist, not a denylist

`dictGetOrNull` only helps if the query uses it, and a NULL-count audit cannot see what was never asked. So the rule needs a mechanical gate — but the obvious gate does not work.

**Only `dictGetOrNull` and `dictHas` are permitted; CI fails on every other `dictGet*` form.** A denylist on "bare `dictGet`" leaks three ways at once:

1. Without word boundaries it matches `dictGetOrNull` itself, failing the compliant call.
2. It lets through the typed accessors — `dictGetString`, `dictGetUInt64` and the rest — which return defaults, which is the whole defect.
3. It lets through `dictGetOrDefault`, which is a sentinel under another name, immediately after the rule above bans sentinels.

That third leak is the one worth keeping as a method note: the gate would have passed CI green while enforcing nothing — the same gate-that-cannot-fire shape this document exists because of.

*Why any gate at all:* every defect this week was a rule nothing enforced — the `comm` sort order, the false `inserted 23967`, the grid regex. A discipline holds until the first person in a hurry.

### One `ionis.contest_id` table with a `source` column

"A real `adif.contest_id` *or one of ours*" cannot be a foreign key — there is no FK to either-of-two-tables. Instead: one table holding ADIF's 256 with `source='adif'` plus ours with `source='ionis'`, and a single FK target.

If ADIF later adopts an ID we invented, **the loader must abort and report the collision**, never merge quietly. A collision means ADIF standardised something of ours — good news that needs a human deciding whether our rows migrate.

### Multi-source evidence columns, not a single answer

Store every source's claim side by side rather than collapsing to one value. Disagreement becomes a queryable fact instead of a worklist that gets lost, and the original is never destroyed.

```
callsign, entity, year, start_ts, end_ts, qsos     -- identity + window
grid_published                                     -- what the TSV said, immutable
lat_qrz, lon_qrz, grid_qrz, grid_calc_qrz, qrz_country, qrz_dxcc, qrz_at
lat_hamqth, lon_hamqth, grid_hamqth, grid_calc_hamqth, hamqth_at
lat_web, lon_web, grid_web, web_source_url, web_at
grid_accepted, accepted_source, verified_by, verified_at, note
```

Three things this buys beyond validation: **stated-vs-computed per source** catches a source whose grid disagrees with its own coordinates — the QSL-manager case; **`qrz_country` vs `entity`** is a free entity check with no prefix map needed; and **adding a source later is a column**, not a redesign.

*The Bouvet test:* `grid_published` keeps `JD16` forever, `grid_accepted` becomes `JD15`, and `accepted_source` plus `verified_at` record who changed it and when. Nothing is silently rewritten and nothing is frozen wrong.

### Store coordinates; derive the grid

The grid must never again be the stored fact. Coordinates are stored, the grid is computed, and the two can be compared. That is the specific defect class that produced the Bouvet entry, and it is closed by construction rather than by care.

## Observation type — the distinction the schema was hiding

### `SWL = Y` on every spot source

ADIF defines `SWL` — Boolean — *"indicates that the QSO information pertains to an SWL report."* Short-wave-listener reports are one-way reception reports, which is exactly what WSPR, RBN and PSKR spots are. Nobody contacted anybody.

Without it, our data expressed as ADIF asserts **22 billion two-way contacts that never occurred**. That is a false claim about the world, not a formatting detail — and it is a single Boolean.

*Consequence:* the ADIF group is 22 fields, not 21. Contest is genuine two-way, so `SWL` is absent there.

The count is therefore **21 as measured, 22 on adoption** — `SWL` is a proposal in this record, not a stored column. It appears only in `classified-v2.tsv`, and there its three rows are coded `M`. That coding is wrong: `M` is the mutated-by-us defect list, and adding a correct ADIF field is neither a mutation nor a defect. Those rows need a distinct status — an ADIF field we *should* carry and do not yet — before the census is cited with 22.

### Drop `tx`/`rx`; use ADIF's roles

The four signature schemas are byte-identical, and `tx_grid_4` meant **opposite things** in them. `populate_contest_signatures.sh:176` joins `cg_tx` on `call_1` — the *logging* station — while RBN uses `dx_call` (the station heard) and PSKR uses `sender_grid`.

The cause is not a bad join. It is that **one schema was describing two kinds of observation**: a spot has a real transmitter and receiver, so `tx`/`rx` is meaningful; a QSO has neither, because both stations transmit — which is why the contest join direction was arbitrary enough to end up inverted.

ADIF's own roles work for both:

| ADIF | means | reception report | QSO |
| --- | --- | --- | --- |
| `MY_GRIDSQUARE` | the logging / reporting station | the receiver | the logger |
| `GRIDSQUARE` | the other station | the station heard | the contacted station |

That states **who reported and who was reported on** — true of both, and it never claims who transmitted. `tx`/`rx` may still be *derived* for spot sources where it is meaningful; it must not be the stored column.

*Mitigating:* `contest.signatures` currently holds 0 rows, so no stored data is 180° off. The defect is in the script, and the azimuth consequence — bearings inverted between contest and the spot sources for the same physical path — was never materialised.

### `observation_type ∈ {reception_report, qso}`

`SWL` records that it was not a contact; `observation_type` makes it a first-class column, because the difference reaches further than grids. `spot_count` counts one-way receptions for a spot source and logged QSOs for contest. `reliability` derived from one-way reports is not the same quantity as from two-way contacts.

*Same lesson as `metric_kind`:* two kinds of thing were collapsed into one column and the reader was expected to know. They are incomparable in exactly the way `median_snr` was.

## Corrective action and prevention

Stated in CLCA terms, because the individual fixes are containment — not the corrective action. 8D requires two root causes, and this record originally carried only one.

### Root cause, occurrence: no specification to build to

Each of this week's defects was a private definition invented at the point of ingest because no shared one existed:

- **Kp** — a missing value and a real `0` stored identically
- **SFI** — a rounded timestamp collapsed 49 genuine observations into other rows
- **Solar** — a `LEFT JOIN` without `join_use_nulls` turned absent SFI into a measurement of zero; a model trained on it
- **Contest** — header fields dropped, and nothing linked headers back to their own QSOs
- **PSKR** — a grid regex rejecting uppercase subsquares, 8/10-character grids and lowercase fields
- **WSPR** — frequency stored as integer MHz where another source stores Hz

All six are now confirmed. The **WSPR** entry was the last one resting on an assumption — the truncation was measured in our table, but whether the source carried more precision was not. It does: a raw WSPRnet archive holds `14.0971`, `14.097046`, `10.140147`, with every sampled row decimal and 303 distinct 20 m values in a 500,000-row slice. `wspr.bronze.frequency` is a `UInt64` storing whole MHz. The definition was invented at ingest, exactly like the other five.

Six ingesters, six private answers to questions a specification answers once.

### Root cause, escape: nothing measured conformance per ingester

A spec explains why the defect was *written*. It does not explain why a null-grid rate near 100% on uppercase subsquares ran for seven months without alarming anyone — and that is the more expensive of the two, because it is what turned a bug into 6.75 billion rows.

The escape point is that **no ingester reports what it conformed to.** Every check in the lab was either downstream (an audit someone chose to run) or self-reported by the writer (`inserted 23967`, which reported what was sent, not what landed). Nothing sat at the boundary of each ingester measuring the shape of what it produced against a declaration of what it should produce.

### Corrective action: the spec

ADIF 3.1.7 plus the IONIS-AI extension, covering every field the lab downloads, ingests and stores. Not a description of what the code happens to do — a definition the code is written against.

### Corrective action: a per-ingester conformance harness

The spec alone closes occurrence and leaves escape open. The harness closes escape, and it is a separate deliverable, not a paragraph in the spec:

| Check | What it catches |
| --- | --- |
| Sent-vs-landed reconciliation | The false `inserted 23967` class — a writer reporting its own intent |
| Per-field null-rate thresholds | The PSKR grid regex, at hour one instead of month seven |
| Per-field value-domain conformance | A field that parses but populates outside its declared enumeration or range |
| Per-field precision/unit assertion | The WSPR integer-MHz class — a unit changing shape between sources, whichever side introduced it |

The thresholds are declared per field in the spec, so the harness has something to measure against rather than a hand-set number. Without it, the next private definition also runs until someone happens to look.

### Prevention: the rule the lab already holds

**Every ingester and every audit is written against the spec and cites it. Drift from the spec is a defect, not a preference.**

That is not a new rule — it is the doctrine already ratified for Fiducial Mesh, applied to the data layer. Which matters: it means this is enforcement of an existing decision rather than the invention of another one, and there is precedent for what citing a requirement looks like and what happens when an implementation disagrees with it.

*The distinction that makes it work:* detection already functions in this lab — audits found every defect above. What did not exist was **prevention**, and what failed was **timeliness of detection**. A specification stops a private definition being written; a conformance harness catches the one that gets written anyway, in hours rather than months. Neither substitutes for the other.

## Extensibility — the part that matters beyond DXE

DXpeditions and contests are the first two. There will be more, and nobody knows what. So standardise the scaffolding, not the columns.

| Every dimension needs | Bespoke or mechanical |
| --- | --- |
| domain columns + natural key | **bespoke** — a DXE row is not shaped like a band plan |
| FK into `adif` including version | mechanical |
| per-row provenance block | mechanical |
| multi-source evidence columns | same pattern, varying columns |
| optional time-ranging | mechanical |
| ClickHouse dictionary definition | mechanical |
| an audit | mechanical |

One bespoke part, six mechanical ones. **Generate the six.** A `ionis.dimension_registry` table holds one row per dimension — name, natural key, which `adif` tables it references, whether it is ranged, refresh interval, owner — and the dictionary DDL, the audit SQL and the API endpoint are produced from that entry.

The payoff is not that adding a dimension gets easier. It is that **dimension #5 cannot be added with a hand-written dictionary using a bare typed accessor and no audit**, which is exactly what would happen on a Friday afternoon. Generated artifacts cannot drift from the rule; hand-written ones always eventually do.

This is the lab's own **PCS primitive** — Spec + Harness + Registry — applied to reference data rather than a new invention. The registry declares, the generator produces, the harness audits.

### The trap: do not reach for a generic key-value table

One `(dimension, key, attribute, value)` table looks maximally flexible and destroys everything Postgres was chosen for — types, foreign keys, constraints, the FK into `adif`. If flexibility is ever argued in that direction, that is the moment to refuse.

### Candidate dimensions beyond the first two

| Table | Ranged | What it validates |
| --- | --- | --- |
| `dxe_catalog` | yes | DX operations, grids, windows — kills the `(2012)` suffix |
| `contest_windows` | yes | Official start/end per year; validates DXE ranges *and* contest bronze |
| `callsign_prefix_entity` | yes | Prefix → entity, with validity dates for reallocations |
| `band_id_lab` | no | ADIF band string → lab integer. A *lab* mapping, named as ours |
| `entity_bounds` | no | Entity extent — mechanises the grid-inside-the-entity test |
| `grid_centroid` | no | The published `grid_lookup`: 31,658 rows shipping from **no table anywhere** |

**Lab mappings are allowed, but only in special circumstances**, and each needs a stated reason, a table rather than a comment, and a name that says it is ours. Band earns one — an integer beats a string for `BETWEEN 102 AND 111` across 12.7 billion rows. Most fields do not: ADIF already supplies an *integer* DXCC entity code, so inventing a second numbering would be pure harm.

## Backward compatibility

### Deprecate, never delete — ADIF's own mechanism

ADIF marks retired values **import-only** rather than removing them, and the flag is already in our packaged data:

| Enumeration | Records | Import-only |
| --- | --- | --- |
| Award | 29 | **29** — entirely deprecated |
| Mode | 91 | **42** — nearly half |
| Country | 400 | 60 — deleted DXCC entities |
| Primary\_Admin\_Subdivision | 1,965 | 50 |
| Contest\_ID | 256 | 4 |

**Read-validity and write-validity are therefore different sets.** 42 of 91 modes are import-only. Validate writes against the full set and we emit deprecated modes; validate reads against only current ones and we reject half of amateur radio's history as invalid.

*The trap:* this would present exactly like a data defect — a validation pass "finding" millions of bad modes that are all legitimate. The `adif` schema must preserve `import_only`, and audits must treat an old row carrying a deprecated value as **correct**.

Applied to our side: `adif` tables versioned and never removed; `ionis` dimensions **additive only** — new columns fine, removing or retyping one is a breaking change; our own `deprecated` flag mirroring `import_only`; dictionaries may gain attributes but never lose one.

### The one place compatibility must not apply

Correcting a wrong fact. Bouvet's `JD16` is wrong; fixing it to `JD15` changes the answer a consumer gets, and that is *correct behaviour*. We do not preserve errors for compatibility's sake.

What makes both properties hold at once is the evidence-column design. So the rule for the spec document is:

> **The schema is additive and versioned; facts are correctable but never erased.** A consumer can always reproduce what we said in 2026 and also get our best current answer — and tell which is which.

## Cabrillo versioning

### The version does not survive ingest — but it is recoverable

`contest.bronze` holds only QSO lines — zero `START-OF-LOG` records — and `contest.log_metadata` has neither a version column nor `file_path`. So **387 M rows cannot be attributed to the Cabrillo version they were parsed under.**

It is still on disk in every file. Surveying the 824,862 logs in `/mnt/contest-logs/_v2`:

```
3.0       810,758
2.0        12,408
V2.0          424
2.3           409
(blank)       335
2.1           162
3              31
2.2            26
----------------
          824,553
```

Those counts total **824,553** — **309 logs short** of the 824,862 on disk. The 2.x logs (2.0, V2.0, 2.3, 2.1, 2.2) total **13,429**, and 335 declare no version at all.

**The 309-log gap is an open item, not a rounding remark.** A version survey that silently loses 309 files is the same class of defect as everything else in this record — a count reported without a reconciliation. Cause unknown: possibly unreadable or absent headers, possibly files the survey's own walk skipped. It needs explaining before the Cabrillo profile is written, because the profile's coverage claim rests on this survey.

**Reconciled by Bob, 2026-09-26. The gap was in the survey, not the corpus.** **824,715** logs carry a `START-OF-LOG` line and **147** do not have one at line start — some indented, some beginning on another header such as `CONTEST:` (`ja1chy.log`). 824,715 + 147 = **824,862**, exactly the corpus. The earlier 824,553 came from listing only the top 8 version strings out of **45 distinct** ones, so 162 logs were hidden in the tail rather than missing from disk. No files were skipped and none are unreadable.

Cabrillo 2.x and 3.0 differ in header fields and in the QSO line for some contests — a plausible source of several of the seven parser defects already fixed.

*Fix:* keep every header line including `START-OF-LOG`, with `file_path`, so each log's version joins to its own QSOs. Folds into the contest header defect already queued.

## Prerequisite: the DXE base data

Nothing goes into `ionis` until the base data is reconciled. Grid validation against a malformed callsign is meaningless, and a grid check against a wrong date window is worse — it looks like a result.

| Pass | Result | Note |
| --- | --- | --- |
| Catalog size | 346 entries | 370 distinct stations, 164 entities, 2009–2026, 22.7 M QSOs |
| Structural — malformed callsigns | 7 on 6 lines | `3D22`, `5R8..`, `7QAA`, `ZEW`, `ZW`, `MD/DL-TEAM`, `VP2V/SP...` |
| RBN witness — corroborated | 354 of 383 | **92.4%** — callsign and dates both confirmed by our own spots |
| Seen but never in window | 10 | Only **1** a real error; 4 reused calls, 1 pre-RBN, 3 noise, 1 to check |
| Never witnessed | 19 | Next pass: contest logs, which see SSB where RBN cannot |
| Resolved so far | 1 | `E51M` — dates carried year 2014; 5,075 RBN spots prove 2012, zero in 2014 |

Two method lessons worth keeping. **RBN flags need filtering before any one counts as a finding** — 9 of 10 were artifacts of reused callsigns or coverage gaps, which is Bob's caution proved in data. And **RBN cannot witness SSB at all**, nor anything before 2009-02-21, so absence is only suspicious for an operation that should have been machine-decodable.

The `E51M` correction is to `ionis-core/data/dxpedition-catalog.tsv`, not to ClickHouse: the TSV is the source of record and installs to `/usr/share/ionis-core/data/`, so a ClickHouse-only fix is undone by the next reinstall. It is held pending one-at-a-time reconciliation of the remaining lines rather than applied alone.

## Load, and the one rule that keeps it near zero

All of this is small reference data. The cost is negligible *provided* ClickHouse never queries PG-1 directly.

| Table set | Rows |
| --- | --- |
| ADIF enumerations, per version | 3,345 |
| — of which administrative subdivisions | 1,965 |
| — DXCC entities · contest IDs · submodes | 403 · 256 · 187 |
| Two ADIF versions side by side | \~6,700 |
| DXpeditions | 346 |
| Contest-year rows | \~1,000 |
| Declared-grid table, if the recovery proceeds | 10⁵–10⁶ |

Under 1 GB for the whole tier, against 22 billion rows of spots. **Reads:** a ClickHouse dictionary loads its table in full into ClickHouse memory and refreshes on a timer, so PG-1 sees one small `SELECT` per table per refresh — milliseconds — and joins against billions of spots run entirely against the in-memory copy. **Writes:** human edits and QRZ lookups, which are rate-limited — thousands of rows a day at most.

### ClickHouse reads PG-1 *only* through dictionaries

Never a direct `postgresql()` table function or table engine in a query. A direct join from a billion-row scan would push that load straight onto PG-1 and turn a reference lookup into a distributed query.

*Enforcement:* the gate must match every way a Postgres reference can enter ClickHouse SQL, not just the function call — `postgresql(` case-insensitively, `ENGINE = PostgreSQL(...)` table definitions, and named collections that resolve to a Postgres source. Dictionary DDL is the allowlisted exception; everything else fails. A rule that lives only in a spec is a rule that holds until the first person in a hurry — which is the finding this whole document exists because of.

### The enumeration count, reconciled

Four numbers were in circulation for one quantity — 3,745, 3,733, 3,345 and \~3,700. The count is not **3,745** for ADIF 3.1.7, but 3,345 across 25 enumerations. The spread had one cause in our own packaging and two of mine:

- **3,345** is ADIF's own set, across 25 enumerations. The combined `enumerations.json` and `all.json` were **right all along**.
- **3,745** is that plus a 400-record `Country` table, which **ADIF does not publish**. It is `adif-mcp`'s own derived view of `DXCC_Entity_Code`'s Entity Name, re-keyed by name — labelled as derived since adif-mcp 1.1.1.
- **3,733** was my own walk, with a script bug.
- **\~3,700** was a rounded restatement of that bug, and should not have appeared beside a precise figure.

**Loader requirement: load the 25 enumerations whose source is ADIF, and assert 3,345.** `Country` needs no table — `DXCC_Entity_Code` already carries the data.

An earlier revision of this record instructed the opposite: *"read the 26 per-enumeration files, not the combined ones, and assert the total."* That instruction would have written **our own derived table into the `adif` schema as though ADIF published it** — breaking the rule stated at the top of this document, that `adif` holds the spec exactly as published and is never edited by us. The schema meant to be the authority would have carried an invention of ours, indistinguishable from spec.

I also filed `adif-mcp#8` asserting the combined files had *omitted* `Country`. The premise was inverted: nothing was missing. Bob established the truth by checking adif.org's published zips rather than reasoning from our own repackaging — which is the method this document argues for, applied to a claim of mine that had already passed two reviews.

## No declaration source is authoritative

This emerged from two grid checks going opposite ways, and it changes what the evidence columns are for. Judge has parked the grid reconciliation itself for research; the structural conclusion stands now.

| Entry | Catalog | QRZ | The station's own reports | Verdict |
| --- | --- | --- | --- | --- |
| RI1FJL, Franz Josef Land | `LR90` | `LR40qk` | `LR90` ×592,581 · `LR40` ×667 | **catalog right, QRZ stale** |
| 3Y0K, Bouvet Island | `JD16` | `JD15qn` | `JD16` ×656 | **catalog wrong — and the station carried the same error** |

Heiss Island sits at roughly 58.05°E, which is `LR90` — so the catalog was right and **QRZ was the outlier**, contradicted by 99.9% of the operation's own spots. For Bouvet the geography says `JD15`, but the operators' own configuration reported `JD16`, and the catalog copied that declaration faithfully.

**Across two entries: QRZ wrong once; the catalog and the station wrong together once.** There is no source that can be trusted by default — which is precisely why the evidence columns exist rather than a single "correct" grid. My own error in the first pass was treating QRZ as ground truth, which is the same mistake in the opposite direction.

### Coordinates need their own source and date

"Store coordinates, derive the grid" is necessary and **not sufficient**. For RI1FJL it was QRZ's *coordinates* that were stale, and a grid derived from them would have been confidently wrong and perfectly self-consistent.

```
lat_<source>, lon_<source>, coord_source, coord_asof, coord_url
grid_<source>          -- as that source states it
grid_calc_<source>     -- derived from that source's coordinates
grid_accepted, accepted_source, verified_by, verified_at
```

`grid_<source>` against `grid_calc_<source>` catches a source disagreeing with itself; `coord_asof` makes staleness visible instead of invisible.

### Check a declaration against observation — but never substitute

Compare every declared grid with what the station **itself reported** in our own spot data. A declared grid contradicted by 99.9% of the station's own transmissions should be *rejected*, not joined.

*The line that matters:* this is the correct use of observation — to **test** a declaration. Using observation to **replace** a declaration is the rejected move: substituting a WSPR-derived grid into PSKR makes PSKR a derivative of WSPR while the schema still claims an independent source.

**Where that rule collides with the PSKR recovery.** Filling the missing end of 2,805,821,017 PSKR rows from a callsign lookup *is* substitution — the recovery and the rule cannot both be taken at face value. The resolution is per-row provenance, not an exception: a recovered grid is written to a distinct column with its own source and date, never into the field that claims PSKR observed it, and any consumer computing an independent cross-check must be able to exclude derived rows in a single predicate. If the recovery cannot be marked that way per row, it does not proceed.

**Judge's decision, 2026-09-26: a separate table, joined on demand. Bronze is never touched, and the ingester is adjusted accordingly.** That settles it in the strongest direction available — `pskr.bronze` keeps saying only what PSKR reported, and a consumer who wants recovered grids opts in by joining. Nothing can accidentally read a derived grid as an observed one, because it is not in the row.

Four things the recovery table must answer before it is built:

1. **No join key is needed — the recovery is a lookup, not a row-to-row join.** An earlier draft of this section called for a spot ID at ingest so the recovery table could join back to `pskr.bronze`. That was my framing error, and Patton caught what it led to: a spot ID added at ingest never reaches the 2.8 billion historical rows the recovery exists for, and giving them IDs means rewriting stored rows — which the decision above forbids.

   What the recovery actually asks is *"what grid was this callsign at this moment"*, which is a dimension lookup — the same pattern this record already specifies for DXE. Measured over seven days of `pskr.bronze`: **67,361** distinct callsigns need a TX grid, and of the callsigns that do report one, **75,099 of 76,145 — 98.6% — report exactly one**, with 934 reporting two and 112 reporting three or more.

   So the lookup is a `COMPLEX_KEY_RANGE_HASHED` dictionary over roughly 67 thousand callsigns, keyed on callsign with a validity range for the 1.4% that move. `dictGetOrNull` returns one value per key **by construction**, so the fan-out that motivated the spot ID cannot occur — fan-out is a property of joins, not of dictionary lookups. No spot ID, no 7.1-billion-row rewrite, and bronze is untouched in the strongest sense: not even rebuilt. Tracked at `ionis-apps#54`, closed as superseded.
2. **A lookup as-of date, per row.** QRZ's grid today is not the station's grid at spot time; that is the RI1FJL lesson exactly. Every recovered grid carries its source and as-of date, and portable or rover callsigns are excluded rather than guessed.
3. **A declared cutoff.** The fixed regex should stop producing gaps, so the table covers a stated historical window and no more. Without a written cutoff, recovery becomes a permanent crutch that hides a regressed regex — the gap refills and the table quietly covers for it.
4. **The harness lands in the same change as the regex fix.** The per-field null-rate check from the conformance table ships with the fix, not after it. Otherwise this exact class can reopen silently, which is the whole failure this record is about.

## Future-proofing grids — one contract, both paths

Judge, 2026-09-26: *"We need to future proof PSKR and DXE's against bad grids, however that can be done."*

PSKR and DXE fail on grids in opposite directions, which is why one contract is the right answer rather than two fixes. **PSKR is high-volume machine ingest that destroyed well-formed grids** because a regex was stricter than the standard. **DXE is low-volume curated data that preserved malformed facts** because a human typed a grid nobody could check. A gate that only validates syntax catches the first and misses the second; a gate that only checks geography catches the second and misses the first.

So: **four gates, applied in order, at every boundary where a grid enters the lab.** A grid passes only if it clears all four, and the outcome of each is stored rather than acted on silently.

| Gate | Asks | Failure it closes |
| --- | --- | --- |
| 1 · Syntax | Is it a valid ADIF `GridSquare` / `GridSquareExt` / `GridSquareList`? | The PSKR regex — 6.75 B pairs erased for being uppercase, 8/10-character, or lowercase |
| 2 · Geometry | Does it fall inside the claimed DXCC entity's bounds? | The Bouvet `JD16` class — well-formed, \~100 km wrong |
| 3 · Self-consistency | Does the stated grid match one derived from the same source's coordinates? | The QSL-manager address, and a source disagreeing with itself |
| 4 · Observation | Is it contradicted by the station's own spots in our data? | A declaration no transmission supports — the RI1FJL check, run as a test and never as a substitution |

### The three rules that make the gates hold

**Never drop, never NULL, never reject-and-discard.** A field that fails gate 1 is stored *as received*, with a validity flag and the reason it failed. This single rule is what would have prevented the seven-month erasure: the collector's regex did not record a rejection, it produced an empty field indistinguishable from a station that sent nothing. An invalid grid we can see is a data-quality metric; an invalid grid we deleted is 6.75 billion rows left with no usable pair, of which only the 2,805,821,017 missing exactly one end can be recovered at all.

**Store at full precision; derive the shorter forms.** The received field is the stored fact, and `grid_4` / `grid_6` are derived from it. Storing a truncated grid discards the subsquare permanently and cannot be undone — the same defect class as integer MHz, and the same class as storing a grid instead of coordinates.

**Validate case-insensitively; normalise on store.** ADIF's grid fields are case-insensitive on input. Both the PSKR regex (uppercase subsquares rejected) and the contest ingester (safe only because it happened to call `strings.ToUpper()` first) turned on this, and one of them got it right by accident. Normalisation belongs in the shared validator, not in whether each ingester remembered.

### Where each gate runs

|  | PSKR and the spot sources | DXE and the reference tier |
| --- | --- | --- |
| Gate 1 | At ingest, per row, on the raw field | On edit, before the row commits |
| Gate 2 | Not applicable — a spot claims no entity | On edit, against `entity_bounds` — blocking |
| Gate 3 | Not applicable — no coordinates are reported | On edit, per source, `grid_<src>` vs `grid_calc_<src>` |
| Gate 4 | As a periodic audit over accumulated spots | On edit, and re-run when new spots arrive |
| Continuous | Invalid-rate and null-rate per field in the conformance harness, thresholds declared in the spec | Same harness, plus the FK into `adif` |

The asymmetry is the point. For PSKR the contract is **one validator called at ingest plus a standing rate check**, because volume means the only affordable defence is a threshold that trips in hours. For DXE the contract is **all four gates as blocking constraints on a human edit**, because 346 rows can afford to be checked completely and a wrong row there poisons every validation built on it.

### What this requires that does not exist yet

- A **shared grid validator** — one implementation, called by every ingester and by the reference-tier editor. Six private regexes is the defect; six callers of one validator is the fix.
- `entity_bounds` — listed in the candidate dimensions above, and gate 2 is what makes it load-bearing rather than nice to have.
- **Invalid-rate thresholds per field**, declared in the spec so the harness measures against a number rather than a hunch.
- **Nothing for the grids already blanked.** They were destroyed rather than flagged, so there is no flag to backfill from and no decision to take. The history is lossy and stays lossy; the gates protect everything from here.

## Decisions taken here, and the tasks they leave

Each item below was an open question in the first draft. Every one now carries a decision and an owner. **Nothing in this section is waiting on Judge** — they are engineering calls that belong to whoever owns the surface, or they are tasks with a name against them.

### Where the source of truth lives, in git terms

The TSV is currently the SOT and it is version-controlled. Moving to PG-1 moves the SOT out of git — a database is not diffable, not PR-reviewable, and not in the commit trail, which is the lab's whole traceability argument.

The working proposal was "Postgres is the working master, and every change dumps back to a file in git." That **creates two masters**, and a proposal with two masters is not yet a decision. It needs three answers: which side wins when they drift, what detects the drift, and on what cadence. The foreign-key and versioning proposals above all assume this resolved.

**Decided: PostgreSQL is the master. Git holds a read-only export, not a second copy of the truth.** Every change dumps to a file in git, and CI diffs a fresh dump against the committed file and fails on any drift. That resolves the two-masters objection rather than living with it — git is the audit trail and the rebuild path, and it has no authority to disagree. When the dump and the file differ, the dump is right and the failing CI job is the detector. Owner: Watson to specify the export and the CI check; Bob to wire it.

### Which ADIF version a lookup selects, and whether rows re-pin

From the versioning section: two coexisting versions means every ClickHouse join must name one, and every `ionis` row is pinned to one. The questions were whether a lab-wide current pointer exists, is re-pinning triggered by a release or by a migration, and what happens to a row referencing a value 3.1.8 retires.

**Decided: one lab-wide current-version pointer. Rows pin at write, and re-pin only by explicit migration.** A ClickHouse join reads the pointer rather than naming a version per query, so there is one place to change and one answer at any moment. A row keeps the `adif_version` it was written against; nothing re-pins silently. A release that retires a value some `ionis` row references does not cascade — it raises a migration, which is a reviewed change with a diff, exactly as the versioning section argues. Owner: Watson to specify; Bob to implement the pointer.

### Who writes

Consumers read. But validated grids and reconciled dates must be written by a human or by Watson, which means either an authenticated write path in the API or direct PG access for the editor. Read-only API plus editor-writes-to-PG is simpler and keeps the API surface small.

**Decided: read-only API, and the editor writes directly to PG.** It keeps the API surface small and puts no write path on the internet-facing side. Owner: Watson to specify the editor's write path; Bob to provision its PG role.

### The IONIS-AI spec document

Our own document defining which fields we add, which ADIF value each builds on, and which ADIF version it tracks. It belongs in `ionis-core` beside the DDL, and it is the artifact that makes *"ADIF 3.1.7 + IONIS-AI extension"* a claim someone can check rather than a label.

**Not a decision — a task. Owner: Watson.** This document is the design record; the spec is the separate normative artifact it argues for, and writing it is scheduled work, not a question.

### WSPR frequency precision

`wspr.bronze.frequency` is integer MHz; all 3,485,092,305 rows on 20 m read `14`. `pskr.capture_bronze.f` stores Hz. Same concept, two units, three orders of magnitude apart — and the ADIF band-edge validation cannot run on WSPR because integer MHz cannot distinguish 14.000–14.350 from 14.351–14.999.

**Closed 2026-09-26 — confirmed as our defect, and worse than precision loss.** Verified against `/mnt/wspr-data/wsprspots-2026-05.csv.gz`: the archive carries full decimal MHz (`14.0971`, `14.097046`, `10.140147`), all 200,000 sampled rows decimal, 303 distinct 20 m values in a 500,000-row slice.

`wspr.bronze.frequency` is declared `UInt64` and holds whole MHz — **471 distinct values across 12.68 billion rows**. The column type cannot represent the source's value at all, so this is not a rounding choice but a field that was redefined at ingest.

The sharper consequence: **239,246,047 rows store frequency `0`**, because every band below 1 MHz truncates to zero. 630 m and 2200 m do not merely lose precision, they lose their frequency entirely — and `0` is indistinguishable from a missing reading, which is the sentinel defect this record bans. Recovering it requires a reload from the raw archive; nothing in the stored column can be repaired in place.

**Done 2026-09-26 — Watson ran it.** One raw archive file settled it: the source carries full decimal MHz, so the truncation is ours. The follow-on is no longer a check but a reload, and it belongs to the WSPR bronze work rather than to this record.

### The 309-log Cabrillo survey gap

Carried from the Cabrillo section: 824,553 counted against 824,862 on disk. Needs a cause, not a reconciliation by rounding.

**Closed 2026-09-26.** Bob reconciled it to the log: 824,715 with a `START-OF-LOG` line plus 147 without one at line start equals 824,862. The shortfall was a truncated version listing — 45 distinct version strings exist and only the top 8 were shown — not lost files.

**Not a decision — a task. Owner: Bob.** The survey walk is his, so the answer is whether the 309 are unreadable headers or files the walk skipped. The Cabrillo profile does not cite these counts until it is known.

### Open tasks, with owners

No item in this table needs a decision. Each has a name against it and closes on work, not on a call from Judge.

| Task | Owner | State |
| --- | --- | --- |
| WSPR raw-archive precision check | Watson | **Done 2026-09-26.** Archive carries decimal MHz; truncation is ours. Leaves a *reload*, owned by the WSPR bronze work |
| 309-log Cabrillo survey gap | Bob | **Done 2026-09-26.** 824,715 + 147 = 824,862; 45 version strings, 8 listed |
| New census status code for the three `SWL` rows | Bob | Open — `classified-v2.tsv` must stop coding a correct-ADIF-field-we-lack as `M`, the mutated defect list |
| The IONIS-AI spec document | Watson | Open — the normative spec in `ionis-core` beside the DDL, with requirement IDs this record can cite |
| Existing invalid grids | — | Nothing to do. They were blanked, not flagged, so there is no flag to backfill from. **The history is lossy and stays lossy** |

One thing deliberately absent from that table: the shared grid validator, the spot ID at ingest and the `entity_bounds` dimension are **build work**, not design decisions. This record specifies them; it does not carry their status. They are tracked as:

| Issue | Work |
| --- | --- |
| `ionis-apps#53` | Shared grid validator — replace the two private Maidenhead regexes, never blank on failure |
| `ionis-apps#54` | Spot ID at ingest, so the grid-recovery table has a reliable join key |
| `ionis-core#31` | `entity_bounds` dimension — mechanise the grid-inside-the-entity test (gate 2) |

## Record provenance

Participants: Judge, Bob, Watson. Adversarial review: Patton, 15 findings tagged P1–P3, raised against the previous HTML version of this record and carried here as anchored comments.

Catalog backups taken before any reconciliation: `dxpedition-catalog.20260926T154821Z.tsv` and `dxpedition.catalog_backup_20260926T154821Z`.

## Work order and open items

Order (Judge, 2026-09-26): this spec, then the PG-1 database initialised from it, then the remaining source work. Status is tracked in GitHub, IONIS-AI/ionis-apps#42 and its children. This section replaces the retired Bronze Work Queue page.

| Item | Status | Tracked in |
| --- | --- | --- |
| ADIF tier on PG-1: `adif` schema, 3.1.6 and 3.1.7 loaded, current version 3.1.7 | Built and tested; awaiting review, database onboarding and load | ionis-core#33 |
| `ionis-db-init` creates and validates schemas from this spec, ClickHouse and PostgreSQL | Requirement; not yet written into this record | this record |
| PSKR P8 conformance check (Watson) | Not run | ionis-apps#37 |
| RBN archive-to-bronze audit, then keep every record | After spec and database init | ionis-apps#38 |
| Contest download: scheduled or manual | After spec and database init | ionis-apps#40 |

Done 2026-09-26: PSKR cutover and retirement (ionis-apps 4.9.0, ionis-core 4.5.3), housekeeping #41, adif-mcp 1.1.1 and 1.1.2 (adif-mcp#8 closed: ADIF publishes 25 enumerations; Country is a view of DXCC\_Entity\_Code).

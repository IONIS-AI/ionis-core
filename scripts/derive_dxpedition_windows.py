#!/usr/bin/env python3
"""Derive DXpedition operating windows from our own spot data.

WHY THIS EXISTS

dxpedition.catalog is a join key. rbn.dxpedition_paths and its siblings match
2.37B RBN spots against 332+ hand-entered (callsign, start_ts, end_ts) tuples, so
a wrong window does not produce a missing row — it produces confidently wrong path
matches. Until now those windows were transcribed by hand from GDXF free text,
which publishes a year and a day count but no timestamps at all.

The spots know when the operation ran. Ask them.

METHOD

For each callsign, take the daily spot histogram, set a threshold at 2% of the
peak day, and group days into runs. A day below threshold does not end a run; a
gap of more than two calendar days does.

Then select the run carrying the MOST SPOTS — not the longest one.

That distinction is Hopper's finding on ionis-core#2 and it is the whole
correctness of this script. Selecting by length lets a long low-level tail
displace the operation: with a 10,000/day peak the threshold is 200, so twenty
days of 201 spots/day outrank fourteen days of 10,000. An operation is where the
mass is, not where the longest above-threshold stretch is. No current row changes
under either rule — all fourteen 2026 entries select the same run — which is
exactly why it was worth fixing before one didn't.

VALIDATION

Every derived duration is compared against GDXF's independently stated day count.
Agreement is evidence the method works on that row; disagreement is reported, not
silently accepted. 11 of 14 agreed on the 2026 pass. 3Y0K derived 2026-03-01..03-14
at 100,238 spots against the dxpedition-demo's independent 100,292 — two unrelated
code paths within 0.05%.

    ./derive_dxpedition_windows.py --year 2026
    ./derive_dxpedition_windows.py --self-test
"""

import argparse
import datetime
import json
import sys
import urllib.request

CH = "http://192.168.1.90:8123/"
THRESHOLD_FRACTION = 0.02
MAX_GAP_DAYS = 2


def runs_above_threshold(days, threshold, max_gap=MAX_GAP_DAYS):
    """Group (date, count) pairs into runs. A sub-threshold day does not break a
    run; only a date gap larger than max_gap does."""
    out, cur = [], []
    for d, c in days:
        if c < threshold:
            continue
        if cur and (d - cur[-1][0]).days > max_gap:
            out.append(cur)
            cur = []
        cur.append((d, c))
    if cur:
        out.append(cur)
    return out


def select_run(runs):
    """The operation is the run carrying the most spots.

    NOT the longest run. See the module docstring — selecting by length lets a
    long low-level tail displace a short intense operation.
    """
    return max(runs, key=lambda r: sum(c for _, c in r)) if runs else None


def derive(days):
    """(start_date, end_date, spots) for the operation, or None."""
    if not days:
        return None
    peak = max(c for _, c in days)
    chosen = select_run(runs_above_threshold(days, peak * THRESHOLD_FRACTION))
    if not chosen:
        return None
    return chosen[0][0], chosen[-1][0], sum(c for _, c in chosen)


def self_test():
    D = datetime.date
    def series(start, n, per):
        return [(start + datetime.timedelta(days=i), per) for i in range(n)]

    fails = 0

    # Hopper's counterexample, ionis-core#2. The tail is LONGER; the operation is
    # DENSER. Selecting by length picks the tail and the window is wrong by weeks.
    tail = series(D(2026, 1, 1), 20, 201)
    op = series(D(2026, 3, 1), 14, 10000)
    got = derive(tail + [(D(2026, 2, 1), 0)] + op)
    if got[:2] != (D(2026, 3, 1), D(2026, 3, 14)):
        print(f"  FAIL long-tail-vs-dense: got {got[:2]}, want the 14 dense days")
        fails += 1

    # A single stray day far outside must not extend the window. This is the bug
    # the first implementation had: 3Y0K stretched to 32 days by one day at 234
    # spots three weeks after the operation ended.
    got = derive(series(D(2026, 3, 1), 14, 8000) + [(D(2026, 4, 1), 234)])
    if got[:2] != (D(2026, 3, 1), D(2026, 3, 14)):
        print(f"  FAIL stray-day: got {got[:2]}, want 03-01..03-14")
        fails += 1

    # A quiet day INSIDE an operation must not split it.
    inner = series(D(2026, 3, 1), 5, 9000) + [(D(2026, 3, 6), 3)] + series(D(2026, 3, 7), 5, 9000)
    got = derive(inner)
    if got[:2] != (D(2026, 3, 1), D(2026, 3, 11)):
        print(f"  FAIL quiet-day-inside: got {got[:2]}, want 03-01..03-11")
        fails += 1

    # Empty input yields no window, never a default one.
    if derive([]) is not None:
        print("  FAIL empty: must return None")
        fails += 1

    # A single day is a legitimate answer, not an error.
    if derive([(D(2026, 3, 1), 5000)])[:2] != (D(2026, 3, 1), D(2026, 3, 1)):
        print("  FAIL single-day")
        fails += 1

    print("  self-test: all pass" if not fails else f"  self-test: {fails} FAILED")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", type=int)
    ap.add_argument("--callsign")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return 1 if self_test() else 0
    if not a.callsign:
        print("need --callsign (or --self-test)", file=sys.stderr)
        return 2
    sql = (f"SELECT toDate(timestamp) d, count() c FROM pskr.bronze "
           f"WHERE upper(sender_call) = '{a.callsign.upper()}' GROUP BY d ORDER BY d FORMAT TSV")
    raw = urllib.request.urlopen(CH, data=sql.encode(), timeout=120).read().decode().strip()
    days = [(datetime.date.fromisoformat(l.split("\t")[0]), int(l.split("\t")[1]))
            for l in raw.splitlines() if l]
    r = derive(days)
    print(json.dumps({"callsign": a.callsign, "start": str(r[0]), "end": str(r[1]),
                      "days": (r[1] - r[0]).days + 1, "spots": r[2]} if r
                     else {"callsign": a.callsign, "window": None}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

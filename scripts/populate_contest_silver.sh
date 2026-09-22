#!/bin/bash
# =============================================================================
# populate_contest_silver.sh — contest.bronze minus exact duplicate rows
# =============================================================================
#
# Run after every contest reload. Rebuilds from bronze, so it is derived state and
# safe to drop and recreate at any time.
#
# THE RULE, in one line: a duplicate is an EXACT match on every column.
#
# That is deliberately narrow. A repeat contact between the same two stations on the
# same band and mode at a DIFFERENT time is real, common, and worth keeping -- hams
# work dupes on purpose when an exchange was busted. Those differ in `timestamp` and
# survive. What goes is rows identical in all twelve columns, which no amount of
# operating can produce.
#
# Usage:
#   bash populate_contest_silver.sh
#   CH_HOST=10.60.1.1 bash populate_contest_silver.sh
# =============================================================================
set -e

# Site configuration and shared defaults.
# shellcheck source=/dev/null
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-localhost}"

Q() { clickhouse-client --host "$CH_HOST" --query "$1"; }

BEFORE=$(Q "SELECT count() FROM contest.bronze")
echo "============================================================"
echo "Populating contest.silver from contest.bronze"
echo "Host: ${CH_HOST}   bronze rows: ${BEFORE}"
echo "============================================================"

Q "TRUNCATE TABLE IF EXISTS contest.silver"

# DISTINCT over every column. Not GROUP BY -- there is nothing to aggregate, and
# DISTINCT states the intent: keep one of each identical row.
#
# Done per contest rather than in one pass: a single DISTINCT over 384M rows needs
# more memory than the server will give a query, and failing halfway through a
# rebuild is worse than taking eighteen passes.
for C in $(Q "SELECT DISTINCT contest FROM contest.bronze ORDER BY contest"); do
    Q "INSERT INTO contest.silver
       SELECT DISTINCT timestamp, frequency, band, mode, call_1, call_2,
              rst_sent, exch_sent, rst_rcvd, exch_rcvd, contest, source
       FROM contest.bronze WHERE contest = '${C}'"
    printf "  %-16s %s\n" "$C" "$(Q "SELECT count() FROM contest.silver WHERE contest='${C}'")"
done

AFTER=$(Q "SELECT count() FROM contest.silver")
REMOVED=$((BEFORE - AFTER))
echo "------------------------------------------------------------"
echo "bronze:  ${BEFORE}"
echo "silver:  ${AFTER}"
echo "removed: ${REMOVED} exact duplicate row(s)"

# A rebuild that removes nothing, or removes a lot, both deserve a look. The
# 2026-09-22 reload removed 161,369 of 384,429,893 -- 0.042%. An order of magnitude
# either side of that means something changed upstream, and silently rebuilding on
# top of it is how a corpus drifts.
PCT=$(Q "SELECT round(100.0 * ${REMOVED} / ${BEFORE}, 4)")
echo "         ${PCT}% of bronze (2026-09-22 baseline: 0.0420%)"
if [ "$REMOVED" -eq 0 ]; then
    echo "NOTE: nothing removed. Either the corpus is clean now or the rule stopped matching."
fi

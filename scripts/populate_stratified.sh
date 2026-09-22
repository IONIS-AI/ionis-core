#!/bin/bash
set -e

# Site configuration and shared defaults. Sourced rather than redeclared: this line
# used to be CH_HOST="${CH_HOST:-192.168.1.90}" in each of sixteen scripts, so one
# host's address was the shipped default sixteen times over and a site had sixteen
# places to change it. ionis-env reads /etc/ionis-core/ionis-core.conf first, so a
# site sets it once. An explicit CH_HOST in the environment still wins.
# shellcheck source=/dev/null
[ -r /usr/bin/ionis-env ] && . /usr/bin/ionis-env
CH_HOST="${CH_HOST:-localhost}"
BANDS=(102 103 104 105 106 107 108 109 110 111)
BAND_NAMES=("160m" "80m" "60m" "40m" "30m" "20m" "17m" "15m" "12m" "10m")

# SSN quintile boundaries: [46, 76, 124, 153]
Q_LABELS=("Q1:SSN<=46" "Q2:46<SSN<=76" "Q3:76<SSN<=124" "Q4:124<SSN<=153" "Q5:SSN>153")
Q_CONDITIONS=(
    "<= 46"
    "> 46 AND sol.ssn <= 76"
    "> 76 AND sol.ssn <= 124"
    "> 124 AND sol.ssn <= 153"
    "> 153"
)
Q_NUMS=(1 2 3 4 5)

TOTAL=0
START_TIME=$(date +%s)

echo "==========================================================="
echo "Phase 5.1: Populating wspr.gold_stratified"
echo "Target: 10M rows (10 bands x 5 quintiles x 200K)"
echo "==========================================================="
echo ""

for bi in "${!BANDS[@]}"; do
    band=${BANDS[$bi]}
    bname=${BAND_NAMES[$bi]}
    
    for qi in "${!Q_NUMS[@]}"; do
        qnum=${Q_NUMS[$qi]}
        qlabel=${Q_LABELS[$qi]}
        qcond=${Q_CONDITIONS[$qi]}
        
        slot=$(( bi * 5 + qi + 1 ))
        printf "[%2d/50] Band %d (%s) %s ... " "$slot" "$band" "$bname" "$qlabel"
        
        T0=$(date +%s%N)
        
        clickhouse-client --host "$CH_HOST" --query "
            INSERT INTO wspr.gold_stratified
            SELECT s.snr, s.distance, s.band,
                   toHour(s.timestamp) AS hour, toMonth(s.timestamp) AS month,
                   s.azimuth,
                   toString(s.grid) AS tx_grid,
                   toString(s.reporter_grid) AS rx_grid,
                   sol.ssn, sol.sfi_observed, sol.kp,
                   ${qnum} AS ssn_quintile
            FROM wspr.bronze s
            INNER JOIN solar.silver sol
    ON toStartOfInterval(s.timestamp, INTERVAL 3 HOUR) = sol.observed_at
            WHERE s.band = ${band}
              AND s.timestamp >= '2020-01-01' AND s.timestamp < '2026-02-04'
              AND s.snr BETWEEN -35 AND 25
              AND s.distance BETWEEN 500 AND 18000
              AND length(toString(s.grid)) >= 4
              AND length(toString(s.reporter_grid)) >= 4
              AND sol.ssn ${qcond}
            ORDER BY cityHash64(toString(s.timestamp))
            LIMIT 200000
            SETTINGS max_execution_time=600, max_memory_usage=40000000000
        "
        
        T1=$(date +%s%N)
        ELAPSED=$(( (T1 - T0) / 1000000 ))
        TOTAL=$(( TOTAL + 200000 ))
        printf "done (%d.%ds) | cumulative: %s\n" "$((ELAPSED/1000))" "$((ELAPSED%1000/100))" "$(printf '%d' $TOTAL)"
    done
done

END_TIME=$(date +%s)
WALL=$(( END_TIME - START_TIME ))

echo ""
echo "==========================================================="
echo "Population Complete"
echo "==========================================================="
echo "Total rows: $TOTAL"
echo "Wall time: ${WALL}s"
echo "==========================================================="

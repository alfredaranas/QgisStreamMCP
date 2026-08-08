#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# QgisStreamMCP — autosave loop (B13 + B18)
# ═══════════════════════════════════════════════════════════════════
# Every hour:
#   1. Snapshot current QGIS project (if any) into /archive/system/qgis/
#      with timestamp filename.
#   2. Append a line to /archive/system/qgis/qgis_session_history.log
#      so audit / rollback can see what the AI did this hour.
# Retention: keep the most recent 24 hourly + 30 daily snapshots.
#
# Runs as a supervisord-managed daemon. Falls back gracefully when
# /archive isn't mounted (e.g. local-only test).
# ═══════════════════════════════════════════════════════════════════

set -e
ARCHIVE_BASE="${QGIS_ARCHIVE:-/archive/system/qgis}"
mkdir -p "$ARCHIVE_BASE/hourly" "$ARCHIVE_BASE/daily" 2>/dev/null || {
    echo "[autosave] /archive not writable; autosave disabled" >&2
    # Sleep forever so the supervisor program stays "running" (no restart loop)
    exec sleep infinity
}
touch "$ARCHIVE_BASE/qgis_session_history.log"

HOURLY_KEEP="${QGIS_AUTOSAVE_HOURLY_KEEP:-24}"
DAILY_KEEP="${QGIS_AUTOSAVE_DAILY_KEEP:-30}"

snapshot_now() {
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    # QGIS bridge writes /data/jobs/active.qgz whenever it saves; copy it if present.
    if [ -f /data/jobs/active.qgz ]; then
        cp /data/jobs/active.qgz "$ARCHIVE_BASE/hourly/project-$ts.qgz"
        echo "[autosave] snapshot $ts" >> "$ARCHIVE_BASE/qgis_session_history.log"
    fi
    # Daily rollup: keep just the most recent daily snapshot per local-date.
    local day
    day="$(date -u +%Y%m%d)"
    if [ ! -f "$ARCHIVE_BASE/daily/project-$day.qgz" ] && [ -f /data/jobs/active.qgz ]; then
        cp /data/jobs/active.qgz "$ARCHIVE_BASE/daily/project-$day.qgz"
    fi
}

enforce_retention() {
    # Hourly: drop everything beyond the most recent N
    ls -1t "$ARCHIVE_BASE/hourly"/project-*.qgz 2>/dev/null | \
        tail -n +$((HOURLY_KEEP + 1)) 2>/dev/null | xargs -r rm -f
    # Daily: drop everything beyond the most recent N
    ls -1t "$ARCHIVE_BASE/daily"/project-*.qgz 2>/dev/null | \
        tail -n +$((DAILY_KEEP + 1)) 2>/dev/null | xargs -r rm -f
}

# First run: snapshot immediately, then loop every hour
snapshot_now
enforce_retention
while true; do
    sleep 3600
    snapshot_now
    enforce_retention
done

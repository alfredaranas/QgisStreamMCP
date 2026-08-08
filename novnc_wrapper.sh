#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# noVNC wrapper — read $QGIS_VNC_HTTP_PASSWORD at exec time so supervisord
# config doesn't need %(ENV_X)s interpolation (which breaks if the operator
# forgets to pass the env at startup — common during image testing).
# ═══════════════════════════════════════════════════════════════════

set -e
VNC_PASSWORD="${QGIS_VNC_HTTP_PASSWORD:-}"
if [ -z "$VNC_PASSWORD" ]; then
    echo "[novnc] WARNING: QGIS_VNC_HTTP_PASSWORD not set — disabling HTTP basic auth layer. VNC password still protects the session." >&2
    exec /usr/bin/websockify --web=/opt/novnc 6080 localhost:5900
fi

# Colon in the password would break the qgis:PASSWORD auth-source format —
# already proven to work in f2ccb89 (commit 2026-07-31). The format spec is
# "user:password" and websockify parses only on the first colon.
exec /usr/bin/websockify \
    --web=/opt/novnc \
    --web-auth \
    --auth-plugin=websockify.auth_plugins.BasicHTTPAuth \
    --auth-source="qgis:${VNC_PASSWORD}" \
    6080 localhost:5900

#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# QgisStreamMCP — secondary MCP server (nkarasiak/qgis-mcp @ :8765)
# ═══════════════════════════════════════════════════════════════════
# Runs the upstream qgis-mcp MCP server on top of the in-QGIS plugin
# (loaded at QGIS startup from the auto-discovered plugin path). Started
# AFTER QGIS is up so the plugin's socket has time to bind.
#
# The qgis_mcp_plugin/server.py binds a TCP socket (default :9876) inside
# QGIS at plugin load. The qgis_mcp Python server (in third_party/) then
# talks to QGIS over that socket and exposes 100+ LLM-friendly MCP tools
# over a streamable-HTTP MCP transport on $QGIS_MCP_ADDON_PORT (default 8765).
#
# Auth (defense in depth): same bearer scheme as api_server.py. Set
# QGIS_MCP_ADDON_TOKEN in the .env. If unset, server starts but logs a
# warning — when AUTH_TOKENS is also unset upstream, the server refuses
# connections from non-loopback peers.
# ═══════════════════════════════════════════════════════════════════

set -e
PORT="${QGIS_MCP_ADDON_PORT:-8765}"
export QGIS_MCP_PLUGIN_PORT="${QGIS_MCP_PLUGIN_PORT:-9876}"
export QGIS_MCP_HOST="${QGIS_MCP_HOST:-127.0.0.1}"
# Pass through any auth tokens so the upstream server can require them
if [ -n "${QGIS_MCP_ADDON_TOKEN:-}" ]; then
    export QGIS_MCP_TOKEN="$QGIS_MCP_ADDON_TOKEN"
fi

# Wait for the in-QGIS socket to come up
echo "[qgis-mcp-addon] waiting for QGIS plugin socket on ${QGIS_MCP_HOST}:${QGIS_MCP_PLUGIN_PORT}..."
for i in $(seq 1 60); do
    if ss -tlnp 2>/dev/null | grep -q ":${QGIS_MCP_PLUGIN_PORT} "; then
        echo "[qgis-mcp-addon] QGIS plugin socket up after ${i}s"
        break
    fi
    sleep 2
done
if ! ss -tlnp 2>/dev/null | grep -q ":${QGIS_MCP_PLUGIN_PORT} "; then
    echo "[qgis-mcp-addon] WARNING: QGIS plugin socket never came up; addon server will retry on each request" >&2
fi

cd /app/third_party/qgis_mcp_server || {
    echo "[qgis-mcp-addon] FATAL: third_party/qgis_mcp_server not installed" >&2
    exit 1
}
exec python3 -m qgis_mcp.server \
    --host "${QGIS_MCP_HOST}" \
    --port "${PORT}" \
    --plugin-port "${QGIS_MCP_PLUGIN_PORT}" \
    --plugin-host "${QGIS_MCP_HOST}"

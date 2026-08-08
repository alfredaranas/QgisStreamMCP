# QGIS_MCP Rebuild — Audit & Runbook
Updated: 2026-08-06 | Owner: demiurge

## 1. Why the first two attempts failed
Two agent runs (run_95988032, run_5afab42b) were cut off by tool-iteration
caps mid-build. Neither completed `docker build`. Root cause of the OUTAGE was
separate and worse:

**docker-compose.yml was corrupted.** Four env names were clobbered to
`${QGIS...?set X in .env}` — the agent's own secret-masking logic wrote into
the file it was editing. `docker compose config` failed, so the container
could not start at all. Repaired 2026-08-06 (anchor-guarded patch, backup in
/tmp/compose.bak.*).

LESSON: never let a masking layer touch files being written. Validate with
`docker compose config` after ANY compose edit.

## 2. Ground truth (verified 2026-08-06, post-restore)
- Container: UP, healthy, running rollback image 475194b5a080
- Ports: 6080/8113/8135/8765 -> 100.92.239.85 (Tailscale-only)
- MCP: container 8100 -> host 100.92.239.85:8130 (Tailscale-only)
- Auth gates: REST 401, noVNC 401 — hardening (f2ccb89) INTACT
- Rollback image: qgis-streammcp:rollback-pre-rebuild-20260806

### Known deviations / open items
- `/health` returns 401 (unintended; docker healthcheck unaffected, internal)
- UNRELATED: trading-brain-mcp holds 0.0.0.0:8100 LAN-exposed (different domain)
- SOUL §4.1 says QGIS 3.44.12; new Dockerfile targets **3.34 LTR** — DOWNGRADE,
  undocumented. Decide + update SOUL before promoting.

## 3. Risk register for the rebuild
| # | Risk | Mitigation |
|---|---|---|
| R1 | Agent cutoff mid-build | Detached `ops/rebuild.sh` via setsid; survives |
| R2 | Hard apt pins rotted in PPA | Build fails fast; unpin and retry |
| R3 | QGIS 3.44->3.34 downgrade | Verify point-cloud pipeline before promote |
| R4 | Live-mounted ./src overrides image | src must stay import-safe (lazy pdal import) |
| R5 | Hardening lost in rebuild | Script gates on 401/401/tailscale-bind, auto-rollback |
| R6 | Container left down on failure | Auto-rollback retags + restarts old image |

## 4. Phasing (decided 2026-08-06)
- **Phase 1** — PDAL + GRASS + bridge fix (A1/A3/A4/A5) + helpers/tools
- **Phase 2** — GDAL 3.11, SAGA, OTB, open3d, addon MCP (A2/B2/B3/B5/B6)
Rationale: phase 2 is the heavy/risky half; a phase-2 failure must not cost
the phase-1 PDAL capability.

## 5. Run it
    cd ~/Projects/qgis-streammcp
    setsid nohup ops/rebuild.sh 1 > /tmp/qgis_rebuild.out 2>&1 < /dev/null &
    tail -f ~/logs/qgis_rebuild_1_*.log

Script aborts + AUTO-ROLLS BACK on: build fail, unhealthy container,
REST/noVNC auth gate open, MCP not Tailscale-bound.

## 6. Verification matrix (script runs these)
pdal CLI+version | python pdal import | gdal version | provider list + alg
count | REST 401 | noVNC 401 | MCP bound 100.92.239.85:8130 | container healthy

## 7. NOT done yet (do not claim)
- End-to-end Sentinel MCP workflow verification post-hardening
- LAS->COPC conversion tested on real CZMIL file (needs EPSG:26918, no
  embedded CRS in CZMIL LAS)
- B1 LAStools: SKIPPED (proprietary licensing)

## 8. Post-rebuild fixes (2026-08-08) — all verified live

| Defect | Cause | Fix | Verified |
|---|---|---|---|
| compose would not parse | agent secret-masking wrote `${QGIS...}` into the file | repaired 4 env names | `docker compose config` exit 0 |
| build died on pip pdal | no `python3-dev` (CMake needs Python headers) | added python3-dev + pybind11-dev | build passed |
| python-pdal unsatisfiable | bindings >=3.4 need PDAL>=2.7; PPA ships 2.6.2 | own layer, 3.3->3.2 fallback, NON-FATAL | build passed w/ [WARN] |
| pip could not upgrade typing_extensions | apt-installed, no RECORD file | `--ignore-installed typing_extensions packaging` | build passed |
| las_to_copc always failed | `compression` passed as positional PDAL STAGE -> filters.LAZ | removed; extension selects COPC writer | 189,624 pts converted |
| 3 processing scripts unloadable | `processing.alg_factory_registry()` does not exist | removed; QGIS auto-discovers subclasses | all 3 register |
| scripts crashed when run | `parameterAsFileDestination` does not exist | -> `parameterAsFileOutput` | qgis_process run OK |
| helpers edits had no effect | helpers/ baked into image, not mounted | added bind mounts | fix live |
| Axes3D unavailable | apt python3-matplotlib shadows pip's mpl_toolkits | purge in Dockerfile | pending next build |
| model3 never loaded | file had no `children` — not a real model | moved to docs/drafts/ | no load errors |

### Verified capability (2026-08-08)
- pdal CLI 2.6.2; GDAL 3.11.4 CLI/python; GRASS + GDAL providers loaded
- CZMIL LAS (no embedded CRS) -> COPC with EPSG:26918 -> valid QgsPointCloudLayer
- `qgis_process run script:pdal_las_to_copc` end to end
- Security: REST 401, noVNC 401, MCP bound 100.92.239.85:8130

### Still open
- QGIS point cloud RENDERER draws nothing (extent box only) — matplotlib renders
  fine, so it is symbology, not data. Not yet root-caused.
- QGIS internally links libgdal.so.34 (3.8.4) while CLI/python use 3.11.4 —
  A2's in-QGIS COPC/LAS drivers NOT achieved. Would need QGIS from source.
- `/health` requires auth (unintended; docker healthcheck unaffected).
- python-pdal bindings absent by design — use pdal CLI via subprocess.
- Sentinel end-to-end MCP workflow verification STILL NOT DONE.
- Visual QC channel = public GitHub repo. Fine for renders; decide before
  routine survey data.

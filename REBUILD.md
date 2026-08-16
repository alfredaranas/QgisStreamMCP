# QGIS_MCP Rebuild — Audit & Runbook
Updated: 2026-08-08 (§9 added) | Owner: demiurge

> **Read §9 first.** Sections 1–8 are the contemporaneous audit trail and are
> kept verbatim. Several items in §2 and §8 were superseded later the same day.

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
  → **SUPERSEDED, see §9. It is localhost-exempt BY DESIGN, not unintended.**
- UNRELATED: trading-brain-mcp holds 0.0.0.0:8100 LAN-exposed (different domain)
- SOUL §4.1 says QGIS 3.44.12; new Dockerfile targets **3.34 LTR** — DOWNGRADE,
  undocumented. Decide + update SOUL before promoting.
  → **SUPERSEDED, see §9. No downgrade exists: qgis.org `ubuntu-ltr` now serves
    3.44.13. The Dockerfile comments were stale, not the behaviour.**

## 3. Risk register for the rebuild
| # | Risk | Mitigation |
|---|---|---|
| R1 | Agent cutoff mid-build | Detached `ops/rebuild.sh` via setsid; survives |
| R2 | Hard apt pins rotted in PPA | Build fails fast; unpin and retry |
| R3 | QGIS 3.44->3.34 downgrade | Verify point-cloud pipeline before promote |
| R4 | Live-mounted ./src overrides image | src must stay import-safe (lazy pdal import) |
| R5 | Hardening lost in rebuild | Script gates on 401/401/tailscale-bind, auto-rollback |
| R6 | Container left down on failure | Auto-rollback retags + restarts old image |

> R6 was real but **incompletely mitigated** — see §9, the rollback target
> predated the PDAL work and silently removed it.

## 4. Phasing (decided 2026-08-06)
- **Phase 1** — PDAL + GRASS + bridge fix (A1/A3/A4/A5) + helpers/tools
- **Phase 2** — GDAL 3.11, SAGA, OTB, open3d, addon MCP (A2/B2/B3/B5/B6)
Rationale: phase 2 is the heavy/risky half; a phase-2 failure must not cost
the phase-1 PDAL capability.

> In practice the Dockerfile is monolithic, so the phase argument does not
> split the build. Both phases shipped in one image.

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
- End-to-end Sentinel MCP workflow verification post-hardening → **DONE, §9**
- LAS->COPC conversion tested on real CZMIL file (needs EPSG:26918, no
  embedded CRS in CZMIL LAS) → **DONE, 189,624 pts, §8**
- B1 LAStools: SKIPPED (proprietary licensing) — still skipped

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
| Axes3D unavailable | apt python3-matplotlib shadows pip's mpl_toolkits | purge in Dockerfile | **THIS FIX WAS WRONG — see §9** |
| model3 never loaded | file had no `children` — not a real model | moved to docs/drafts/ | no load errors |

### Verified capability (2026-08-08)
- pdal CLI 2.6.2; GDAL 3.11.4 CLI/python; GRASS + GDAL providers loaded
- CZMIL LAS (no embedded CRS) -> COPC with EPSG:26918 -> valid QgsPointCloudLayer
- `qgis_process run script:pdal_las_to_copc` end to end
- Security: REST 401, noVNC 401, MCP bound 100.92.239.85:8130

### Still open  →  **SUPERSEDED BY §9**
- QGIS point cloud RENDERER draws nothing — **RESOLVED, §9**
- QGIS internally links libgdal.so.34 (3.8.4) — **still true, still low value**
- `/health` requires auth (unintended) — **NOT a defect, §9**
- python-pdal bindings absent by design — **still true**
- Sentinel end-to-end MCP workflow verification STILL NOT DONE — **DONE, §9**
- Visual QC channel = public GitHub repo — **still true, still a live decision**

## 9. Closing findings (2026-08-08, later the same session)

Four of the six "Still open" items above were resolved hours after §8 was
written, and two new defects were found. §8 is left intact as the audit trail.

| Item | Status | Evidence |
|---|---|---|
| **Point cloud renderer "draws nothing"** | **NOT A BUG** | QGIS assigns `QgsPointCloudExtentRenderer` by default — its entire job is to draw the bounding box. That was the red dashed rectangle. Assigning `QgsPointCloudAttributeByRampRenderer` on Z renders correctly: 1711 vs 318 sampled non-background pixels, 4.7 KB → 24.6 KB, visually confirmed to match the matplotlib render of the same file. Commit `ce13227`. |
| **`/health` 401** | **BY DESIGN** | `api_server.py` (~L75) exempts `/health` for `127.0.0.1`/`::1` only — exactly as specified when the hardening was requested. Verified: 200 from container localhost, 401 from the tailnet, docker healthcheck green. External monitoring must send a bearer token or probe from inside the container. |
| **Sentinel end-to-end post-hardening** | **DONE, PASSED** | 49 MCP tools; `add_layer(provider=copc)` → point_count 189624, EPSG:26918, correct extent, re-checked via `QgsProject.mapLayers()`; `execute_python` OK; auth 200 with token, 401 without, 401 with a wrong token. **Caveat:** the run overlapped a ~90 s window in which auto-rollback had swapped in the pre-PDAL image, so Sentinel's *PDAL-missing* observations are artefacts of that window. The MCP/auth/add_layer path is image-independent and did pass. |
| **MCP :8130 auth** | **NOW REQUIRED** | A6 added `_MCPSecurityMiddleware` in `main_mcp.py` (~L2004), accepting `QGIS_API_TOKEN` or `QGIS_ELEVATED_TOKEN`, `/health` exempt. Verified 401 unauthenticated / 200 with token + valid JSON-RPC handshake. **Breaking change for every archon client** — Sentinel's config now carries an `Authorization` header and its SOUL §4.1 was corrected. |

### New defects found after §8

**1. The matplotlib purge broke the container.**
`apt-get purge python3-matplotlib` removed QGIS components with it; the rebuilt
image never became healthy and auto-rollback fired. The real problem is
narrower: apt's `mpl_toolkits` ships an `__init__.py`, making it a REGULAR
package that fully shadows pip's — so `PYTHONPATH`/`sys.path` reordering cannot
fix it either. Corrected in the Dockerfile to:

    RUN rm -rf /usr/lib/python3/dist-packages/mpl_toolkits \
        /usr/lib/python3/dist-packages/matplotlib-*-nspkg.pth

pip's copy provides axes_grid1 + axisartist + mplot3d, so nothing is lost.
Removing the directory alone leaves the stale `.pth` behind, which then raises
on every Python startup — hence the second path. **Verified by hand in the
running container; NOT yet proven through a clean build.**

**2. Auto-rollback silently stripped PDAL.**
The failed matplotlib build rolled back to `rollback-pre-rebuild-20260806`,
which **predates the PDAL work**. The rollback "succeeded" and the container
came up healthy — with pdal 2.6.2 and GDAL 3.11.4 gone. `ops/rebuild.sh` now
prefers `qgis-streammcp:last-known-good` (tagged to the verified
`build-20260807-045037`), falling back to the original snapshot only if that
tag is missing.

> **Rule:** a rollback target that predates a capability silently removes it.
> Assert the capability after rollback, not just container health.

**3. `qgis_healthcheck` reported a false `Processing=DEGRADED`.**
It probed `Processing.instance().providerRegistry()`, which is empty unless the
Processing framework is initialised in that process, while `qgis_process list`
showed `gdal:*` and `grass:*` present. Now prefers
`QgsApplication.processingRegistry()` with the old call as fallback. Verified
`Processing=OK`.

### State at session end (2026-08-08)
- Running image: `qgis-streammcp:build-20260807-045037`, also tagged `last-known-good`
- Container healthy; `PC-providers=OK | Processing=OK`
- Security: REST 401, noVNC 401, MCP 401 unauthenticated / 200 with token, all Tailscale-bound
- `Axes3D` restored, no startup warnings
- Fork clean and pushed

### Next
1. A clean rebuild to land the corrected matplotlib fix through a real build.
2. Bulk ingest — 623 LAS / 278.8 GB on jalbtcx04; `/archive` is 76% used, 5.4T free.
3. Monitoring with an authed `/health` probe.
4. Reboot survival — never observed.

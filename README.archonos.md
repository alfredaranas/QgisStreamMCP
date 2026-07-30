# ArchonOS deployment notes — QgisStreamMCP on Yoda

> **This repo is PRIVATE (`alfredaranas/qgis-streammcp-config`) and holds the
> deployed configuration.**
> The public fork (`alfredaranas/QgisStreamMCP`) does NOT contain it.
> A fresh clone of the public fork will be missing the `/archive` mount and the
> port remaps, and the container will come up unable to see any survey data.

## Repo layout — three remotes, on purpose

| Remote | Repo | Visibility | Holds |
|---|---|---|---|
| `origin` | `alfredaranas/QgisStreamMCP` | public fork | PR branches only |
| `upstream` | `nic01asFr/QgisStreamMCP` | public | the original project |
| `private` | `alfredaranas/qgis-streammcp-config` | **private** | `main` — the deployed branch |

`main` here is the deployed branch. Never push it to `origin` — it contains local
mount paths. Generic fixes go on a branch cut from `upstream/main`
(see PR https://github.com/nic01asFr/QgisStreamMCP/pull/2).

A patch copy also lives in the `archonos` repo at
`deploy/qgis-streammcp/0001-archonos-local-changes.patch` as a belt-and-braces backup.

## What this branch changes vs upstream

- **Dockerfile** — enables the GRASS processing provider (388 → 695 algorithms);
  adds the python analysis stack (pandas, geopandas, shapely, fiona, rasterio,
  h5py, netCDF4, laspy) via **apt, never pip** — pip would disturb the
  numpy/scipy that QGIS's compiled bindings link against.
- **docker-compose.yml** — port remaps + the RAID6 `/archive` bind mount.
- **src/qgis_bridge.py** — point cloud support in `add_layer` (also upstreamed).

## Ports (remapped — defaults collided with existing ArchonOS services)

| Service | Host | Container | Why remapped |
|---|---|---|---|
| MCP | **8130** | 8100 | 8100 = trading-brain-mcp |
| noVNC | 6080 | 6080 | — |
| REST API | **8113** | 8080 | 8080 = Open WebUI (host-network, invisible to `docker ps --filter publish=`) |
| MJPEG | **8135** | 8081 | 8081 = hf-rebuild-wiki |

Registered in `archonos` `config/ports.yml`.

## Storage — two tiers, deliberately

| Mount | Path | Media | Write speed | Use for |
|---|---|---|---|---|
| `/data` | `./data` | SSD ext4 | 351 MB/s | active working set, indexing, random I/O |
| `/archive` | `/media/alfredaranas/NewVolume/jalbtcx` | hardware RAID6, NTFS/ntfs-3g | 89 MB/s | bulk survey storage (5.5 T free) |

Do COPC conversion and processing against the SSD; keep the corpus on RAID6.
The RAID6 is in `/etc/fstab` with `nofail` and `allow_other` (required for Docker
to bind-mount a FUSE mount).

> Do **not** use the Seagate drive (`sdc2`, 6.7 T free) for a bind mount — it is a
> udisks2 session mount with no fstab entry. If it is not mounted when Docker
> starts, the container silently gets an empty directory instead of the data.

## Point cloud workflow — PDAL is a SIDECAR, not in this image

QGIS has native `copc` / `ept` / `vpc` providers, so it only ever needs to *read*
COPC. PDAL is **not** installed in this image and must not be: Ubuntu 24.04 ships
no pdal at all, and the only packaged build (ubuntugis PPA) requires GDAL 3.11.4
while QGIS 3.44 here links GDAL 3.8.4. Forcing that upgrade breaks QGIS.

Convert raw LAS to COPC with the sidecar container:

```bash
docker run --rm -v /media/alfredaranas/NewVolume/jalbtcx:/work pdal/pdal:latest \
  pdal translate /work/incoming/FILE.las /work/copc/FILE.copc.laz \
  --writers.copc.a_srs=EPSG:26918
```

Then load it from an archon:

```
add_layer(uri="/archive/copc/FILE.copc.laz", provider="copc")
```

**`a_srs` is mandatory.** CZMIL LAS files carry an empty `comp_spatialreference` —
no CRS at all. Omit it and you get a valid-looking layer with no projection that
silently misaligns against everything else. NCMP North Carolina = EPSG:26918
(NAD83 / UTM 18N). Note `writers.gdal` has no `a_srs` argument — it inherits from
its input, so set the CRS at the COPC step.

## Getting data here

SSH between jalbtcx04 and Yoda is denied in **both** directions (no key trust;
jalbtcx04 is domain-joined). Use Taildrop:

```powershell
# on jalbtcx04 - must use the Tailscale IP; the hostname resolves to a LAN IP and fails
& "C:\Program Files\Tailscale\tailscale.exe" file cp "D:\_data\...\FILE.las" 100.92.239.85:
```
```bash
# on Yoda
tailscale file get /media/alfredaranas/NewVolume/jalbtcx/incoming/
```

Receiving required a one-time elevated `tailscale set --operator=` (done
2026-07-30) — otherwise every `file get` needs root.
Source corpus: `jalbtcx04:D:\_data` — 623 LAS / 278.8 GB.

## Operating

```bash
# python changes only (src/ is bind-mounted) - no rebuild needed
docker restart qgisstreammcp

# Dockerfile changes
docker tag qgis-streammcp-qgisstreammcp qgis-streammcp:rollback-$(date +%Y%m%d)
setsid nohup docker compose build > build.log 2>&1 < /dev/null &   # bare nohup dies with the SSH session
docker compose up -d

# rollback
docker tag qgis-streammcp:pre-pdal-20260729 qgis-streammcp-qgisstreammcp && docker compose up -d
```

Health: `curl -s localhost:8113/health` — expect `processing_available: true`.
Startup takes ~40 s (Xvfb + QGIS + supervisord).
Regression guard after any rebuild: algorithm count should still be **695** and
`gdalinfo --version` still **3.8.4**.

## Gotchas that cost real time

- **`docker ps --filter publish=<port>` misses host-network containers.** Open WebUI
  holds `:8080` invisibly. Use `ss -ltn` + `curl` to identify a port's owner.
- **Docker creates a missing bind-mount source as root-owned.** `data/` was
  unwritable. Fix without elevation: `docker exec qgisstreammcp chown -R 1000:1000 /data`.
- **`ROTA` is meaningless for hardware RAID**, and the absence of `md` devices does
  not mean the absence of RAID — a hardware array presents as one block device.
- **`apt-cache search` can return nothing while packages exist** (description index
  stripped in slim images). Use `apt-cache pkgnames`.
- **Never `pip install --upgrade numpy`** in this image — it breaks QGIS's compiled
  bindings. Use apt for anything in the scientific stack.

## Known gaps

- No auth on `:8130` / `:6080` / `:8113`, and `execute_python` is arbitrary code
  execution. Tailscale-only, deliberately not on the cb246996 public tunnel.
- No CPU/memory limits — a large ingest could pressure Yoda.
- Nothing pages if the container or QGIS session dies.
- Reboot survival never observed (`restart: unless-stopped` is set; RAID6 mount is
  fstab `nofail`).

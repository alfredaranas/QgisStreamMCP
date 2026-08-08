# B1 — LAStools QGIS plugin: SKIPPED with rationale

**Status**: NOT installed, intentionally.

## Why we skipped

The QGIS "LAStools provider" plugin (originally by Martin Isenburg / rapidlasso)
is a proprietary wrapper around the LAStools suite. From the project README:

- `LASlib` and `LASzip` are open source (LGPL).
- The **LAStools Software Suite** above those libraries — including
  `lasground`, `lasclassify`, `lasclip`, `lasthin`, `lascanopy`,
  and the full integration with QGIS Processing Toolbox — is **proprietary**.
- Many tools require a license key. Some can be used for evaluation
  purposes only (time-limited), or are licensed per-seat/per-org.

In a Docker image that's expected to live for months/years unattended,
a time-limited or per-organisation-billed license string is impractical.
The image also runs headless under supervisord — there is no operator at
the keyboard to click "I accept the license" once a day.

## What we already have instead (zero licence, all the useful tools)

| Use case | Replacement in this image |
|---|---|
| LAS -> COPC-LAZ | `pdal translate ... COPC` (libpdal16, libgdal37) |
| Ground classification | `pdal filters.pmf` / `filters.smrf` via `pdal_pipeline` MCP tool |
| Clipping, decimating | `filters.range`, `filters.crop`, `filters.decimation` |
| Reproject | `filters.reproject` (depends on libgdal) |
| Visualize COPC | QGIS native `copc` provider (built-in) |
| Histogram of classification | `pdal filters.groupby` via `galaxy_class_histogram` Processing script (B11) |
| Classify water | `galaxy_water_classify.model3` (B9) |

If a future requirement explicitly demands a licensed tool that PDAL lacks,
the right path is: host a small sidecar container that owns the licence,
mount only its CLI tools into this image, and re-export them as MCP tools.
We will NOT bake a license string into `Dockerfile` or `secrets/`.

## How to enable later (if user has a license)

```bash
# Inside QGIS GUI: Plugins > Manage and Install Plugins > search "LAStools"
# In headless mode, install via the QGIS Python console:
from pyplugin_installer.installer import PluginInstaller
PluginInstaller().installFromZipFile('/path/to/lastools.zip')
# Then accept the license in the GUI manually.
```

The pdal-side fleet ops are NOT affected by this skip.

# ═══════════════════════════════════════════════════════════════════════════════
# QgisStreamMCP — multi-stage build (B19)
#
# Stages:
#   base    — QGIS 3.44.13 LTR + GDAL 3.11.4 (PPA) + PDAL 2.6.2 + GRASS 8.4 + SAGA 9.8
#             + OTB 8.1 + python stack + Processing providers + supervisor stack.
#             Cached layer; only rebuilds when base deps change.
#   app     — thin layer on top: source code (.py), templates, recipes, scripts,
#             models, secret files. Layer rebuilds on source change; fast.
#   final   — used as default target; assembly of base + app + labels (B15).
#
# Package versions (B15): pinned by explicit "=PKGVERSION" where possible.
# Critical pins:
#   libgdal37 = 3.11.4+dfsg-1~noble0    (A2: ≥ 3.10.2)
#   libpdal16 = 2.6.2+ds-1~noble2       (A1: ≥ 2.6 has copc, las built-in)
#   qgis      = 3.44.13 from qgis.org LTR repo (verified 2026-08-06) (no PPA pin — apt tracks LTR)
#   grass     = 8.4.2-1~noble1
#   saga      = 9.8.0+dfsg-1~noble1
#   otb       = 8.1.0+dfsg-1~noble2
#
# Security baseline (carried from f2ccb89):
#   - Container ports MUST be bound to tailscale0 (100.92.239.85) at the
#     docker-compose layer, NOT inside this image. Image listens on 0.0.0.0.
#   - /api/* on :8080 requires QGIS_API_TOKEN; execute_python requires
#     QGIS_ELEVATED_TOKEN. Enforced by src/api_server.py at runtime.
#   - MCP Server :8100 is Tailscale-only (compose bind) and inherits the
#     api_server bearer scheme indirectly via MCP client config.
#   - noVNC HTTP basic-auth via QGIS_VNC_HTTP_PASSWORD; x11vnc via rfb.
# ═══════════════════════════════════════════════════════════════════════════════

# ──────────────────────────────────────────────────────────────────────────────
# BASE STAGE — heavy deps (rebuild only when this list changes)
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    QT_QPA_PLATFORM=xcb \
    LP_NUM_THREADS=4 \
    XDG_SESSION_TYPE=x11 \
    XDG_RUNTIME_DIR=/run/user/0 \
    QT_X11_NO_MITSHM=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# ── System core ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        x11vnc \
        fluxbox \
        x11-xserver-utils \
        xdotool \
        mesa-utils \
        libgl1-mesa-dri \
        libgl1 \
        libosmesa6 \
        libglapi-mesa \
        libegl1 \
        libglu1-mesa \
        libglvnd0 \
        libglx-mesa0 \
        websockify \
        curl \
        wget \
        net-tools \
        gnupg \
        software-properties-common \
        python3 \
        python3-pip \
        python3-venv \
        supervisor \
        ffmpeg \
        fonts-liberation \
        fonts-dejavu-core \
        fonts-noto-core \
        ca-certificates \
        # Build (needed by python3-pdal pip wheel — CMake C++ extension)
        build-essential \
        cmake \
        python3-dev \
        pybind11-dev \
        libgdal-dev \
        # Time
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# ── QGIS LTR (3.44.13) from official qgis.org repo ───────────────────────────
# Pinned to the LTR; later rebuilds update via apt-get upgrade, not image change.
RUN wget -qO /etc/apt/keyrings/qgis-archive-keyring.gpg \
        https://download.qgis.org/downloads/qgis-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/qgis-archive-keyring.gpg] \
        https://qgis.org/ubuntu-ltr noble main" \
        > /etc/apt/sources.list.d/qgis.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        qgis \
        qgis-plugin-grass \
        python3-qgis \
        qgis-providers \
    && rm -rf /var/lib/apt/lists/*

# ── UbuntuGIS unstable PPA: GDAL 3.11.4 + PDAL 2.6.2 + GRASS 8.4 + SAGA + OTB
#    (A1, A2, A3, B2, B3)
# NOTE: libgdal37 (3.11.4) replaces libgdal34 shipped with QGIS LTR. Different
#       SONAMEs (.so.34 vs .so.37) coexist; QGIS binaries keep using .so.34
#       they were linked against at qgis.org, PDAL/GRASS/SAGA/OTB use .so.37.
RUN add-apt-repository -y ppa:ubuntugis/ubuntugis-unstable \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        # A2: GDAL 3.11.4 (also pulls Python gdal/osgeo bindings)
        libgdal37=3.11.4+dfsg-1~noble0 \
        gdal-bin=3.11.4+dfsg-1~noble0 \
        python3-gdal=3.11.4+dfsg-1~noble0 \
        # A1: PDAL 2.6.2 (CLI + libpdal16 with copc/las built-in)
        pdal=2.6.2+ds-1~noble2 \
        libpdal-dev=2.6.2+ds-1~noble2 \
        libpdal-plugins=2.6.2+ds-1~noble2 \
        # B4 extras: pgpointcloud (copc/las are in libpdal core; greyhound
        # was removed from PDAL upstream circa 2.3 — replaced by EPT/COPC)
        # A3: GRASS 8.4.2
        grass=8.4.2-1~noble1 \
        grass-core=8.4.2-1~noble1 \
        # B3: SAGA 9.8.0
        saga=9.8.0+dfsg-1~noble1 \
        # B2: Orfeo ToolBox 8.1 + GDAL bridge
        otb-bin=8.1.0+dfsg-1~noble2 \
        otb-qgis=8.1.0+dfsg-1~noble2 \
    && rm -rf /var/lib/apt/lists/*

# ── Python bindings ──────────────────────────────────────────────────────────
# pip wheel for pdal builds against system libpdal16 via CMake.
# gdal/osgeo already come from libgdal37 (apt).
# --ignore-installed for distro-managed pkgs (apt-installed python3-* have no
# RECORD file, so pip cannot uninstall/upgrade them; container-local so safe)
RUN pip3 install --break-system-packages --no-cache-dir \
        --ignore-installed typing_extensions packaging \
        # MCP / REST stack
        'fastapi>=0.110' \
        'uvicorn[standard]>=0.27' \
        'mcp[cli]>=1.20,<3' \
        'python-multipart>=0.0.9' \
        'httpx>=0.27' \
        'pydantic>=2.11,<3' \
        'psutil>=5.9' \
        # B6: point cloud python stack (~500MB total)
        'lazrs>=0.5' \
        'plyfile>=1.0' \
        'pyntcloud>=0.3' \
        'open3d>=0.19' \
        # A1: laspy already present from earlier builds (kept)
        'laspy[lazrs]>=2.5' \
        # GIS / vector stack
        'numpy<2.0' \
        'pandas>=2.0' \
        'geopandas>=0.14' \
        'shapely>=2.0' \
        'fiona>=1.9' \
        'pyproj>=3.6' \
        'rasterio>=1.3' \
        'h5py>=3.10' \
        'netcdf4>=1.6' \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# apt python3-matplotlib ships a stale mpl_toolkits that shadows pip's and
# breaks Axes3D (mpl_toolkits is a namespace pkg; apt's copy wins). Purge it.
RUN apt-get purge -y python3-matplotlib 2>/dev/null || true; \
    rm -rf /usr/lib/python3/dist-packages/mpl_toolkits

# ── A1: python-pdal bindings (NON-FATAL).
# python-pdal>=3.4 needs PDAL>=2.7; PPA ships 2.6.2, so try 3.3.x then 3.2.x.
# The pdal CLI (apt) is the load-bearing piece for LAS->COPC; bindings are
# convenience and imported lazily by helpers, so never fail the build here.
RUN pip3 install --break-system-packages --no-cache-dir 'pdal>=3.3,<3.4' \
 || pip3 install --break-system-packages --no-cache-dir 'pdal>=3.2,<3.3' \
 || echo '[WARN] python-pdal bindings unavailable; pdal CLI still present'

# ── apt stack that must match python3 (already python3.12 on noble) ─────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-pandas \
        python3-geopandas \
        python3-shapely \
        python3-fiona \
        python3-rasterio \
        python3-h5py \
        python3-netcdf4 \
        python3-psycopg2 \
        python3-matplotlib \
        python3-numpy \
        # gdal-py is already installed via the GDAL pin above; keep as a
        # explicit reminder that osgeo.gdal is provided by python3-gdal
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Enable GRASS/SAGA/OTB providers in QGIS Processing ───────────────────────
# grassprovider is enabled via [PythonPlugins] in QGIS3.ini. Saga + OTB auto-
# register when qgis-plugin-grass / otb-qgis is installed; verify post-build.
RUN mkdir -p /root/.local/share/QGIS/QGIS3/profiles/default/QGIS \
    && printf '\n[PythonPlugins]\ngrassprovider=true\n' \
       >> /root/.local/share/QGIS/QGIS3/profiles/default/QGIS/QGIS3.ini

# ── noVNC ────────────────────────────────────────────────────────────────────
RUN wget -qO- https://github.com/novnc/noVNC/archive/v1.5.0.tar.gz \
        | tar xz -C /opt \
    && mv /opt/noVNC-1.5.0 /opt/novnc \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# ── Filesystem skeleton ──────────────────────────────────────────────────────
RUN mkdir -p \
        /app /data /archive /tmp/qgis \
        /data/jobs /data/cache \
        /run/user/0 \
        /var/log/supervisor \
        /root/.local/share/QGIS/QGIS3/profiles/default/python/plugins \
        /root/.local/share/QGIS/QGIS3/profiles/default/python/startup \
        /root/.local/share/QGIS/QGIS3/profiles/default/processing/scripts \
        /root/.local/share/QGIS/QGIS3/profiles/default/processing/models \
        /root/.fluxbox \
    && chmod 0700 /run/user/0 \
    && printf '[app] (name=.*)\n  [Maximized] {yes}\n[end]\n' > /root/.fluxbox/apps

# ── B20: qgis_process jobs go to /data/jobs/<timestamp> ─────────────────────
ENV QGIS_PROCESS_WORKDIR="/data/jobs" \
    QGIS_AUTOSAVE_HOURLY_KEEP=24 \
    QGIS_AUTOSAVE_DAILY_KEEP=30 \
    QGIS_ARCHIVE="/archive/system/qgis" \
    IMAGE_REVISION="base-r2-20260806" \
    IMAGE_BUILD_DATE="2026-08-06"

# ──────────────────────────────────────────────────────────────────────────────
# APP STAGE — thin: source + scripts + models + templates
# ──────────────────────────────────────────────────────────────────────────────
FROM base AS app

WORKDIR /app

# Copy in priority order: most-changes-last, so Docker cache survives source-only edits
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /app/entrypoint.sh
COPY maximize_qgis.sh /app/maximize_qgis.sh
COPY novnc_wrapper.sh /app/novnc_wrapper.sh
COPY qgis_autosave.sh /app/qgis_autosave.sh
RUN chmod +x /app/entrypoint.sh /app/maximize_qgis.sh /app/novnc_wrapper.sh /app/qgis_autosave.sh

# Application source
COPY main_mcp.py /app/main_mcp.py
COPY qgis_app.html /app/qgis_app.html
COPY datasources.json /app/datasources.json
COPY setup_qgis_connections.py /app/setup_qgis_connections.py
COPY src/ /app/src/
COPY skills/ /app/skills/
COPY templates/ /app/templates/
COPY recipes/ /app/recipes/

# B7: pdal_copc helper lives under /app/src/helpers/ alongside the qgis_helpers
COPY helpers/ /app/helpers/

# B11: Processing "scripts" provider entries (R-runner compatible)
COPY processing_scripts/ /root/.local/share/QGIS/QGIS3/profiles/default/processing/scripts/

# B9: galaxy_water_classify model3
COPY processing_models/ /root/.local/share/QGIS/QGIS3/profiles/default/processing/models/

# QGIS bridge auto-load
COPY src/qgis_bridge.py /root/.local/share/QGIS/QGIS3/profiles/default/python/startup/qgis_bridge.py

# B5: nkarasiak/qgis-mcp plugin (loaded at QGIS launch via plugin discovery)
COPY third_party/qgis_mcp_plugin/ \
     /root/.local/share/QGIS/QGIS3/profiles/default/python/plugins/qgis_mcp_plugin/
# B5: qgis-mcp Python server (runs under supervisord, talks to plugin over socket)
COPY third_party/qgis_mcp_server/ /app/third_party/qgis_mcp_server/

# ── B15: version label + commit label ────────────────────────────────────────
ARG GIT_COMMIT="unknown"
ARG BUILD_DATE="2026-08-06"
LABEL org.opencontainers.image.title="qgisstreammcp" \
      org.opencontainers.image.version="${BUILD_DATE}-${GIT_COMMIT}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.source="https://github.com/alfredaranas/QgisStreamMCP" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      com.archonos.archon="archonos" \
      com.archonos.role="qgis-mcp" \
      com.archonos.commit="${GIT_COMMIT}"

ENV IMAGE_REVISION="app-${BUILD_DATE}-${GIT_COMMIT}"

# ── Healthcheck ──────────────────────────────────────────────────────────────
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=4 \
    CMD curl -sf http://localhost:8080/health && curl -sf http://localhost:8100/health || exit 1

EXPOSE 6080 8080 8081 8100

ENTRYPOINT ["/app/entrypoint.sh"]

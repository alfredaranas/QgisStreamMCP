#!/usr/bin/env bash
# Dry-run resolve: validates pins + qgis.org/ubuntugis coexistence BEFORE real build
set -uo pipefail
CH="${1:-ubuntu-ltr}"   # ubuntu-ltr (3.34) | ubuntu (3.44)
echo "=== CHANNEL: $CH ==="
docker run --rm ubuntu:24.04 bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wget gnupg software-properties-common ca-certificates >/dev/null 2>&1
mkdir -p /etc/apt/keyrings
wget -qO /etc/apt/keyrings/qgis.gpg https://download.qgis.org/downloads/qgis-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/qgis.gpg] https://qgis.org/$CH noble main' > /etc/apt/sources.list.d/qgis.list
add-apt-repository -y ppa:ubuntugis/ubuntugis-unstable >/dev/null 2>&1
apt-get update -qq
echo '--- AVAILABLE VERSIONS ---'
for p in qgis python3-qgis libgdal37 gdal-bin pdal libpdal-dev libpdal-plugins grass grass-core saga otb-bin otb-qgis; do
  v=\$(apt-cache policy \$p 2>/dev/null | awk '/Candidate:/{print \$2}')
  echo \"\$p -> \${v:-MISSING}\"
done
echo '--- COEXIST SIMULATE (qgis + gdal37 + pdal + grass + saga + otb) ---'
apt-get install -s -y qgis python3-qgis qgis-providers libgdal37 gdal-bin pdal libpdal-dev grass saga otb-bin otb-qgis 2>&1 | grep -E '^(Remv|Conf .*qgis|E:|The following packages will be REMOVED)' | head -25
echo '--- REMOVE COUNT ---'
apt-get install -s -y qgis python3-qgis libgdal37 pdal grass saga otb-bin 2>&1 | grep -c '^Remv' || true
"

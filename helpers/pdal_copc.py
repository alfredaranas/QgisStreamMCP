#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# helpers/pdal_copc.py — shared point-cloud conversion utilities (B7)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Drop-in helpers, importable from BOTH the QGIS PyQGIS context (during
# startup, via sys.path injection) AND the QGIS Processing "scripts"
# provider (B11). Kept framework-agnostic on purpose:
#   - no qgis.core imports
#   - returns plain dicts (no QVariant, no QGIS-specific types)
#   - works equally well inside `qgis_process` and inside the GUI
#
# Used by:
#   - scripts/pdal_copc.py           (Processing-script wrapper for `qgis_process`)
#   - scripts/czmil_las_to_copc.py   (CZMIL-tuned wrapper)
#   - scripts/galaxy_class_histogram.py (post-classification stats)
#   - src/qgis_helpers.py            (PyQGIS in-process helper)
#   - main_mcp.py                    (las_to_copc MCP tool)
#
# Key contract: `srs_epsg` is REQUIRED for raw LAS (no auto-detect), because
# CZMIL LAS files ship with an empty comp_spatialreference — auto-detect
# would silently misalign every layer. Caller MUST pass a real EPSG:XXXX
# string. Pass "" only if you have checked the input already carries a
# valid CRS and you accept that risk.
# ═══════════════════════════════════════════════════════════════════════════════

import json
import subprocess
import time
from pathlib import Path

_PDAL_BIN = "/usr/bin/pdal"


def _run(cmd, timeout):
    """Subprocess helper that captures stdout/stderr and returns (rc, out, err)."""
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return proc.returncode, proc.stdout, proc.stderr


def las_info(input_path, timeout=120):
    """Return PDAL metadata for a .las/.laz/.copc.laz file as a dict.

    Args:
        input_path: absolute path inside the container.
        timeout: seconds before the subprocess is killed (default 120).

    Returns:
        dict with at least {"point_count", "srs", "bounds"} keys, or
        {"error": "..."} on failure.
    """
    p = Path(input_path)
    if not p.exists():
        return {"error": f"File not found: {input_path}"}
    if not p.is_file():
        return {"error": f"Not a file: {input_path}"}
    rc, out, err = _run([_PDAL_BIN, "info", "--metadata", str(p)], timeout)
    if rc != 0:
        return {"error": err.strip() or out.strip(), "returncode": rc}
    try:
        meta = json.loads(out)
    except json.JSONDecodeError as e:
        return {"error": f"pdal info non-JSON: {e}", "raw_head": out[:200]}
    readers = meta.get("readers", [])
    if not readers:
        return {"error": "no readers metadata", "raw": meta}
    reader = readers[0]
    return {
        "point_count": reader.get("count"),
        "srs": (
            reader.get("srs", {}).get("compoundWkt")
            if isinstance(reader.get("srs"), dict)
            else reader.get("srs")
        ),
        "bounds": reader.get("bounds"),
        "pdal_version": meta.get("pdal_version"),
    }


def las_to_copc(input_path, output_path, srs_epsg=None, compression="laz", forward=None, timeout=600):
    """Convert a .las/.laz file into a streamable COPC-LAZ.

    Args:
        input_path:  absolute path to a .las or .laz file.
        output_path: absolute path for the .copc.laz output. May be omitted
                     to write alongside input as <stem>.copc.laz.
        srs_epsg:    REQUIRED assignment for `writers.copc.a_srs` when the
                     input has no embedded CRS (CZMIL reality). Must be an
                     EPSG auth string like "EPSG:26918". Pass "" only when
                     the input is known to carry a valid CRS.
        compression: "laz" (default) or "las".
        forward:     optional EPSG:XXXX to reproject into during conversion.
                     None = assign-only (no reprojection).
        timeout:     seconds before subprocess is killed (default 600).

    Returns:
        dict with {"success", "input_path", "output_path", "output_size",
        "point_count", "elapsed_seconds", "command"}, or {"error": "..."}.
    """
    if not srs_epsg and not forward:
        return {"error": "srs_epsg is required for raw .las/.laz (CZMIL has no embedded CRS). "
                        "Pass 'EPSG:26918' for UTM 18N, or a different zone, or '' if you have "
                        "verified the input already carries a CRS."}
    in_path = Path(input_path)
    if not in_path.exists() or not in_path.is_file():
        return {"error": f"Input not found or not a file: {input_path}"}
    if output_path:
        out_path = Path(output_path)
    else:
        out_path = in_path.parent / f"{in_path.stem}.copc.laz"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    def _epsg(v):
        # accept 26918, "26918", "EPSG:26918" -> "EPSG:26918"
        if v in (None, ""):
            return ""
        t = str(v).strip()
        return t if t.upper().startswith("EPSG:") else f"EPSG:{t}"

    srs_epsg = _epsg(srs_epsg)
    forward = _epsg(forward)

    # COPC writer is selected by the .copc.laz extension; do NOT pass the
    # compression as a positional arg -- pdal reads a bare positional as a
    # STAGE name and fails with "Couldn't create filter stage of type ...".
    cmd = [_PDAL_BIN, "translate", str(in_path), str(out_path)]
    if forward:
        # real reprojection (assign source CRS first when input has none)
        cmd += ["-f", "filters.reprojection", f"--filters.reprojection.out_srs={forward}"]
        if srs_epsg:
            cmd.append(f"--filters.reprojection.in_srs={srs_epsg}")
        cmd.append(f"--writers.copc.a_srs={forward}")
    elif srs_epsg:
        cmd.append(f"--writers.copc.a_srs={srs_epsg}")

    started = time.monotonic()
    rc, out, err = _run(cmd, timeout)
    elapsed = time.monotonic() - started
    if rc != 0:
        return {"error": err.strip() or out.strip(),
                "returncode": rc,
                "elapsed_seconds": round(elapsed, 2),
                "command": " ".join(cmd)}
    if not out_path.exists():
        return {"error": "pdal translate returned 0 but output file not found",
                "output_path": str(out_path), "stderr": err.strip()}
    return {
        "success": True,
        "input_path": str(in_path),
        "output_path": str(out_path),
        "output_size": out_path.stat().st_size,
        "srs_epsg": srs_epsg or "(inherited)",
        "elapsed_seconds": round(elapsed, 2),
        "command": " ".join(cmd),
    }


def pdal_translate(input_path, output_path, srs_epsg=None, forward=None, timeout=600):
    """Generic pdal translate (LAS/LAS -> any writers.* stage). Same arg shape as las_to_copc."""
    return las_to_copc(input_path, output_path, srs_epsg=srs_epsg, forward=forward, timeout=timeout)


def pdal_pipeline(pipeline, timeout=1800):
    """Run an arbitrary PDAL pipeline.

    Args:
        pipeline: dict {"pipeline": [...]}, list of stages, or string JSON.
        timeout: seconds.

    Returns:
        dict with {"success", "stdout", "stderr"} or {"error": ...}.

    Example:
        pdal_pipeline({
            "pipeline": [
                {"type": "readers.las", "filename": "/data/in.las"},
                {"type": "filters.range", "limits": "Classification[2:2]"},
                {"type": "writers.copc", "filename": "/data/ground.copc.laz",
                 "a_srs": "EPSG:26918"},
            ]
        })
    """
    if isinstance(pipeline, (list, dict)):
        text = json.dumps(pipeline)
    else:
        text = pipeline
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        tf.write(text)
        tmp = tf.name
    try:
        cmd = [_PDAL_BIN, "pipeline", "--input", tmp]
        rc, out, err = _run(cmd, timeout)
        if rc != 0:
            return {"error": err.strip() or out.strip(), "returncode": rc}
        return {"success": True, "stdout": out.strip(), "stderr": err.strip()}
    except subprocess.TimeoutExpired:
        return {"error": f"pdal pipeline timed out after {timeout}s"}
    finally:
        try:
            Path(tmp).unlink()
        except OSError:
            pass


def class_histogram(input_path, dim="Classification", timeout=600):
    """Return a histogram of values for any PDAL dimension (default: Classification).

    Useful for post-classification analysis (galaxy_water_classify model
    feeds this back to the operator). Uses `pdal pipeline` with filters.groupby.

    Returns:
        dict {value: count} for the requested dimension, or {"error": ...}.
    """
    pipeline = {
        "pipeline": [
            {"type": "readers.las", "filename": str(input_path)},
            {"type": "filters.groupby", "dimension": dim,
             "outputs": [{"type": "writers.null"}]},
        ]
    }
    rc, out, err = _run([_PDAL_BIN, "pipeline", "--input",
                          json.dumps(pipeline)], timeout)
    if rc != 0:
        return {"error": err.strip() or out.strip(), "returncode": rc}
    # filters.groupby emits JSON with a "groups" array; each group has
    # the dimension value at "<dim>" and a "num_selected" count.
    try:
        meta = json.loads(out) if out.strip() else {}
    except json.JSONDecodeError:
        # pdal prints human-readable summary to stderr by default; the JSON
        # pretty-print is on stdout. Fall back to parsing "Count : value".
        return {"error": "pdal pipeline returned non-JSON output",
                "raw_stdout": out, "raw_stderr": err}
    groups = meta.get("groups", [])
    return {str(g.get(dim)): g.get("num_selected") for g in groups}


# Aliases for clarity in callers (B7 spec)
las_to_copc_required_srs = las_to_copc

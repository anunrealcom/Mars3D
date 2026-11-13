#!/usr/bin/env python3
"""Prepare the 4 build-time data files that Blender's CMake embeds via datatoc.

Background: this checkout came from the GitHub mirror, which has no Git LFS
objects (all 6804 LFS files return 404).  CMake/Ninja only needs these four
binary inputs to build `blender`; all other LFS files are test/installer data.

This script is idempotent: it never overwrites a file that is already a valid
(i.e. > 1KB) real file, so a proper `git lfs pull` later takes precedence.

Usage:  python tools/clion_dev/prepare_data.py
"""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "release" / "datafiles"

# Any installed Blender can author a valid .blend. Prefer a matching 5.x build.
BLENDER_CANDIDATES = [
    Path(r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"),
    Path(r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe"),
    Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"),
    Path(r"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe"),
]
APP_TEMPLATE_GLOBS = [
    r"C:\Program Files\Blender Foundation\Blender 5.2\5.2\scripts\startup\bl_app_templates_system\*\startup.blend",
    r"C:\Program Files\Blender Foundation\Blender 5.*\*\scripts\startup\bl_app_templates_system\*\startup.blend",
]

TARGETS = [
    "startup.blend",
    "preview.blend",
    "preview_grease_pencil.blend",
    "splash.png",
]


def is_real(path: Path) -> bool:
    if not path.is_file():
        return False
    # CMake rejects startup.blend below 1KB (it treats that as an LFS pointer).
    # A tiny PNG is still a perfectly valid PNG, so validate its signature.
    if path.suffix == ".png":
        return path.stat().st_size > 64 and path.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
    return path.stat().st_size > 1024


def make_png(dest: Path, w: int = 64, h: int = 64, rgb=(38, 38, 44)) -> None:
    """Write a minimal but fully valid RGBA PNG without third-party modules."""
    row = b"\x00" + bytes((*rgb, 255)) * w
    raw = row * h

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) +
           chunk(b"IDAT", zlib.compress(raw, 9)) +
           chunk(b"IEND", b""))
    dest.write_bytes(png)


def find_blender():
    for exe in BLENDER_CANDIDATES:
        if exe.is_file():
            return exe
    import glob
    for pattern in (r"C:\Program Files\Blender Foundation\Blender*\blender.exe",):
        hits = sorted(glob.glob(pattern), reverse=True)
        if hits:
            return Path(hits[0])
    return None


def author_blend(dest: Path) -> str:
    """Create a real .blend using an installed Blender in background mode."""
    exe = find_blender()
    if exe:
        code = ("import bpy; bpy.ops.wm.save_as_mainfile(filepath=%r, "
                "check_existing=False, compress=False)" % dest.as_posix())
        try:
            result = subprocess.run(
                [str(exe), "--background", "--factory-startup", "--python-expr", code],
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode == 0 and is_real(dest):
                return "generated with %s" % exe.name
            print("[!] Blender returned %s: %s" %
                  (result.returncode, (result.stderr or result.stdout)[-300:]),
                  file=sys.stderr)
        except (OSError, subprocess.TimeoutExpired) as exc:
            print("[!] Blender invocation failed: %s" % exc, file=sys.stderr)

    # Fallback: an app-template startup.blend is a perfectly valid .blend.
    import glob
    for pattern in APP_TEMPLATE_GLOBS:
        for hit in sorted(glob.glob(pattern)):
            src = Path(hit)
            if is_real(src):
                shutil.copy2(src, dest)
                return "copied from %s" % src.name

    # Last resort: a valid BLENDER header is enough for datatoc (byte-to-C),
    # but Blender could not load it at runtime. Report clearly instead of
    # silently producing something misleading.
    raise RuntimeError(
        "No installed Blender found to author startup.blend. "
        "Install any Blender 5.x, or copy a real .blend file to %s" % dest
    )


def main() -> int:
    DATA.mkdir(parents=True, exist_ok=True)
    print("Source root: %s" % ROOT)

    startup = DATA / "startup.blend"
    if is_real(startup):
        print("[OK] startup.blend already present (%d bytes)" % startup.stat().st_size)
    else:
        how = author_blend(startup)
        print("[OK] startup.blend %s (%d bytes)" % (how, startup.stat().st_size))

    for name in ("preview.blend", "preview_grease_pencil.blend"):
        target = DATA / name
        if is_real(target):
            print("[OK] %s already present" % name)
        else:
            shutil.copy2(startup, target)
            print("[OK] %s generated (copy of startup.blend)" % name)

    splash = DATA / "splash.png"
    if is_real(splash):
        print("[OK] splash.png already present")
    else:
        make_png(splash)
        print("[OK] splash.png generated (%d bytes)" % splash.stat().st_size)

    missing = [n for n in TARGETS if not is_real(DATA / n)]
    if missing:
        print("[FAIL] still missing/invalid: %s" % ", ".join(missing), file=sys.stderr)
        return 1
    print("[DONE] all 4 build-time data files are ready; Ninja graph is complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

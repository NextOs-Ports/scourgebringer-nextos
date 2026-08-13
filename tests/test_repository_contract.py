#!/usr/bin/env python3
"""Static public-repository and release-input contract for ScourgeBringer."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SCREENSHOTS = {
    "screenshots/00-titulo.png",
    "screenshots/01-primeira-sala.png",
    "screenshots/02-tutorial-ataque.png",
    "screenshots/03-launcher-portmaster.png",
}
PRIVATE_MARKERS = tuple(
    fragment.encode("utf-8")
    for fragment in (
        "192" + ".168.",
        "/home/" + "felipe",
        "TRABALHO CLAUDE " + "CODE",
        "claude-" + "1000",
    )
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest = json.loads((ROOT / "nxrelease.json").read_text(encoding="utf-8"))
require(manifest["schema_version"] == 2, "unexpected nxrelease schema")
require(manifest["package"]["id"] == "scourgebringer", "wrong package id")
require(
    manifest["package"]["version"] == "1.0.0-test.8",
    "wrong package version",
)
require(manifest["release"]["max_glibc"] == "2.17", "glibc ceiling drifted")

missing_build_outputs: list[str] = []
for entry in manifest["files"]:
    source = ROOT / entry["source"]
    if entry["kind"] == "project-linux" and not source.exists():
        require(
            entry["target"] == "scourgebringer/scourgebringer-nextos",
            "unexpected omitted build output",
        )
        missing_build_outputs.append(entry["source"])
        continue
    require(source.is_file() and not source.is_symlink(), f"unsafe input: {source}")
    require(sha256(source) == entry["sha256"], f"hash drift: {entry['source']}")

require(
    missing_build_outputs in ([], ["scourgebringer-nextos"]),
    "unexpected build-output set",
)
readme_entry = next(
    entry for entry in manifest["files"]
    if entry["target"] == "scourgebringer/README.md"
)
require(
    readme_entry["source"] == "package/README.md",
    "release must use the physically audited README snapshot",
)

installation = (ROOT / "INSTALLATION.md").read_text(encoding="utf-8")
for required in (
    "## Português",
    "## English",
    "com.pid.scourgebringer",
    "arm64-v8a",
    "154.803.705 bytes",
    "154,803,705 bytes",
    "6ee2082eebaed3d3ddb736295cc38760edb2f4f74b29ea1f2d424c7f9e15fd1e",
    "141.799.538 bytes",
    "141,799,538 bytes",
    "3a5818273e3b0dba528a69e4a0321378fcb43bf1dc6a10d95c56c15dfef277d3",
):
    require(required in installation, f"INSTALLATION.md lost: {required}")

for relative in EXPECTED_SCREENSHOTS:
    image = ROOT / relative
    require(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), f"bad PNG: {relative}")
root_readme = (ROOT / "README.md").read_text(encoding="utf-8")
for relative in EXPECTED_SCREENSHOTS:
    require(relative in root_readme, f"README does not show {relative}")

tracked_raw = subprocess.check_output(
    ["git", "-C", str(ROOT), "ls-files", "-z"]
)
tracked = [item.decode("utf-8") for item in tracked_raw.split(b"\0") if item]
for relative in tracked:
    lower = relative.lower()
    require(
        not lower.endswith((".apk", ".aab", ".apkm", ".apks", ".xapk", ".obb")),
        f"proprietary archive tracked: {relative}",
    )
    require(
        not lower.endswith((".sav", ".log", ".tombstone")),
        f"runtime artifact tracked: {relative}",
    )
    path = ROOT / relative
    data = path.read_bytes()
    for marker in PRIVATE_MARKERS:
        require(marker not in data, f"private marker in {relative}")

external_stat = re.compile(r"(?<![/A-Za-z0-9_.-])stat(?=[\t );&|]|$)")
for relative in tracked:
    if not relative.endswith(".sh"):
        continue
    for number, line in enumerate(
        (ROOT / relative).read_text(encoding="utf-8").splitlines(), 1
    ):
        if line.lstrip().startswith("#"):
            continue
        require(
            external_stat.search(line) is None,
            f"external stat in {relative}:{number}",
        )

print(
    "repository contract: PASS "
    f"release_files={len(manifest['files'])} screenshots={len(EXPECTED_SCREENSHOTS)} "
    f"omitted_build_outputs={len(missing_build_outputs)}"
)

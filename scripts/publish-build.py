#!/usr/bin/env python3
"""Publish a validated app and zip, restoring previous outputs on failure."""
from pathlib import Path
import os
import sys


def publish(stage: Path, destination: Path) -> None:
    names = ("Cheatble.app", "Cheatble.zip")
    for name in names:
        if not (stage / name).exists():
            raise FileNotFoundError(stage / name)
    backup = stage / "previous"
    backup.mkdir()
    saved = []
    installed = []
    try:
        for name in names:
            target = destination / name
            if target.exists():
                os.replace(target, backup / name)
                saved.append(name)
            os.replace(stage / name, target)
            installed.append(name)
    except OSError:
        # Move new outputs back to staging, then restore both previous outputs.
        # The caller keeps staging on failure, including any recovery backups.
        for name in reversed(installed):
            os.replace(destination / name, stage / name)
        for name in reversed(saved):
            os.replace(backup / name, destination / name)
        raise


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: publish-build.py STAGING_DIRECTORY DIST_DIRECTORY")
    publish(Path(sys.argv[1]), Path(sys.argv[2]))

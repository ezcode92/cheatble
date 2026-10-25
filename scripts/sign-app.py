#!/usr/bin/env python3
"""Sign local Cheatble builds with one certificate-pinned, stable identity."""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
with (app / "Contents/Info.plist").open("rb") as file:
    identifier = plistlib.load(file)["CFBundleIdentifier"]
if identifier != "app.cheatble.desktop":
    raise SystemExit("Only the Cheatble app bundle may use this local signing identity.")
configuration = Path.home() / "Library/Application Support/Cheatble/Signing/identity.json"
if os.environ.get("CHEATBLE_ADHOC_SIGNING") == "1":
    print("Explicit ad-hoc build: Accessibility permission will not survive code changes.")
    command = ["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app)]
else:
    if not configuration.exists():
        raise SystemExit("Run python3 scripts/setup-signing.py once before building. "
                         "Use CHEATBLE_ADHOC_SIGNING=1 only for temporary test builds.")
    identity = json.loads(configuration.read_text())
    fingerprint = identity["sha1"]
    if identity.get("schemaVersion") != 1 or not re.fullmatch(r"[A-Fa-f0-9]{40}", fingerprint):
        raise SystemExit("Invalid local signing configuration; it was not replaced.")
    requirement = f'designated => identifier "{identifier}" and certificate leaf = H"{fingerprint}"'
    command = ["/usr/bin/codesign", "--force", "--sign", fingerprint,
               "--keychain", identity["keychain"], "--timestamp=none",
               "--requirements", "=" + requirement, str(app)]
subprocess.run(command, check=True)
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(app)], check=True)

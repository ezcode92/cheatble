#!/usr/bin/env python3
"""Query Accessibility from the installed app's LaunchServices context."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

app = Path("/Applications/Cheatble.app")
with (app / "Contents/Info.plist").open("rb") as file:
    if plistlib.load(file).get("CFBundleIdentifier") != "app.cheatble.desktop":
        raise SystemExit("The installed Cheatble bundle was not found.")

# Direct shell execution can inherit the launching terminal's TCC responsibility.
# A diagnostic-only LaunchServices instance does not create a window or hot keys.
with tempfile.TemporaryDirectory(prefix="cheatble-permission-", dir="/private/tmp") as temporary:
    output = Path(temporary) / "status.json"
    errors = Path(temporary) / "errors.txt"
    output.touch(mode=0o600)
    errors.touch(mode=0o600)
    subprocess.run(["/usr/bin/open", "-n", "-g", "--stdout", str(output), "--stderr", str(errors),
                    str(app), "--args", "--permission-status"], check=True)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            status = json.loads(output.read_text())
        except json.JSONDecodeError:
            time.sleep(0.05)
            continue
        if status.get("bundleIdentifier") != "app.cheatble.desktop" or status.get("bundlePath") != str(app):
            raise SystemExit("The response was not from the expected installed app.")
        status["launchContext"] = "LaunchServices"
        print(json.dumps(status, ensure_ascii=False, sort_keys=True))
        break
    else:
        raise SystemExit(errors.read_text().strip() or "The installed app did not return a permission status.")

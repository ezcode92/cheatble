#!/usr/bin/env python3
"""Check update identity and reject same-ID impostors or modified resources."""
from pathlib import Path
import argparse
import plistlib
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
app = root / "dist/Cheatble.app"
parser = argparse.ArgumentParser()
parser.add_argument("--previous-requirement", type=Path,
                    help="Compare a new build with an earlier release's recorded designated requirement.")
options = parser.parse_args()

def run(*arguments, expected_success=True):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if (result.returncode == 0) != expected_success:
        raise SystemExit(f"Unexpected result from {arguments[0]}: {result.stderr}")
    return result.stdout + result.stderr

def requirement(bundle):
    output = run("/usr/bin/codesign", "-dr", "-", str(bundle))
    return next(line.split("=>", 1)[1].strip() for line in output.splitlines()
                if line.startswith("designated =>"))

def code_hash(bundle):
    return re.search(r"^CDHash=(.+)$", run("/usr/bin/codesign", "-dv", "--verbose=4", str(bundle)), re.M)[1]

original_requirement = (options.previous_requirement.read_text().strip()
                        if options.previous_requirement else requirement(app))
if 'identifier "app.cheatble.desktop"' not in original_requirement or "certificate leaf = H" not in original_requirement:
    raise SystemExit("A certificate-pinned signing identity is required for this check.")
run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + original_requirement, str(app))
with tempfile.TemporaryDirectory(prefix="cheatble-signature-check-", dir="/private/tmp") as temporary:
    scratch = Path(temporary)
    updated = scratch / "updated.app"
    run("/usr/bin/ditto", str(app), str(updated))
    if not options.previous_requirement:
        info = updated / "Contents/Info.plist"
        value = plistlib.loads(info.read_bytes())
        value["CFBundleVersion"] = str(value["CFBundleVersion"]) + "01"
        info.write_bytes(plistlib.dumps(value))
        run(sys.executable, str(root / "scripts/sign-app.py"), str(updated))
        if code_hash(app) == code_hash(updated):
            raise SystemExit("Update fixture must have different signed content.")
    if requirement(updated) != original_requirement:
        raise SystemExit("The app identity changed across an update.")
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + original_requirement, str(updated))
    print("PASS: changed app content still matches the previous certificate-pinned identity.")

    impostor = scratch / "same-id-different-signer.app"
    run("/usr/bin/ditto", str(updated), str(impostor))
    run("/usr/bin/codesign", "--remove-signature", str(impostor))
    run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(impostor))
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + original_requirement,
        str(impostor), expected_success=False)
    print("PASS: an ad-hoc app with the same bundle identifier is rejected.")

    resource = updated / "Contents/Resources/Shortcuts.json"
    resource.write_bytes(resource.read_bytes() + b"\n")
    run("/usr/bin/codesign", "--verify", "--strict", str(updated), expected_success=False)
    print("PASS: modifying a signed resource is rejected.")

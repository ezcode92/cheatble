#!/usr/bin/env python3
"""Create a persistent local signing identity without changing certificate trust settings."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

os.umask(0o077)
directory = Path.home() / "Library/Application Support/Cheatble/Signing"
configuration = directory / "identity.json"
if configuration.exists():
    print(f"Existing signing configuration retained: {configuration}")
    raise SystemExit(0)

keychain = subprocess.check_output(
    ["/usr/bin/security", "default-keychain", "-d", "user"], text=True
).strip().strip('"')
if not Path(keychain).is_file():
    raise SystemExit("A user keychain is required to store the private signing key.")

with tempfile.TemporaryDirectory(prefix="cheatble-signing-", dir="/private/tmp") as temporary:
    scratch = Path(temporary)
    config = scratch / "certificate.cnf"
    config.write_text("""[req]
prompt = no
distinguished_name = identity
x509_extensions = signing
[identity]
CN = Cheatble Local Code Signing
O = Cheatble Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
    def run(*arguments):
        result = subprocess.run(arguments, capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(f"{Path(arguments[0]).name} failed: {result.stderr.strip()}")

    run("/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:3072", "-nodes",
        "-sha256", "-days", "3650", "-config", str(config),
        "-keyout", str(scratch / "private.pem"), "-out", str(scratch / "certificate.pem"))
    run("/usr/bin/openssl", "x509", "-in", str(scratch / "certificate.pem"),
        "-outform", "der", "-out", str(scratch / "certificate.der"))
    temporary_password = secrets.token_urlsafe(32)
    run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(scratch / "private.pem"),
        "-in", str(scratch / "certificate.pem"), "-out", str(scratch / "identity.p12"),
        "-passout", "pass:" + temporary_password)
    # Only codesign may use this key without an additional Keychain prompt.
    # Import does not make this certificate a trusted system/user root.
    run("/usr/bin/security", "import", str(scratch / "identity.p12"), "-k", keychain,
        "-f", "pkcs12", "-P", temporary_password, "-x", "-T", "/usr/bin/codesign")
    certificate = (scratch / "certificate.der").read_bytes()
    fingerprint = hashlib.sha1(certificate).hexdigest().upper()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    (directory / "certificate.der").write_bytes(certificate)
    configuration.write_text(json.dumps({
        "schemaVersion": 1, "sha1": fingerprint, "keychain": keychain,
        "commonName": "Cheatble Local Code Signing",
    }, indent=2) + "\n")
    print(f"Local signing certificate: {fingerprint}")
    print(f"Private key stored non-extractably in: {keychain}")
    print("Certificate trust settings were not changed.")
    print(f"Configuration: {configuration}")

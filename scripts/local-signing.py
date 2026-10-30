#!/usr/bin/env python3
"""Reuse a private, machine-local signing identity for local Xcode installs."""

import hashlib
import os
from pathlib import Path
import secrets
import shlex
import ssl
import subprocess
import sys
import tempfile


def run(*args, env=None):
    # Do not echo commands: security takes keychain passwords as arguments.
    result = subprocess.run(args, capture_output=True, text=True, env=env)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed: {result.stderr.strip()}")
    return result.stdout


def signing_identity():
    root = Path.home() / "Library/Application Support/BetterBetterCapture/Signing"
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    keychain = root / "local-signing.keychain-db"
    password_file = root / "keychain-password"
    certificate = root / "certificate.pem"

    if not keychain.exists():
        if password_file.exists() or certificate.exists():
            raise RuntimeError(f"Incomplete signing state in {root}; restore it before continuing.")
        password = secrets.token_urlsafe(48)
        with tempfile.TemporaryDirectory(prefix="setup-", dir=root) as scratch:
            scratch = Path(scratch)
            private_key = scratch / "private-key.pem"
            new_certificate = scratch / "certificate.pem"
            archive = scratch / "identity.p12"
            run("/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256",
                "-nodes", "-days", "3650", "-subj", "/CN=BetterBetterCapture Local Signing/",
                "-addext", "basicConstraints=critical,CA:FALSE",
                "-addext", "keyUsage=critical,digitalSignature",
                "-addext", "extendedKeyUsage=critical,codeSigning",
                "-keyout", str(private_key), "-out", str(new_certificate))
            environment = dict(os.environ, BBC_SIGNING_PASSWORD=password)
            run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(private_key),
                "-in", str(new_certificate), "-out", str(archive),
                "-passout", "env:BBC_SIGNING_PASSWORD", env=environment)
            run("/usr/bin/security", "create-keychain", "-p", password, str(keychain))
            password_file.write_text(password)
            password_file.chmod(0o600)
            certificate.write_bytes(new_certificate.read_bytes())
            run("/usr/bin/security", "import", str(archive), "-k", str(keychain),
                "-P", password, "-x", "-T", "/usr/bin/codesign")
            run("/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:",
                "-s", "-k", password, str(keychain))
        print("Created persistent local signing identity (no Apple account required).", flush=True)

    if not password_file.exists() or not certificate.exists():
        raise RuntimeError(f"Missing signing credentials in {root}; restore them, do not regenerate.")
    password = password_file.read_text()
    run("/usr/bin/security", "unlock-keychain", "-p", password, str(keychain))
    run("/usr/bin/security", "set-keychain-settings", "-l", "-u", "-t", "3600", str(keychain))
    # Xcode resolves CODE_SIGN_IDENTITY through the user's keychain search list.
    keychains = shlex.split(run("/usr/bin/security", "list-keychains", "-d", "user"))
    if str(keychain) not in keychains:
        run("/usr/bin/security", "list-keychains", "-d", "user", "-s", *keychains, str(keychain))
    trusted = subprocess.run([
        "/usr/bin/security", "verify-cert", "-q", "-L", "-p", "codeSign",
        "-c", str(certificate), "-k", str(keychain),
    ], capture_output=True)
    if trusted.returncode:
        # Trust only this local certificate for code signing, in the user domain.
        run("/usr/bin/security", "add-trusted-cert", "-r", "trustRoot", "-p", "codeSign",
            "-k", str(keychain), str(certificate))
    der = ssl.PEM_cert_to_DER_cert(certificate.read_text())
    fingerprint = hashlib.sha1(der).hexdigest().upper()
    identities = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning", str(keychain))
    if fingerprint not in identities:
        raise RuntimeError("The existing local signing identity is not valid; installation stopped.")
    return fingerprint, keychain


def main():
    if len(sys.argv) < 3 or sys.argv[1] != "--":
        raise RuntimeError("Usage: local-signing.py -- xcodebuild build [arguments...]")
    os.umask(0o077)
    identity, keychain = signing_identity()
    command = sys.argv[2:] + [
        "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={identity}", "DEVELOPMENT_TEAM=",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES", "ENABLE_HARDENED_RUNTIME=NO",
        f'OTHER_CODE_SIGN_FLAGS=--keychain "{keychain}"',
    ]
    # Xcode retains its normal output and exit status; passwords are never passed to it.
    return subprocess.run(command).returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)

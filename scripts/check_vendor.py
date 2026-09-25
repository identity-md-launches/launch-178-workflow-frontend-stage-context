#!/usr/bin/env python3
"""Verify the pinned, ordinary vendored source files without network access.

Run with --write to regenerate the hash inventory after deliberately changing lib/.
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lock_path = root / "docs/dependencies.lock.json"
actual = {}
for path in sorted((root / "lib").rglob("*")):
    if path.is_symlink():
        raise SystemExit(f"Unexpected symlink: {path}")
    if path.is_file():
        actual[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()

if "--write" in sys.argv[1:]:
    lock = json.loads(lock_path.read_text())
    lock["sha256"] = actual
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"Wrote {len(actual)} vendored file hashes")
    raise SystemExit(0)

expected = json.loads(lock_path.read_text())["sha256"]
if actual != expected:
    differing = sorted(k for k in actual.keys() | expected.keys() if actual.get(k) != expected.get(k))
    raise SystemExit("Vendored files missing, changed, or added: " + ", ".join(differing))
print(f"Verified {len(actual)} vendored file hashes")

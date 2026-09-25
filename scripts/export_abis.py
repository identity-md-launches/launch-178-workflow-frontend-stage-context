#!/usr/bin/env python3
"""Export or check ABI arrays from a prior offline `forge build`. No third-party packages."""
import argparse
import json
from pathlib import Path

CONTRACTS = ("IMDOracleDisputeRegistry", "OracleChallengeToken")

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="fail on missing or stale exports")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
for contract in CONTRACTS:
    artifact = root / "out" / f"{contract}.sol" / f"{contract}.json"
    if not artifact.exists():
        raise SystemExit("Missing build artifacts; run forge build --offline first.")
    abi = json.loads(artifact.read_text())["abi"]
    target = root / "docs" / "abi" / f"{contract}.json"
    if args.check:
        if not target.exists() or json.loads(target.read_text()) != abi:
            raise SystemExit(f"ABI export missing or stale: {target.relative_to(root)}")
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(abi, indent=2) + "\n")
    print(f"{'Checked' if args.check else 'Exported'} {target.relative_to(root)}")

# Offline dependency provenance

All Solidity dependencies are committed as ordinary, unchanged upstream source files under `lib/`, with
their licences. There are no git submodules, package-manager metadata or install steps.
`docs/dependencies.lock.json` records each package's pinned revision and a SHA-256 for every vendored
file; `python3 scripts/check_vendor.py` verifies the snapshot offline (`--write` regenerates it after a
deliberate change). The hash inventory is a reproducibility aid, not a service attestation.

The formatter excludes `lib/**` in `foundry.toml`, so `forge fmt` never rewrites upstream bytes.

| Package | Pinned revision | Files | Use |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts v5.2.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/acd4ff74de833399287ed6b31b4debf6b2b35527) | `acd4ff74de833399287ed6b31b4debf6b2b35527` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`, `LICENSE` | Standard ERC-20 for `OracleChallengeToken` |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/ba4733c33497dd0c0983dcc033d7645576cc46e5) | `ba4733c33497dd0c0983dcc033d7645576cc46e5` | `src/**`, licences | Test utilities only; not part of any deployed contract |

`IMDOracleDisputeRegistry` has no dependencies at all.

Remappings are explicit in `foundry.toml`:

```
forge-std/=lib/forge-std/src/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
```

Only the minimal import closure of OpenZeppelin is included. To use more of it later, vendor and pin
the additional files and regenerate the lock rather than relying on uncommitted global dependencies.

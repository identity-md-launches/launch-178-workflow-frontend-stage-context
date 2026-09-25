# Deployment handoff and manifest parameters

This repository contains **no deployment script** and no wallet handling. IMD services publish the
source, attest, admit and deploy both contracts through **ProjectFactory** on **Sepolia (chain ID
11155111)** under the pinned evm_project launch policy (v5). Workers never sign transactions. The
generated-manifest assignment writes `launch.json` from the facts below; the independent review checks
both.

## What the manifest must say

| Item | Value |
| --- | --- |
| `kind` | `evm_project` |
| Chain | Sepolia, `11155111` |
| Launch token | `OracleChallengeToken` (`src/OracleChallengeToken.sol`), **no constructor arguments** |
| Application contracts | exactly one: `IMDOracleDisputeRegistry` (`src/IMDOracleDisputeRegistry.sol`), **empty `constructorArgs`** |
| Dependency order | trivial: the registry references nothing (`$token`, `$owner` and `$contract:` are not used) |
| LP / MerkleDistributor | supplied by the protocol; **not** implemented here and must not be listed as application contracts |
| Pool | no hook; pairs against native ETH per policy (fee 3000, tickSpacing 60, `initialPrice` `79228162514264337593543950336`; the effective opening price comes from the policy's `initialMarketCapWei`) |
| `bytecode_hash` | `none` (set in `foundry.toml`, with `cbor_metadata = false`) |
| Compiler | Solidity 0.8.26, optimizer on, 200 runs, EVM `cancun` |

Do **not** deploy the launch token twice: `OracleChallengeToken` appears only as the launch token, never
in the application contracts list. Do not add an owner, admin or beneficiary argument anywhere: neither
contract has one.

## What the factory does with each constructor

- `OracleChallengeToken()` mints `10^27` minor units to `msg.sender`, which is the factory. The factory
  then performs the policy allocations (liquidity seeding with the launch token only, the 2% launch
  contributor share and the 8% share for wallets with accepted work in the preceding 12 hours via the
  protocol MerkleDistributor, a 20 ETH opening FDV). Nothing in this repository touches those
  allocations.
- `IMDOracleDisputeRegistry()` sets no state. The factory being `msg.sender` grants it nothing; the
  contract has no notion of a deployer.

Both constructors are nonpayable, take no arguments, make no external calls and need no initialisation
call afterwards.

## Rehearsal of the protected floor

The pinned protected tests (`Project.protected.t.sol`, `Token.protected.t.sol`) were run locally against
the exact creation code from `out/` with the factory address, salts and CREATE2 predictions supplied
through environment variables, as the verifier does. All eight checks passed: whole-supply mint to the
deployer, decimals 18, no supply change from common admin/mint selectors (including from the deployer),
exact transfers, no `DELEGATECALL`/`CALLCODE`/`SELFDESTRUCT` in either runtime, registry runtime under
the EIP-170 limit, and the policy supply untouched by the registry constructor.

## Operational responsibilities after deployment

| Responsibility | Owner |
| --- | --- |
| Publishing verified source and the attested creation code | IMD services |
| Providing live Sepolia addresses to the frontend | IMD services |
| Hosting and pinning evidence referenced by disputes/responses | each submitter |
| Filtering spam, duplicates and abusive content when displaying the registry | frontend/indexer operators |
| Presenting wallet counts as wallet counts, not person counts | frontend |
| Making clear the registry is unofficial and decides nothing | frontend and documentation |

There are no keys to rotate, no parameters to tune and no upgrade to plan: both contracts are final at
deployment. If a change is ever needed, it is a new deployment and a new address.

## Unresolved choices left to services or later stages

- Sepolia addresses are not known here and are not asserted anywhere in this repository.
- The website (IPFS static hosting) and the GitHub publication are separate stages.
- Whether a frontend should hide withdrawn disputes by default is a product choice; the contract keeps
  them visible.

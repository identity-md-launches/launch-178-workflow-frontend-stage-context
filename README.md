# IMD Oracle Challenges: contracts

Solidity source, tests and ABI exports for the IMD Oracle Challenges prototype on Sepolia (chain ID
**11155111**). Two contracts are delivered:

- **`IMDOracleDisputeRegistry`** ([`src/IMDOracleDisputeRegistry.sol`](src/IMDOracleDisputeRegistry.sol)):
  an unofficial, ownerless, append-only public registry where anyone can record an evidence-backed
  challenge to an IMD oracle answer, anyone can append responses, and only the challenger can withdraw
  their own challenge. No constructor arguments.
- **`OracleChallengeToken`** ([`src/OracleChallengeToken.sol`](src/OracleChallengeToken.sol)): the
  separate fixed-supply launch token **Oracle Challenge Test (OCTEST)** required by IMD's project-launch
  policy. 18 decimals, no constructor arguments, exactly 1,000,000,000 tokens (`10^27` minor units)
  minted once to `msg.sender` in the constructor. No owner, mint, admin, upgrade, fee or hook.

The registry never reads, holds or moves OCTEST. Holding or spending OCTEST is never required to open,
answer or withdraw a dispute. OCTEST is a Sepolia test token for this experiment, not the IMD payment
token, and carries no value or return promise.

The registry is **not** an oracle, an adjudicator or an appeals process. It cannot reverse IMD decisions,
penalise agents or prove that a challenged answer is wrong. It records public claims attributed to the
wallets that submitted them.

## Build and check offline

Requires Foundry with native Solidity **0.8.26** in its compiler cache and a Cancun-capable EVM. All
Solidity dependencies are vendored as ordinary files under `lib/` (see
[`docs/dependencies.md`](docs/dependencies.md)). No network, submodule, FFI, filesystem cheatcode
permission or environment variable is needed.

```sh
forge build --offline
forge test --offline
forge fmt --check
python3 scripts/export_abis.py --check   # ABI exports match the build
python3 scripts/check_vendor.py          # vendored files match the pinned hashes
```

`foundry.toml` sets `offline = true`, `bytecode_hash = "none"`, `cbor_metadata = false`, `ffi = false`
and empty `fs_permissions`. Regenerate ABI exports after a source change with
`python3 scripts/export_abis.py` following a build.

## Registry model

### Data

A **dispute** stores, immutably after creation:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `uint256` | Sequential, starting at 1. `0` is never valid. |
| `challenger` | `address` | Always the `msg.sender` of `openDispute`. |
| `requestId` | `bytes16` | The IMD oracle request UUID being challenged. Non-zero. |
| `sourceChainId` | `uint256` | The chain the oracle request was *about*. Non-zero. Not the registry's own chain. |
| `attestationSnapshotHash` | `bytes32` | `keccak256` of the exact downloaded attestation JSON bytes. Non-zero. |
| `evidenceHash` | `bytes32` | `keccak256` of the exact evidence bytes at `evidenceURI`. Non-zero. |
| `evidenceURI` | `string` | 1–512 bytes. Where the evidence is hosted. |
| `rationale` | `string` | 1–280 UTF-8 bytes. |
| `createdAt` | `uint64` | `block.timestamp` at creation. |
| `withdrawnAt` | `uint64` | `block.timestamp` at withdrawal, `0` while Open. |
| `status` | `enum` | `0` = Open, `1` = Withdrawn. The only mutable field. |

A **response** stores, immutably: `author` (always the `msg.sender` of `respond`), `evidenceHash`
(non-zero), `evidenceURI` (1–512 bytes), `text` (1–280 UTF-8 bytes) and `createdAt`. Responses are
indexed from `0` per dispute, in append order.

### State transitions

There are exactly two states and one transition.

| From | Action | Who | To | Effect |
| --- | --- | --- | --- | --- |
| — | `openDispute(...)` | anyone | Open | New record with `id = disputeCount() + 1`, `challenger = msg.sender`. Emits `DisputeOpened`. |
| Open | `respond(id, ...)` | anyone (including the challenger) | Open | Appends a response with `author = msg.sender`. Emits `ResponseAdded`. |
| Open | `withdrawDispute(id)` | the challenger only | Withdrawn | Sets `status` and `withdrawnAt`. Every other field and every response is kept. Emits `DisputeWithdrawn`. |
| Withdrawn | `respond` / `withdrawDispute` | anyone | — | Reverts with `DisputeNotOpen`. |

Nothing can be edited or deleted by anyone, ever. There is no resolution, verdict, acceptance, rejection,
reopening, expiry or administrator override. Withdrawal is the challenger's own statement that they no
longer stand behind the dispute; it does not remove the dispute from the public record.

### Validation (all revert with a named custom error)

| Condition | Error |
| --- | --- |
| `requestId == 0` | `ZeroRequestId()` |
| `sourceChainId == 0` | `ZeroSourceChainId()` |
| `attestationSnapshotHash == 0` | `ZeroAttestationSnapshotHash()` |
| `evidenceHash == 0` | `ZeroEvidenceHash()` |
| rationale/text not 1–280 bytes | `InvalidTextLength(uint256 length)` |
| URI not 1–512 bytes | `InvalidURILength(uint256 length)` |
| dispute id `0` or `> disputeCount()` | `DisputeNotFound(uint256 disputeId)` |
| respond/withdraw on a Withdrawn dispute | `DisputeNotOpen(uint256 disputeId)` |
| withdraw by anyone but the challenger | `NotChallenger(uint256 disputeId, address caller)` |
| page limit not 1–50 | `InvalidPageLimit(uint256 limit)` |
| page offset at or past the end (non-empty), or non-zero (empty) | `OffsetOutOfBounds(uint256 offset, uint256 total)` |
| response index past the end | `ResponseNotFound(uint256 disputeId, uint256 index)` |

Lengths are measured in **bytes**, not characters: a 280-character rationale of multi-byte UTF-8 is
rejected. The contract does not validate UTF-8 encoding or URI syntax.

### Reads and pagination

- `disputeCount()` and `responseCount(id)`.
- `getDispute(id)` and `getResponse(id, index)` for single items.
- `getDisputes(offset, limit)` and `getResponses(id, offset, limit)` return at most `limit` (1–50)
  items starting at the zero-based `offset`, in id/append order. The last page is shorter, not padded.
  On an empty collection only `offset = 0` is accepted and an empty array is returned; on a non-empty
  collection `offset` must be `< total`, so a caller cannot silently read past the end. To page through
  everything: start at `0`, add the returned length, stop when `offset == total`.

### Hash encoding

`attestationSnapshotHash` is expected to be `keccak256(bytes)` of the attestation JSON **exactly as
downloaded** from IMD: no re-serialisation, no key sorting, no whitespace or newline normalisation.
`evidenceHash` is expected to be `keccak256(bytes)` of the exact bytes hosted at `evidenceURI`. A reader
verifies a commitment by downloading the same bytes and hashing them; if they differ, either the
document changed or the challenger committed to something else. The contract never computes or checks
these hashes. `keccak256`, not SHA-256, and no `0x`/hex-string pre-processing: hash the raw bytes.

### Public-data semantics and limitations

- **Everything is user-submitted.** `requestId`, `sourceChainId`, both hashes, both URIs and all text
  are stored verbatim. The registry cannot know whether the request exists, whether the snapshot hash
  matches a real attestation, whether the URI resolves, or whether the evidence supports the rationale.
- **Source-chain identity is a claim.** The registry lives on Sepolia; `sourceChainId` is whatever the
  challenger typed. It is kept separately so consumers can filter, not because it was verified.
- **Evidence hosting is external.** The contract stores a URI and a hash. Availability, persistence and
  pinning (IPFS, HTTPS, Arweave, ...) are the submitter's responsibility. A dead URI leaves the hash as
  the only record.
- **No spam or Sybil resistance.** Opening a dispute or response costs only gas. There is no fee, bond,
  stake, allow-list, rate limit or deduplication. Many disputes from many wallets do not imply many
  people; the same wallet may open duplicate disputes for the same request. Off-chain consumers (the
  website, indexers) must apply their own filtering and should present wallet counts as wallet counts.
- **No moderation.** Text and URIs are arbitrary bytes. Anyone reading them, including a website, must
  treat them as untrusted content.
- **Timestamps** are `block.timestamp` and are only as precise as Sepolia block production.
- **Not an outcome.** Neither a dispute's existence nor its withdrawal says anything about whether the
  oracle answer was correct.

### No admin, no value, no dependencies

The registry has no owner, role, pause, upgrade, proxy, `selfdestruct`, `delegatecall`, or external
call of any kind. It has no `receive` or `fallback` function and no `payable` function, so it rejects
all ETH. It never references any token. The deployer (IMD's ProjectFactory) holds no privilege: tests
show it cannot withdraw anyone else's dispute. A runtime-bytecode scan in the tests confirms no
`CALL`, `CALLCODE`, `DELEGATECALL`, `STATICCALL`, `CREATE`, `CREATE2` or `SELFDESTRUCT` opcode.

## ABIs

Implementation-derived ABI arrays exported from the build artifacts:

- [`docs/abi/IMDOracleDisputeRegistry.json`](docs/abi/IMDOracleDisputeRegistry.json)
- [`docs/abi/OracleChallengeToken.json`](docs/abi/OracleChallengeToken.json)

[`docs/abi.md`](docs/abi.md) lists each function, event and error with usage notes for the website.

## Deployment and launch manifest

Services deploy both contracts through ProjectFactory; workers never sign transactions and this
repository contains no deployment script. [`docs/deployment.md`](docs/deployment.md) documents the
parameters the generated `launch.json` must use:

- `OracleChallengeToken` is the **launch token** (no constructor arguments).
- `IMDOracleDisputeRegistry` is the **sole application contract**, with empty `constructorArgs`.
- Deploy the launch token once only; the protocol supplies the LP and MerkleDistributor.

## Tests

`test/IMDOracleDisputeRegistry.t.sol` (unit and fuzz), `test/IMDOracleDisputeRegistry.invariant.t.sol`
(stateful: history is append-only and immutable, pages agree with single reads, no ETH),
`test/OracleChallengeToken.t.sol` (metadata, single mint, bare creation code, transfer exactness,
admin/mint selectors, opcode scan). Passing tests are not a security audit; the workflow's independent
adversarial review follows this stage. See [`docs/security.md`](docs/security.md).

## Licence

MIT (see [`LICENSE`](LICENSE)). Vendored dependencies keep their own licences under `lib/`.

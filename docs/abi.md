# ABI reference

Both JSON files under `docs/abi/` are the `abi` arrays taken verbatim from the Foundry build artifacts
(`python3 scripts/export_abis.py`; `--check` verifies they are current). They are what the website and
indexers should load.

## `IMDOracleDisputeRegistry` — `docs/abi/IMDOracleDisputeRegistry.json`

Constructor: none (no arguments). Not payable. No `receive`/`fallback`.

### Write functions

| Function | Access | Notes |
| --- | --- | --- |
| `openDispute(bytes16 requestId, uint256 sourceChainId, bytes32 attestationSnapshotHash, bytes32 evidenceHash, string evidenceURI, string rationale) returns (uint256 disputeId)` | anyone | Ids start at 1. `challenger = msg.sender`. |
| `respond(uint256 disputeId, bytes32 evidenceHash, string evidenceURI, string text) returns (uint256 responseIndex)` | anyone, Open only | Index is zero-based per dispute. `author = msg.sender`. |
| `withdrawDispute(uint256 disputeId)` | challenger only, Open only | Sets status to Withdrawn; keeps everything. |

### Read functions

| Function | Notes |
| --- | --- |
| `disputeCount() returns (uint256)` | Ids are `1..disputeCount()`. |
| `responseCount(uint256 disputeId) returns (uint256)` | Reverts for unknown ids. |
| `getDispute(uint256 disputeId) returns (Dispute)` | Struct tuple, field order below. |
| `getResponse(uint256 disputeId, uint256 index) returns (Response)` | Reverts for unknown id or index. |
| `getDisputes(uint256 offset, uint256 limit) returns (Dispute[])` | `limit` 1–50; `offset < total` (or `0` when empty). |
| `getResponses(uint256 disputeId, uint256 offset, uint256 limit) returns (Response[])` | Same bounds. |
| `MAX_TEXT_BYTES()`, `MAX_URI_BYTES()`, `MAX_PAGE_LIMIT()` | 280, 512, 50. |

`Dispute` tuple order: `id, challenger, requestId, sourceChainId, attestationSnapshotHash, evidenceHash,
evidenceURI, rationale, createdAt, withdrawnAt, status` (status: `0` Open, `1` Withdrawn).

`Response` tuple order: `author, evidenceHash, evidenceURI, text, createdAt`.

### Events

| Event | Indexed | Use |
| --- | --- | --- |
| `DisputeOpened(uint256 disputeId, address challenger, bytes16 requestId, uint256 sourceChainId, bytes32 attestationSnapshotHash, bytes32 evidenceHash, string evidenceURI, string rationale, uint64 createdAt)` | `disputeId`, `challenger`, `requestId` | Filter all disputes for one request UUID or one wallet. |
| `ResponseAdded(uint256 disputeId, uint256 responseIndex, address author, bytes32 evidenceHash, string evidenceURI, string text, uint64 createdAt)` | `disputeId`, `responseIndex`, `author` | Filter a dispute's thread or one wallet's responses. |
| `DisputeWithdrawn(uint256 disputeId, address challenger, uint64 withdrawnAt)` | `disputeId`, `challenger` | |

Because `requestId` is `bytes16` and indexed, its topic is the 16 bytes left-aligned in a 32-byte word
(padded with zeros on the right), which is how Solidity encodes fixed-size bytes topics.

### Errors

`ZeroRequestId()`, `ZeroSourceChainId()`, `ZeroAttestationSnapshotHash()`, `ZeroEvidenceHash()`,
`InvalidTextLength(uint256)`, `InvalidURILength(uint256)`, `DisputeNotFound(uint256)`,
`DisputeNotOpen(uint256)`, `NotChallenger(uint256,address)`, `InvalidPageLimit(uint256)`,
`OffsetOutOfBounds(uint256,uint256)`, `ResponseNotFound(uint256,uint256)`.

### Encoding a request UUID as `bytes16`

An IMD oracle request UUID such as `0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50` is the 16 bytes of its hex
digits with the hyphens removed: `0x0192d5f8a3b14c6e9f2a7b8c1d3e4f50`. The all-zero UUID is rejected.

### Computing the commitments

```
attestationSnapshotHash = keccak256(<exact bytes of the attestation JSON as downloaded>)
evidenceHash            = keccak256(<exact bytes hosted at evidenceURI>)
```

Hash the raw bytes (not a hex string, not re-serialised JSON). Zero is rejected for both.

## `OracleChallengeToken` — `docs/abi/OracleChallengeToken.json`

Standard ERC-20 (OpenZeppelin v5.2.0) plus `TOTAL_SUPPLY()` = `1000000000000000000000000000`.

Constructor: none (no arguments). `name()` = `Oracle Challenge Test`, `symbol()` = `OCTEST`,
`decimals()` = `18`. Functions: `totalSupply`, `balanceOf`, `transfer`, `allowance`, `approve`,
`transferFrom`. Events: `Transfer`, `Approval`. Errors: the ERC-6093 set (`ERC20InsufficientBalance`,
`ERC20InvalidSender`, `ERC20InvalidReceiver`, `ERC20InsufficientAllowance`, `ERC20InvalidApprover`,
`ERC20InvalidSpender`). There is no mint, burn, owner, pause, permit or hook function.

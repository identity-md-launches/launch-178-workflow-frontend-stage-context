# Security design notes and review handoff

These notes accompany the source for the independent adversarial review that follows this stage. They
describe what was designed, what the tests cover and what remains a judgement call. Passing tests are
not an audit.

## Threat model

The registry holds no funds, no tokens and no privileged roles, so the classic attack surface (custody,
reentrancy, oracle manipulation, admin abuse, upgrade hijack) is absent by construction rather than by
mitigation. What remains:

| Concern | Position |
| --- | --- |
| Impersonation | Attribution is literally `msg.sender`; never `tx.origin`, never a signed message. A contract wallet is recorded as the contract. Tested. |
| Unauthorized withdrawal | Only `dispute.challenger == msg.sender`. The deployer/factory, responders and third parties are rejected. Unit, fuzz and invariant tested. |
| Tampering or deletion | No function writes to any field except `status`/`withdrawnAt` on withdrawal. The invariant suite mirrors every stored value across random call sequences and asserts equality. |
| Late responses | `respond` checks `status == Open`. Tested before and after withdrawal, including by the challenger. |
| Zero / garbage commitments | Zero `requestId`, `sourceChainId`, snapshot hash and evidence hash are rejected. Non-zero garbage is accepted by design: the contract cannot verify content, and rejecting "unlikely" values would be security theatre. Documented. |
| Length bombs | Text 1–280 bytes, URI 1–512 bytes. Bounded storage per record. |
| Gas griefing of reads | Pagination limit 1–50, offsets validated. No unbounded loop exists in any write path. `getDisputes` reads at most 50 records with two strings each, comfortably within RPC `eth_call` limits. |
| ETH | No `payable`, `receive` or `fallback`; all value transfers revert. Tested with and without calldata; invariant asserts zero balance. |
| External calls | None. The runtime-bytecode scan in the tests asserts no `CALL`, `STATICCALL`, `CALLCODE`, `DELEGATECALL`, `CREATE`, `CREATE2` or `SELFDESTRUCT`. |
| Spam / Sybil | Not mitigated on-chain and not claimed to be. Anyone can open unlimited disputes for unlimited request ids from unlimited wallets. Documented in the README as a consumer-side problem. |
| Timestamp manipulation | `createdAt`/`withdrawnAt` are informational; no logic depends on them. |
| Id exhaustion | Ids are `uint256`; `disputeCount()` cannot realistically overflow. |

## Token

`OracleChallengeToken` is unmodified OpenZeppelin v5.2.0 `ERC20` with a constructor that mints the whole
supply once to `msg.sender`. There is no `_mint` call reachable after construction, no owner, no
`_update` override, no hook. The protected floor and the local tests both confirm supply is fixed and
transfers are exact. It exists only to satisfy the launch policy; the registry does not know it exists.

## What the tests exercise

- Every revert path with its exact custom error and arguments.
- Boundary lengths (0, 1, 280, 281, 512, 513) and UTF-8 byte counting.
- Fuzzed callers, request ids, chain ids and hashes for attribution.
- Fuzzed page walks proving each dispute is returned exactly once.
- Stateful invariant runs (64 runs × 32 calls) with a mirrored model of all stored data.
- A pretend-factory deployer and a contract-wallet caller.
- The pinned protected floor (see `docs/deployment.md`).

## What the tests do not establish (for the reviewer)

- That off-chain consumers handle untrusted strings safely (XSS, URI schemes such as `javascript:`).
  The contract stores arbitrary bytes.
- That a `requestId` corresponds to a real IMD request, or that any hash matches any document.
- Anything about the website, the IPFS hosting or the GitHub publication.
- Gas economics on Sepolia under adversarial volume; the registry does not attempt to limit volume.

## Suggested review focus

1. Confirm there is no path that mutates a stored dispute or response other than the withdrawal status.
2. Confirm `withdrawDispute` cannot be reached by the factory, an operator, or via any selector.
3. Confirm the manifest lists the token once and the registry with empty `constructorArgs`.
4. Confirm the README's public-data caveats are reflected in the frontend copy in the next stage.

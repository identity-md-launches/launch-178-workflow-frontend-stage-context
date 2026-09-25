// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IMD Oracle Dispute Registry
/// @notice An unofficial, ownerless, append-only public registry of challenges to IMD oracle answers.
///
/// Anyone may open a dispute against an oracle request, anyone may append a response while the dispute is
/// open, and only the original challenger may withdraw their own open dispute. Nothing is ever edited or
/// deleted: a withdrawn dispute keeps every field and every response, it simply stops accepting new
/// responses.
///
/// What this contract is NOT:
/// - It is not an oracle, an adjudicator or an appeals process. It records claims; it never decides
///   whether a challenged answer is wrong, never reverses an IMD decision and never penalises anyone.
/// - It performs no verification. `requestId`, `sourceChainId`, `attestationSnapshotHash`,
///   `evidenceHash`, `evidenceURI` and all free text are user-submitted values stored verbatim. The
///   contract cannot check that the request exists, that the snapshot hash matches a real attestation,
///   or that a URI resolves to anything. Readers must fetch the evidence themselves and compare
///   `keccak256(bytes)` of what they download with the recorded commitment.
/// - It has no administrator, no upgrade path, no pause, no fees, no bonds, no rewards and no token
///   dependency. It accepts no ETH (no `receive`/`fallback`, no `payable` function) and it makes no
///   external calls of any kind.
/// - It does not rate-limit or deduplicate. Wallets are cheap: many disputes or responses from many
///   addresses do not imply many people. Off-chain consumers must apply their own spam filtering.
///
/// Hash encoding: `attestationSnapshotHash` is expected to be `keccak256` of the exact bytes of the
/// attestation JSON as downloaded (no re-serialisation, no whitespace normalisation); `evidenceHash` is
/// expected to be `keccak256` of the exact bytes hosted at `evidenceURI`. Both are user commitments.
///
/// Chain identity: the registry itself lives on one chain (Sepolia for this experiment) while the oracle
/// request it refers to may have been answered about a different `sourceChainId`. That field is a claim
/// by the challenger, not something the registry can confirm.
contract IMDOracleDisputeRegistry {
    // ---------------------------------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------------------------------

    /// @notice Lifecycle of a dispute. There are exactly two states and one transition: Open -> Withdrawn.
    enum DisputeStatus {
        Open,
        Withdrawn
    }

    /// @notice A recorded challenge. Every field except `status` is immutable after creation.
    struct Dispute {
        /// @dev Sequential identifier, starting at 1. Zero is never a valid dispute id.
        uint256 id;
        /// @dev The wallet that opened the dispute; always the `msg.sender` of `openDispute`.
        address challenger;
        /// @dev The IMD oracle request UUID being challenged (user-supplied claim).
        bytes16 requestId;
        /// @dev The chain the oracle request was about (user-supplied claim; not this registry's chain).
        uint256 sourceChainId;
        /// @dev keccak256 of the exact downloaded attestation JSON bytes (user-supplied commitment).
        bytes32 attestationSnapshotHash;
        /// @dev keccak256 of the exact evidence bytes hosted at `evidenceURI` (user-supplied commitment).
        bytes32 evidenceHash;
        /// @dev Where the evidence can be fetched. Hosting and availability are external to the contract.
        string evidenceURI;
        /// @dev Short human-readable reason, 1-280 UTF-8 bytes.
        string rationale;
        /// @dev `block.timestamp` at creation.
        uint64 createdAt;
        /// @dev `block.timestamp` at withdrawal, zero while Open.
        uint64 withdrawnAt;
        /// @dev Current status.
        DisputeStatus status;
    }

    /// @notice An appended response to a dispute. Immutable once stored.
    struct Response {
        /// @dev The wallet that wrote the response; always the `msg.sender` of `respond`.
        address author;
        /// @dev keccak256 of the exact evidence bytes hosted at `evidenceURI` (user-supplied commitment).
        bytes32 evidenceHash;
        /// @dev Where the evidence can be fetched. Hosting and availability are external to the contract.
        string evidenceURI;
        /// @dev Short human-readable text, 1-280 UTF-8 bytes.
        string text;
        /// @dev `block.timestamp` at creation.
        uint64 createdAt;
    }

    // ---------------------------------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------------------------------

    /// @notice Maximum length in UTF-8 bytes of a dispute rationale or response text.
    uint256 public constant MAX_TEXT_BYTES = 280;
    /// @notice Maximum length in bytes of an evidence URI.
    uint256 public constant MAX_URI_BYTES = 512;
    /// @notice Maximum number of items a pagination getter returns per call.
    uint256 public constant MAX_PAGE_LIMIT = 50;

    // ---------------------------------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------------------------------

    error ZeroRequestId();
    error ZeroSourceChainId();
    error ZeroAttestationSnapshotHash();
    error ZeroEvidenceHash();
    /// @dev Thrown when a rationale or response text is empty or longer than `MAX_TEXT_BYTES`.
    error InvalidTextLength(uint256 length);
    /// @dev Thrown when an evidence URI is empty or longer than `MAX_URI_BYTES`.
    error InvalidURILength(uint256 length);
    /// @dev Thrown when a dispute id is zero or larger than `disputeCount()`.
    error DisputeNotFound(uint256 disputeId);
    /// @dev Thrown when responding to or withdrawing a dispute that is not Open.
    error DisputeNotOpen(uint256 disputeId);
    /// @dev Thrown when someone other than the challenger tries to withdraw.
    error NotChallenger(uint256 disputeId, address caller);
    /// @dev Thrown when a pagination limit is zero or larger than `MAX_PAGE_LIMIT`.
    error InvalidPageLimit(uint256 limit);
    /// @dev Thrown when a pagination offset is beyond the end of the collection.
    error OffsetOutOfBounds(uint256 offset, uint256 total);
    /// @dev Thrown when a response index is beyond the end of a dispute's responses.
    error ResponseNotFound(uint256 disputeId, uint256 index);

    // ---------------------------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------------------------

    event DisputeOpened(
        uint256 indexed disputeId,
        address indexed challenger,
        bytes16 indexed requestId,
        uint256 sourceChainId,
        bytes32 attestationSnapshotHash,
        bytes32 evidenceHash,
        string evidenceURI,
        string rationale,
        uint64 createdAt
    );

    event ResponseAdded(
        uint256 indexed disputeId,
        uint256 indexed responseIndex,
        address indexed author,
        bytes32 evidenceHash,
        string evidenceURI,
        string text,
        uint64 createdAt
    );

    event DisputeWithdrawn(uint256 indexed disputeId, address indexed challenger, uint64 withdrawnAt);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    /// @dev Disputes indexed by `id - 1`; `_disputes.length` is the dispute count.
    Dispute[] private _disputes;
    /// @dev Responses per dispute id, in append order.
    mapping(uint256 disputeId => Response[]) private _responses;

    // ---------------------------------------------------------------------------------------------
    // Write functions
    // ---------------------------------------------------------------------------------------------

    /// @notice Open a new dispute. Anyone may call; the recorded challenger is always `msg.sender`.
    /// @param requestId The oracle request UUID being challenged (16 bytes, non-zero).
    /// @param sourceChainId The chain the oracle request was about (non-zero).
    /// @param attestationSnapshotHash keccak256 of the exact downloaded attestation JSON bytes (non-zero).
    /// @param evidenceHash keccak256 of the exact evidence bytes hosted at `evidenceURI` (non-zero).
    /// @param evidenceURI Where the evidence is hosted, 1-512 bytes.
    /// @param rationale Short reason, 1-280 UTF-8 bytes.
    /// @return disputeId The sequential id of the new dispute (starting at 1).
    function openDispute(
        bytes16 requestId,
        uint256 sourceChainId,
        bytes32 attestationSnapshotHash,
        bytes32 evidenceHash,
        string calldata evidenceURI,
        string calldata rationale
    ) external returns (uint256 disputeId) {
        if (requestId == bytes16(0)) revert ZeroRequestId();
        if (sourceChainId == 0) revert ZeroSourceChainId();
        if (attestationSnapshotHash == bytes32(0)) revert ZeroAttestationSnapshotHash();
        if (evidenceHash == bytes32(0)) revert ZeroEvidenceHash();
        _checkURI(evidenceURI);
        _checkText(rationale);

        disputeId = _disputes.length + 1;
        uint64 now64 = _timestamp();
        _disputes.push(
            Dispute({
                id: disputeId,
                challenger: msg.sender,
                requestId: requestId,
                sourceChainId: sourceChainId,
                attestationSnapshotHash: attestationSnapshotHash,
                evidenceHash: evidenceHash,
                evidenceURI: evidenceURI,
                rationale: rationale,
                createdAt: now64,
                withdrawnAt: 0,
                status: DisputeStatus.Open
            })
        );

        emit DisputeOpened(
            disputeId,
            msg.sender,
            requestId,
            sourceChainId,
            attestationSnapshotHash,
            evidenceHash,
            evidenceURI,
            rationale,
            now64
        );
    }

    /// @notice Append a response to an Open dispute. Anyone may call; the recorded author is `msg.sender`.
    /// @param disputeId The dispute to respond to.
    /// @param evidenceHash keccak256 of the exact evidence bytes hosted at `evidenceURI` (non-zero).
    /// @param evidenceURI Where the evidence is hosted, 1-512 bytes.
    /// @param text Short response, 1-280 UTF-8 bytes.
    /// @return responseIndex The zero-based index of the new response within the dispute.
    function respond(
        uint256 disputeId,
        bytes32 evidenceHash,
        string calldata evidenceURI,
        string calldata text
    ) external returns (uint256 responseIndex) {
        Dispute storage dispute = _getDispute(disputeId);
        if (dispute.status != DisputeStatus.Open) revert DisputeNotOpen(disputeId);
        if (evidenceHash == bytes32(0)) revert ZeroEvidenceHash();
        _checkURI(evidenceURI);
        _checkText(text);

        Response[] storage responses = _responses[disputeId];
        responseIndex = responses.length;
        uint64 now64 = _timestamp();
        responses.push(
            Response({
                author: msg.sender,
                evidenceHash: evidenceHash,
                evidenceURI: evidenceURI,
                text: text,
                createdAt: now64
            })
        );

        emit ResponseAdded(disputeId, responseIndex, msg.sender, evidenceHash, evidenceURI, text, now64);
    }

    /// @notice Withdraw an Open dispute. Only the original challenger may call. All records are preserved.
    /// @param disputeId The dispute to withdraw.
    function withdrawDispute(uint256 disputeId) external {
        Dispute storage dispute = _getDispute(disputeId);
        if (dispute.challenger != msg.sender) revert NotChallenger(disputeId, msg.sender);
        if (dispute.status != DisputeStatus.Open) revert DisputeNotOpen(disputeId);

        uint64 now64 = _timestamp();
        dispute.status = DisputeStatus.Withdrawn;
        dispute.withdrawnAt = now64;

        emit DisputeWithdrawn(disputeId, msg.sender, now64);
    }

    // ---------------------------------------------------------------------------------------------
    // Read functions
    // ---------------------------------------------------------------------------------------------

    /// @notice Total number of disputes ever opened. Dispute ids run from 1 to this value inclusive.
    function disputeCount() external view returns (uint256) {
        return _disputes.length;
    }

    /// @notice Number of responses appended to a dispute.
    function responseCount(uint256 disputeId) external view returns (uint256) {
        _getDispute(disputeId);
        return _responses[disputeId].length;
    }

    /// @notice Fetch a single dispute by id.
    function getDispute(uint256 disputeId) external view returns (Dispute memory) {
        return _getDispute(disputeId);
    }

    /// @notice Fetch a single response by dispute id and zero-based index.
    function getResponse(uint256 disputeId, uint256 index) external view returns (Response memory) {
        _getDispute(disputeId);
        Response[] storage responses = _responses[disputeId];
        if (index >= responses.length) revert ResponseNotFound(disputeId, index);
        return responses[index];
    }

    /// @notice Page through disputes in id order.
    /// @param offset Zero-based position of the first dispute to return (dispute id = offset + 1).
    ///        Must be strictly less than `disputeCount()` unless the count is zero, in which case
    ///        only offset 0 is accepted and an empty page is returned.
    /// @param limit Maximum number of disputes to return, 1-50.
    /// @return page The disputes from `offset`, at most `limit` of them, fewer at the end.
    function getDisputes(uint256 offset, uint256 limit) external view returns (Dispute[] memory page) {
        uint256 total = _disputes.length;
        uint256 size = _pageSize(offset, limit, total);
        page = new Dispute[](size);
        for (uint256 i; i < size; ++i) {
            page[i] = _disputes[offset + i];
        }
    }

    /// @notice Page through the responses of a dispute in append order.
    /// @param disputeId The dispute whose responses to read.
    /// @param offset Zero-based index of the first response to return; same bounds rule as `getDisputes`.
    /// @param limit Maximum number of responses to return, 1-50.
    function getResponses(uint256 disputeId, uint256 offset, uint256 limit)
        external
        view
        returns (Response[] memory page)
    {
        _getDispute(disputeId);
        Response[] storage responses = _responses[disputeId];
        uint256 size = _pageSize(offset, limit, responses.length);
        page = new Response[](size);
        for (uint256 i; i < size; ++i) {
            page[i] = responses[offset + i];
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------------------------------

    /// @dev `block.timestamp` fits in 64 bits for the next ~584 billion years; the cast cannot truncate.
    function _timestamp() private view returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(block.timestamp);
    }

    function _getDispute(uint256 disputeId) private view returns (Dispute storage) {
        if (disputeId == 0 || disputeId > _disputes.length) revert DisputeNotFound(disputeId);
        return _disputes[disputeId - 1];
    }

    function _checkText(string calldata text) private pure {
        uint256 length = bytes(text).length;
        if (length == 0 || length > MAX_TEXT_BYTES) revert InvalidTextLength(length);
    }

    function _checkURI(string calldata uri) private pure {
        uint256 length = bytes(uri).length;
        if (length == 0 || length > MAX_URI_BYTES) revert InvalidURILength(length);
    }

    /// @dev Validates `limit` in 1..MAX_PAGE_LIMIT and `offset` against `total`, and returns the page size.
    /// An empty collection accepts only offset 0 (returning zero items); a non-empty one requires
    /// `offset < total` so callers cannot silently read past the end.
    function _pageSize(uint256 offset, uint256 limit, uint256 total) private pure returns (uint256) {
        if (limit == 0 || limit > MAX_PAGE_LIMIT) revert InvalidPageLimit(limit);
        if (offset > total || (offset == total && total != 0)) revert OffsetOutOfBounds(offset, total);
        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }
}

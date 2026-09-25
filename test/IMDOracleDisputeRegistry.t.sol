// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDOracleDisputeRegistry} from "../src/IMDOracleDisputeRegistry.sol";

contract IMDOracleDisputeRegistryTest is Test {
    IMDOracleDisputeRegistry internal registry;

    address internal alice;
    address internal bob;
    address internal carol;

    bytes16 internal constant REQUEST_ID = bytes16(0x0192d5f8a3b14c6e9f2a7b8c1d3e4f50);
    uint256 internal constant SOURCE_CHAIN = 1;
    bytes32 internal constant SNAPSHOT_HASH = keccak256('{"request":"attestation"}');
    bytes32 internal constant EVIDENCE_HASH = keccak256("evidence bytes");
    string internal constant URI = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
    string internal constant RATIONALE = "The attested value disagrees with the on-chain event log.";

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

    function setUp() public {
        registry = new IMDOracleDisputeRegistry();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        vm.warp(1_700_000_000);
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    function _open(address who) internal returns (uint256) {
        vm.prank(who);
        return registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE);
    }

    function _respond(address who, uint256 id) internal returns (uint256) {
        vm.prank(who);
        return registry.respond(id, EVIDENCE_HASH, URI, "A response");
    }

    function _bytesOf(uint256 n) internal pure returns (string memory s) {
        bytes memory b = new bytes(n);
        for (uint256 i; i < n; ++i) {
            b[i] = "a";
        }
        s = string(b);
    }

    // ---------------------------------------------------------------------------------------------
    // Deployment shape
    // ---------------------------------------------------------------------------------------------

    function test_constants() public view {
        assertEq(registry.MAX_TEXT_BYTES(), 280);
        assertEq(registry.MAX_URI_BYTES(), 512);
        assertEq(registry.MAX_PAGE_LIMIT(), 50);
        assertEq(registry.disputeCount(), 0);
    }

    function test_emptyRegistryPagination() public view {
        IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(0, 50);
        assertEq(page.length, 0);
    }

    function test_emptyRegistryRejectsNonZeroOffset() public {
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 1, 0));
        registry.getDisputes(1, 10);
    }

    // ---------------------------------------------------------------------------------------------
    // openDispute
    // ---------------------------------------------------------------------------------------------

    function test_openDisputeStoresAllFieldsAndAttributesToSender() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit DisputeOpened(
            1,
            alice,
            REQUEST_ID,
            SOURCE_CHAIN,
            SNAPSHOT_HASH,
            EVIDENCE_HASH,
            URI,
            RATIONALE,
            uint64(block.timestamp)
        );
        uint256 id = _open(alice);
        assertEq(id, 1);
        assertEq(registry.disputeCount(), 1);

        IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(1);
        assertEq(d.id, 1);
        assertEq(d.challenger, alice);
        assertEq(d.requestId, REQUEST_ID);
        assertEq(d.sourceChainId, SOURCE_CHAIN);
        assertEq(d.attestationSnapshotHash, SNAPSHOT_HASH);
        assertEq(d.evidenceHash, EVIDENCE_HASH);
        assertEq(d.evidenceURI, URI);
        assertEq(d.rationale, RATIONALE);
        assertEq(d.createdAt, uint64(block.timestamp));
        assertEq(d.withdrawnAt, 0);
        assertEq(uint256(d.status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));
        assertEq(registry.responseCount(1), 0);
    }

    function test_idsAreSequentialAcrossWallets() public {
        assertEq(_open(alice), 1);
        assertEq(_open(bob), 2);
        assertEq(_open(alice), 3);
        assertEq(registry.disputeCount(), 3);
        assertEq(registry.getDispute(2).challenger, bob);
        assertEq(registry.getDispute(3).challenger, alice);
    }

    function test_duplicateDisputesForSameRequestAreAllowed() public {
        // The registry does not deduplicate; two identical disputes are two records.
        uint256 a = _open(alice);
        uint256 b = _open(alice);
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(registry.getDispute(1).requestId, registry.getDispute(2).requestId);
    }

    function test_openDisputeRejectsZeroRequestId() public {
        vm.prank(alice);
        vm.expectRevert(IMDOracleDisputeRegistry.ZeroRequestId.selector);
        registry.openDispute(bytes16(0), SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE);
    }

    function test_openDisputeRejectsZeroSourceChainId() public {
        vm.prank(alice);
        vm.expectRevert(IMDOracleDisputeRegistry.ZeroSourceChainId.selector);
        registry.openDispute(REQUEST_ID, 0, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE);
    }

    function test_openDisputeRejectsZeroSnapshotHash() public {
        vm.prank(alice);
        vm.expectRevert(IMDOracleDisputeRegistry.ZeroAttestationSnapshotHash.selector);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, bytes32(0), EVIDENCE_HASH, URI, RATIONALE);
    }

    function test_openDisputeRejectsZeroEvidenceHash() public {
        vm.prank(alice);
        vm.expectRevert(IMDOracleDisputeRegistry.ZeroEvidenceHash.selector);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, bytes32(0), URI, RATIONALE);
    }

    function test_openDisputeRejectsEmptyURI() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 0));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, "", RATIONALE);
    }

    function test_openDisputeRejectsOverlongURI() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 513));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, _bytesOf(513), RATIONALE);
    }

    function test_openDisputeAcceptsBoundaryURI() public {
        vm.prank(alice);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, _bytesOf(512), RATIONALE);
        vm.prank(alice);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, "x", RATIONALE);
        assertEq(bytes(registry.getDispute(1).evidenceURI).length, 512);
        assertEq(registry.getDispute(2).evidenceURI, "x");
    }

    function test_openDisputeRejectsEmptyRationale() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 0));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, "");
    }

    function test_openDisputeRejectsOverlongRationale() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 281));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, _bytesOf(281));
    }

    function test_openDisputeAcceptsBoundaryRationale() public {
        vm.prank(alice);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, _bytesOf(280));
        vm.prank(alice);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, "!");
        assertEq(bytes(registry.getDispute(1).rationale).length, 280);
        assertEq(registry.getDispute(2).rationale, "!");
    }

    function test_lengthLimitsCountUtf8BytesNotCharacters() public {
        // 94 copies of a 3-byte character = 282 bytes, 94 characters. Bytes are what count.
        bytes memory b = new bytes(282);
        for (uint256 i; i < 94; ++i) {
            b[3 * i] = 0xE2;
            b[3 * i + 1] = 0x82;
            b[3 * i + 2] = 0xAC; // "€"
        }
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 282));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, string(b));
    }

    function test_snapshotHashIsStoredVerbatimNotVerified() public {
        // The registry cannot know what an attestation looks like; any non-zero value is accepted.
        bytes32 arbitrary = bytes32(uint256(0xdeadbeef));
        vm.prank(alice);
        registry.openDispute(REQUEST_ID, 999_999, arbitrary, arbitrary, URI, RATIONALE);
        IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(1);
        assertEq(d.attestationSnapshotHash, arbitrary);
        assertEq(d.evidenceHash, arbitrary);
        assertEq(d.sourceChainId, 999_999);
    }

    function testFuzz_openDisputeAttributesToSender(
        address who,
        bytes16 requestId,
        uint256 sourceChainId,
        bytes32 snapshot,
        bytes32 evidence
    ) public {
        vm.assume(who != address(0) && who.code.length == 0);
        vm.assume(requestId != bytes16(0) && sourceChainId != 0 && snapshot != 0 && evidence != 0);
        vm.prank(who);
        uint256 id = registry.openDispute(requestId, sourceChainId, snapshot, evidence, URI, RATIONALE);
        IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(id);
        assertEq(d.challenger, who);
        assertEq(d.requestId, requestId);
        assertEq(d.sourceChainId, sourceChainId);
        assertEq(d.attestationSnapshotHash, snapshot);
        assertEq(d.evidenceHash, evidence);
    }

    function testFuzz_textLengthBounds(uint16 length) public {
        length = uint16(bound(length, 0, 600));
        string memory text = _bytesOf(length);
        vm.prank(alice);
        if (length == 0 || length > 280) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, uint256(length))
            );
        }
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, text);
    }

    function testFuzz_uriLengthBounds(uint16 length) public {
        length = uint16(bound(length, 0, 1100));
        string memory uri = _bytesOf(length);
        vm.prank(alice);
        if (length == 0 || length > 512) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, uint256(length))
            );
        }
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, uri, RATIONALE);
    }

    // ---------------------------------------------------------------------------------------------
    // respond
    // ---------------------------------------------------------------------------------------------

    function test_respondStoresFieldsAndAttributesToSender() public {
        uint256 id = _open(alice);
        vm.warp(block.timestamp + 100);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ResponseAdded(id, 0, bob, EVIDENCE_HASH, URI, "A response", uint64(block.timestamp));
        uint256 idx = _respond(bob, id);
        assertEq(idx, 0);
        assertEq(registry.responseCount(id), 1);

        IMDOracleDisputeRegistry.Response memory r = registry.getResponse(id, 0);
        assertEq(r.author, bob);
        assertEq(r.evidenceHash, EVIDENCE_HASH);
        assertEq(r.evidenceURI, URI);
        assertEq(r.text, "A response");
        assertEq(r.createdAt, uint64(block.timestamp));
    }

    function test_responsesAreAppendOnlyInOrder() public {
        uint256 id = _open(alice);
        assertEq(_respond(bob, id), 0);
        assertEq(_respond(carol, id), 1);
        assertEq(_respond(alice, id), 2); // the challenger may respond to their own dispute
        assertEq(_respond(bob, id), 3); // the same wallet may respond repeatedly
        assertEq(registry.responseCount(id), 4);
        assertEq(registry.getResponse(id, 0).author, bob);
        assertEq(registry.getResponse(id, 1).author, carol);
        assertEq(registry.getResponse(id, 2).author, alice);
        assertEq(registry.getResponse(id, 3).author, bob);
    }

    function test_responsesAreIsolatedPerDispute() public {
        uint256 a = _open(alice);
        uint256 b = _open(bob);
        _respond(carol, a);
        assertEq(registry.responseCount(a), 1);
        assertEq(registry.responseCount(b), 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.ResponseNotFound.selector, b, 0));
        registry.getResponse(b, 0);
    }

    function test_respondRejectsUnknownDispute() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        registry.respond(1, EVIDENCE_HASH, URI, "text");

        _open(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 0));
        registry.respond(0, EVIDENCE_HASH, URI, "text");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 2));
        registry.respond(2, EVIDENCE_HASH, URI, "text");
    }

    function test_respondRejectsZeroEvidenceHash() public {
        uint256 id = _open(alice);
        vm.prank(bob);
        vm.expectRevert(IMDOracleDisputeRegistry.ZeroEvidenceHash.selector);
        registry.respond(id, bytes32(0), URI, "text");
    }

    function test_respondRejectsBadLengths() public {
        uint256 id = _open(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 0));
        registry.respond(id, EVIDENCE_HASH, "", "text");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 513));
        registry.respond(id, EVIDENCE_HASH, _bytesOf(513), "text");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 0));
        registry.respond(id, EVIDENCE_HASH, URI, "");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 281));
        registry.respond(id, EVIDENCE_HASH, URI, _bytesOf(281));
        // Boundaries are accepted.
        vm.prank(bob);
        registry.respond(id, EVIDENCE_HASH, _bytesOf(512), _bytesOf(280));
        assertEq(registry.responseCount(id), 1);
    }

    function test_respondRejectedOnceWithdrawn() public {
        uint256 id = _open(alice);
        _respond(bob, id);
        vm.prank(alice);
        registry.withdrawDispute(id);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
        registry.respond(id, EVIDENCE_HASH, URI, "late");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
        registry.respond(id, EVIDENCE_HASH, URI, "late from challenger");
        assertEq(registry.responseCount(id), 1);
    }

    function testFuzz_respondAttributesToSender(address who, bytes32 evidence) public {
        vm.assume(who != address(0) && who.code.length == 0 && evidence != 0);
        uint256 id = _open(alice);
        vm.prank(who);
        uint256 idx = registry.respond(id, evidence, URI, "fuzzed");
        IMDOracleDisputeRegistry.Response memory r = registry.getResponse(id, idx);
        assertEq(r.author, who);
        assertEq(r.evidenceHash, evidence);
    }

    // ---------------------------------------------------------------------------------------------
    // withdrawDispute
    // ---------------------------------------------------------------------------------------------

    function test_withdrawByChallengerPreservesEverything() public {
        uint256 id = _open(alice);
        _respond(bob, id);
        _respond(carol, id);
        IMDOracleDisputeRegistry.Dispute memory before = registry.getDispute(id);
        vm.warp(block.timestamp + 3600);

        vm.expectEmit(true, true, true, true, address(registry));
        emit DisputeWithdrawn(id, alice, uint64(block.timestamp));
        vm.prank(alice);
        registry.withdrawDispute(id);

        IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(id);
        assertEq(uint256(d.status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn));
        assertEq(d.withdrawnAt, uint64(block.timestamp));
        // Every other field is untouched.
        assertEq(d.id, before.id);
        assertEq(d.challenger, before.challenger);
        assertEq(d.requestId, before.requestId);
        assertEq(d.sourceChainId, before.sourceChainId);
        assertEq(d.attestationSnapshotHash, before.attestationSnapshotHash);
        assertEq(d.evidenceHash, before.evidenceHash);
        assertEq(d.evidenceURI, before.evidenceURI);
        assertEq(d.rationale, before.rationale);
        assertEq(d.createdAt, before.createdAt);
        // Responses and counts survive.
        assertEq(registry.disputeCount(), 1);
        assertEq(registry.responseCount(id), 2);
        assertEq(registry.getResponse(id, 0).author, bob);
        assertEq(registry.getResponse(id, 1).author, carol);
        assertEq(registry.getResponses(id, 0, 50).length, 2);
    }

    function test_withdrawRejectsNonChallenger() public {
        uint256 id = _open(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, bob));
        registry.withdrawDispute(id);
        // A responder is not a challenger either.
        _respond(carol, id);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, carol));
        registry.withdrawDispute(id);
        // The deployer has no special power.
        vm.expectRevert(
            abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, address(this))
        );
        registry.withdrawDispute(id);
        assertEq(
            uint256(registry.getDispute(id).status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open)
        );
    }

    function test_withdrawRejectsUnknownDispute() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        registry.withdrawDispute(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 0));
        registry.withdrawDispute(0);
    }

    function test_withdrawIsFinalAndNotRepeatable() public {
        uint256 id = _open(alice);
        vm.prank(alice);
        registry.withdrawDispute(id);
        uint64 firstWithdrawnAt = registry.getDispute(id).withdrawnAt;
        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
        registry.withdrawDispute(id);
        assertEq(registry.getDispute(id).withdrawnAt, firstWithdrawnAt);
    }

    function test_withdrawOneDisputeDoesNotAffectOthers() public {
        uint256 a = _open(alice);
        uint256 b = _open(alice);
        vm.prank(alice);
        registry.withdrawDispute(a);
        assertEq(uint256(registry.getDispute(b).status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));
        assertEq(_respond(bob, b), 0);
    }

    function testFuzz_onlyChallengerCanWithdraw(address challenger, address other) public {
        vm.assume(challenger != address(0) && challenger.code.length == 0);
        vm.assume(other != challenger && other != address(0) && other.code.length == 0);
        uint256 id = _open(challenger);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, other));
        registry.withdrawDispute(id);
        vm.prank(challenger);
        registry.withdrawDispute(id);
        assertEq(
            uint256(registry.getDispute(id).status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn)
        );
    }

    // ---------------------------------------------------------------------------------------------
    // Getters and pagination
    // ---------------------------------------------------------------------------------------------

    function test_getDisputeRejectsInvalidIds() public {
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 0));
        registry.getDispute(0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        registry.getDispute(1);
        _open(alice);
        registry.getDispute(1);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 2));
        registry.getDispute(2);
        vm.expectRevert(
            abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, type(uint256).max)
        );
        registry.getDispute(type(uint256).max);
    }

    function test_responseGettersRejectInvalidDispute() public {
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        registry.responseCount(1);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        registry.getResponse(1, 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        registry.getResponses(1, 0, 10);
    }

    function test_getResponseRejectsOutOfRangeIndex() public {
        uint256 id = _open(alice);
        _respond(bob, id);
        registry.getResponse(id, 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.ResponseNotFound.selector, id, 1));
        registry.getResponse(id, 1);
    }

    function test_getDisputesPagesInOrder() public {
        for (uint256 i; i < 7; ++i) {
            _open(i % 2 == 0 ? alice : bob);
        }
        IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(0, 3);
        assertEq(page.length, 3);
        assertEq(page[0].id, 1);
        assertEq(page[2].id, 3);

        page = registry.getDisputes(3, 3);
        assertEq(page.length, 3);
        assertEq(page[0].id, 4);
        assertEq(page[2].id, 6);

        // The last page is short, not padded.
        page = registry.getDisputes(6, 3);
        assertEq(page.length, 1);
        assertEq(page[0].id, 7);
        assertEq(page[0].challenger, alice);

        // A limit larger than the remainder is fine.
        page = registry.getDisputes(0, 50);
        assertEq(page.length, 7);
    }

    function test_getDisputesRejectsBadLimit() public {
        _open(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 0));
        registry.getDisputes(0, 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 51));
        registry.getDisputes(0, 51);
        vm.expectRevert(
            abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, type(uint256).max)
        );
        registry.getDisputes(0, type(uint256).max);
    }

    function test_getDisputesRejectsOffsetAtOrPastEnd() public {
        _open(alice);
        _open(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 2, 2));
        registry.getDisputes(2, 10);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 3, 2));
        registry.getDisputes(3, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, type(uint256).max, 2)
        );
        registry.getDisputes(type(uint256).max, 10);
    }

    function test_getDisputesLimitBoundaryFifty() public {
        for (uint256 i; i < 55; ++i) {
            _open(alice);
        }
        assertEq(registry.getDisputes(0, 50).length, 50);
        assertEq(registry.getDisputes(50, 50).length, 5);
        assertEq(registry.getDisputes(54, 1).length, 1);
    }

    function test_getResponsesPagesInOrder() public {
        uint256 id = _open(alice);
        for (uint256 i; i < 5; ++i) {
            vm.prank(bob);
            registry.respond(id, bytes32(uint256(i + 1)), URI, "r");
        }
        IMDOracleDisputeRegistry.Response[] memory page = registry.getResponses(id, 0, 2);
        assertEq(page.length, 2);
        assertEq(page[0].evidenceHash, bytes32(uint256(1)));
        assertEq(page[1].evidenceHash, bytes32(uint256(2)));
        page = registry.getResponses(id, 4, 2);
        assertEq(page.length, 1);
        assertEq(page[0].evidenceHash, bytes32(uint256(5)));
        page = registry.getResponses(id, 0, 50);
        assertEq(page.length, 5);
    }

    function test_getResponsesEmptyAndBounds() public {
        uint256 id = _open(alice);
        assertEq(registry.getResponses(id, 0, 10).length, 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 1, 0));
        registry.getResponses(id, 1, 10);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 0));
        registry.getResponses(id, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 51));
        registry.getResponses(id, 0, 51);
        _respond(bob, id);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 1, 1));
        registry.getResponses(id, 1, 10);
    }

    function testFuzz_disputePagesCoverExactlyOnce(uint8 count, uint8 limit) public {
        count = uint8(bound(count, 0, 60));
        limit = uint8(bound(limit, 1, 50));
        for (uint256 i; i < count; ++i) {
            _open(alice);
        }
        uint256 seen;
        uint256 offset;
        while (offset < count) {
            IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(offset, limit);
            assertGt(page.length, 0);
            assertLe(page.length, limit);
            for (uint256 i; i < page.length; ++i) {
                assertEq(page[i].id, offset + i + 1);
            }
            seen += page.length;
            offset += page.length;
        }
        assertEq(seen, count);
        if (count == 0) {
            assertEq(registry.getDisputes(0, limit).length, 0);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, count, count)
            );
            registry.getDisputes(count, limit);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // No ETH, no admin, no token, no external calls
    // ---------------------------------------------------------------------------------------------

    function test_rejectsPlainEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(registry).call{value: 1 wei}("");
        assertFalse(ok, "registry accepted plain ETH");
        assertEq(address(registry).balance, 0);
    }

    function test_rejectsEtherWithCalldata() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(registry).call{value: 1 wei}(
            abi.encodeCall(
                IMDOracleDisputeRegistry.openDispute,
                (REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE)
            )
        );
        assertFalse(ok, "openDispute accepted ETH");
        assertEq(registry.disputeCount(), 0);
        assertEq(address(registry).balance, 0);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(registry).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "fallback exists");
    }

    function test_noAdminSurfaceRespondsToCommonSelectors() public {
        string[12] memory signatures = [
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)",
            "resolveDispute(uint256,bool)",
            "deleteDispute(uint256)",
            "setAdmin(address)",
            "sweep(address)"
        ];
        uint256 id = _open(alice);
        for (uint256 i; i < signatures.length; ++i) {
            (bool ok,) = address(registry).call(abi.encodeWithSignature(signatures[i], id, true));
            assertFalse(ok, signatures[i]);
        }
        assertEq(
            uint256(registry.getDispute(id).status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open)
        );
    }

    function test_deployerAndFactoryHoldNoPrivilege() public {
        // Deploy from a pretend factory address and confirm the factory cannot withdraw anyone's dispute.
        address factory = makeAddr("factory");
        vm.prank(factory);
        IMDOracleDisputeRegistry fresh = new IMDOracleDisputeRegistry();
        vm.prank(alice);
        uint256 id = fresh.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE);
        vm.prank(factory);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, factory));
        fresh.withdrawDispute(id);
    }

    function test_runtimeHasNoCallDelegatecallCallcodeSelfdestructOrCreate() public view {
        bytes memory code = address(registry).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            assertTrue(op != 0xF0, "CREATE");
            assertTrue(op != 0xF1, "CALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF5, "CREATE2");
            assertTrue(op != 0xFA, "STATICCALL");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    function test_contractCallersAreRecordedAsTheContract() public {
        // msg.sender attribution is literal: a contract wallet is recorded as itself, not its EOA.
        Caller c = new Caller(registry);
        uint256 id = c.open();
        assertEq(registry.getDispute(id).challenger, address(c));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, alice));
        registry.withdrawDispute(id);
        c.withdraw(id);
        assertEq(
            uint256(registry.getDispute(id).status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn)
        );
    }
}

/// @dev A contract wallet stand-in to show attribution is `msg.sender`, never `tx.origin`.
contract Caller {
    IMDOracleDisputeRegistry private immutable registry;

    constructor(IMDOracleDisputeRegistry r) {
        registry = r;
    }

    function open() external returns (uint256) {
        return registry.openDispute(
            bytes16(uint128(1)), 1, bytes32(uint256(1)), bytes32(uint256(2)), "ipfs://x", "from a contract"
        );
    }

    function withdraw(uint256 id) external {
        registry.withdrawDispute(id);
    }
}

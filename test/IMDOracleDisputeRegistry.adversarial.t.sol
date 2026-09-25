// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDOracleDisputeRegistry} from "../src/IMDOracleDisputeRegistry.sol";

/// @title Adversarial and edge-case tests for IMDOracleDisputeRegistry
/// @notice Complements `IMDOracleDisputeRegistry.t.sol`. The focus here is what a hostile or careless
/// caller can do to somebody else's record: cross-wallet withdrawal attempts, repeat withdrawals, writes to
/// withdrawn or nonexistent disputes, multi-byte UTF-8 at the byte limits, arbitrary pagination arguments
/// and ETH sent to every selector. Every test deploys its own registry from an explicit, pranked deployer
/// and derives every wallet locally, so nothing depends on the default sender, environment variables or
/// test order.
contract IMDOracleDisputeRegistryAdversarialTest is Test {
    IMDOracleDisputeRegistry internal registry;

    address internal deployer;
    address internal alice;
    address internal bob;
    address internal carol;
    address internal dave;
    address internal erin;
    address[5] internal wallets;

    bytes16 internal constant REQUEST_ID = bytes16(0x0192d5f8a3b14c6e9f2a7b8c1d3e4f50);
    uint256 internal constant SOURCE_CHAIN = 8453;
    bytes32 internal constant SNAPSHOT_HASH = keccak256('{"attestation":"snapshot"}');
    bytes32 internal constant EVIDENCE_HASH = keccak256("evidence");
    string internal constant URI = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
    string internal constant RATIONALE = "The attested value disagrees with the on-chain event log.";

    /// @dev Multi-byte UTF-8 units: 2-byte "e acute", 3-byte euro sign, 4-byte grinning face.
    bytes internal constant TWO_BYTE = hex"c3a9";
    bytes internal constant THREE_BYTE = hex"e282ac";
    bytes internal constant FOUR_BYTE = hex"f09f9880";

    function setUp() public {
        vm.warp(1_700_000_000);
        deployer = makeAddr("deployer");
        vm.prank(deployer);
        registry = new IMDOracleDisputeRegistry();

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");
        erin = makeAddr("erin");
        wallets = [alice, bob, carol, dave, erin];
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    function _open(address who) internal returns (uint256) {
        vm.prank(who);
        return registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE);
    }

    function _openWith(address who, bytes16 requestId, uint256 chainId, string memory rationale)
        internal
        returns (uint256)
    {
        vm.prank(who);
        return registry.openDispute(requestId, chainId, SNAPSHOT_HASH, EVIDENCE_HASH, URI, rationale);
    }

    function _respond(address who, uint256 id, string memory text) internal returns (uint256) {
        vm.prank(who);
        return registry.respond(id, keccak256(bytes(text)), URI, text);
    }

    function _disputeDigest(uint256 id) internal view returns (bytes32) {
        return keccak256(abi.encode(registry.getDispute(id)));
    }

    /// @dev Digest of every dispute field that must never change after creation (all but status/withdrawnAt).
    function _immutableDigest(IMDOracleDisputeRegistry.Dispute memory d) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                d.id,
                d.challenger,
                d.requestId,
                d.sourceChainId,
                d.attestationSnapshotHash,
                d.evidenceHash,
                d.evidenceURI,
                d.rationale,
                d.createdAt
            )
        );
    }

    function _responseDigest(uint256 id, uint256 index) internal view returns (bytes32) {
        return keccak256(abi.encode(registry.getResponse(id, index)));
    }

    function _allResponsesDigest(uint256 id) internal view returns (bytes32) {
        uint256 n = registry.responseCount(id);
        bytes32 acc;
        for (uint256 i; i < n; ++i) {
            acc = keccak256(abi.encode(acc, _responseDigest(id, i)));
        }
        return keccak256(abi.encode(n, acc));
    }

    function _repeat(bytes memory unit, uint256 count) internal pure returns (string memory) {
        bytes memory out = new bytes(unit.length * count);
        for (uint256 i; i < count; ++i) {
            for (uint256 j; j < unit.length; ++j) {
                out[i * unit.length + j] = unit[j];
            }
        }
        return string(out);
    }

    function _ascii(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i; i < n; ++i) {
            b[i] = "z";
        }
        return string(b);
    }

    /// @dev Fuzzed addresses that can act as an EOA in this harness.
    function _usable(address a) internal view returns (bool) {
        return a != address(0) && a.code.length == 0 && a != address(vm) && a != address(registry)
            && a != 0x000000000000000000636F6e736F6c652e6c6f67 && uint160(a) > 0xff;
    }

    function _status(uint256 id) internal view returns (IMDOracleDisputeRegistry.DisputeStatus) {
        return registry.getDispute(id).status;
    }

    // ---------------------------------------------------------------------------------------------
    // Deployment with an explicit local deployer
    // ---------------------------------------------------------------------------------------------

    function test_deploymentFromExplicitDeployerGrantsNoPrivilege() public {
        assertGt(address(registry).code.length, 0);
        assertEq(registry.disputeCount(), 0);

        uint256 id = _open(alice);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, deployer));
        registry.withdrawDispute(id);

        // The deployer is an ordinary participant: it may open and withdraw its own dispute.
        uint256 own = _open(deployer);
        vm.prank(deployer);
        registry.withdrawDispute(own);
        assertEq(uint256(_status(own)), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn));
        assertEq(uint256(_status(id)), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));
    }

    function test_twoRegistriesDoNotShareState() public {
        address otherDeployer = makeAddr("other-deployer");
        vm.prank(otherDeployer);
        IMDOracleDisputeRegistry second = new IMDOracleDisputeRegistry();
        assertTrue(address(second) != address(registry));

        _open(alice);
        _open(bob);
        assertEq(registry.disputeCount(), 2);
        assertEq(second.disputeCount(), 0);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 1));
        second.getDispute(1);

        vm.prank(carol);
        uint256 id =
            second.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE);
        assertEq(id, 1);
        assertEq(second.getDispute(1).challenger, carol);
        assertEq(registry.getDispute(1).challenger, alice);
    }

    // ---------------------------------------------------------------------------------------------
    // Multiple independent wallets and cross-wallet withdrawal
    // ---------------------------------------------------------------------------------------------

    function test_fiveWalletsOwnOnlyTheirOwnDisputes() public {
        uint256[5] memory ids;
        for (uint256 i; i < 5; ++i) {
            ids[i] = _open(wallets[i]);
            assertEq(ids[i], i + 1);
            assertEq(registry.getDispute(ids[i]).challenger, wallets[i]);
        }

        // Every wallet is refused on every dispute it did not open.
        for (uint256 i; i < 5; ++i) {
            for (uint256 j; j < 5; ++j) {
                if (i == j) continue;
                vm.prank(wallets[j]);
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IMDOracleDisputeRegistry.NotChallenger.selector, ids[i], wallets[j]
                    )
                );
                registry.withdrawDispute(ids[i]);
            }
        }
        for (uint256 i; i < 5; ++i) {
            assertEq(uint256(_status(ids[i])), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));
        }

        // Each wallet withdraws its own; the others remain open until their own challenger acts.
        for (uint256 i; i < 5; ++i) {
            vm.prank(wallets[i]);
            registry.withdrawDispute(ids[i]);
            for (uint256 k; k < 5; ++k) {
                IMDOracleDisputeRegistry.DisputeStatus expected = k <= i
                    ? IMDOracleDisputeRegistry.DisputeStatus.Withdrawn
                    : IMDOracleDisputeRegistry.DisputeStatus.Open;
                assertEq(uint256(_status(ids[k])), uint256(expected));
            }
        }

        // After withdrawal the challenger check still comes first for strangers, then the status check.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, ids[0], bob));
        registry.withdrawDispute(ids[0]);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, ids[0]));
        registry.withdrawDispute(ids[0]);
        assertEq(registry.disputeCount(), 5);
    }

    function test_identicalContentDoesNotTransferOwnership() public {
        // Two disputes with byte-identical content from different wallets are two records with two owners.
        uint256 a = _open(alice);
        uint256 b = _open(bob);
        assertEq(registry.getDispute(a).requestId, registry.getDispute(b).requestId);
        assertEq(registry.getDispute(a).rationale, registry.getDispute(b).rationale);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, b, alice));
        registry.withdrawDispute(b);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, a, bob));
        registry.withdrawDispute(a);
    }

    function testFuzz_anotherAccountCannotAlterPriorAuthorRecord(
        address author,
        address other,
        bytes16 requestId,
        uint256 chainId,
        bytes32 otherEvidence
    ) public {
        vm.assume(_usable(author) && _usable(other) && author != other);
        vm.assume(requestId != bytes16(0) && chainId != 0 && otherEvidence != bytes32(0));

        // The author writes a dispute and the first response to it.
        uint256 id = _openWith(author, requestId, chainId, "original rationale");
        uint256 idx = _respond(author, id, "original response");
        assertEq(idx, 0);
        bytes32 disputeBefore = _disputeDigest(id);
        bytes32 immutableBefore = _immutableDigest(registry.getDispute(id));
        bytes32 responseBefore = _responseDigest(id, 0);

        vm.warp(vm.getBlockTimestamp() + 42);

        // The other account tries everything the ABI offers against the author's record.
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, other));
        registry.withdrawDispute(id);

        vm.prank(other);
        uint256 otherIdx = registry.respond(id, otherEvidence, "ipfs://other", "rewritten?");
        assertEq(otherIdx, 1, "a response appends; it never replaces");

        vm.prank(other);
        uint256 otherId = registry.openDispute(requestId, chainId, SNAPSHOT_HASH, otherEvidence, URI, "mine");
        assertEq(otherId, id + 1);

        // The author's dispute and the author's response are byte-for-byte unchanged.
        assertEq(_disputeDigest(id), disputeBefore, "dispute record altered by another account");
        assertEq(_responseDigest(id, 0), responseBefore, "response record altered by another account");
        assertEq(registry.getDispute(id).challenger, author);
        assertEq(registry.getResponse(id, 0).author, author);
        assertEq(registry.getResponse(id, 1).author, other);
        assertEq(registry.getResponse(id, 1).evidenceHash, otherEvidence);
        assertEq(registry.responseCount(id), 2);

        // Only the author can close it, and doing so still leaves both responses intact.
        vm.prank(author);
        registry.withdrawDispute(id);
        assertEq(_responseDigest(id, 0), responseBefore);
        assertEq(registry.getResponse(id, 1).author, other);
        assertEq(
            _immutableDigest(registry.getDispute(id)),
            immutableBefore,
            "withdrawal altered an immutable field"
        );
        assertEq(registry.getDispute(id).withdrawnAt, uint64(block.timestamp));

        // The other account's own dispute is still theirs alone.
        vm.prank(author);
        vm.expectRevert(
            abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, otherId, author)
        );
        registry.withdrawDispute(otherId);
    }

    // ---------------------------------------------------------------------------------------------
    // ID / count consistency
    // ---------------------------------------------------------------------------------------------

    function testFuzz_idsAndCountsStayConsistent(uint8 rawCount, uint256 seed) public {
        uint256 count = bound(rawCount, 0, 40);
        address[] memory expected = new address[](count);
        for (uint256 i; i < count; ++i) {
            address who = wallets[uint256(keccak256(abi.encode(seed, i))) % 5];
            expected[i] = who;
            uint256 before = registry.disputeCount();
            uint256 id = _open(who);
            assertEq(id, before + 1, "id is count + 1");
            assertEq(registry.disputeCount(), id, "count equals last id");
        }
        for (uint256 i; i < count; ++i) {
            IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(i + 1);
            assertEq(d.id, i + 1);
            assertEq(d.challenger, expected[i]);
        }
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, count + 1));
        registry.getDispute(count + 1);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 0));
        registry.getDispute(0);
    }

    function testFuzz_responseIndicesStayConsistent(uint8 rawCount, uint256 seed) public {
        uint256 count = bound(rawCount, 0, 60);
        uint256 id = _open(alice);
        address[] memory expected = new address[](count);
        for (uint256 i; i < count; ++i) {
            address who = wallets[uint256(keccak256(abi.encode(seed, i))) % 5];
            expected[i] = who;
            vm.prank(who);
            uint256 idx = registry.respond(id, bytes32(i + 1), URI, "r");
            assertEq(idx, i, "index is previous count");
            assertEq(registry.responseCount(id), i + 1);
        }
        for (uint256 i; i < count; ++i) {
            IMDOracleDisputeRegistry.Response memory r = registry.getResponse(id, i);
            assertEq(r.author, expected[i]);
            assertEq(r.evidenceHash, bytes32(i + 1));
        }
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.ResponseNotFound.selector, id, count));
        registry.getResponse(id, count);
        vm.expectRevert(
            abi.encodeWithSelector(IMDOracleDisputeRegistry.ResponseNotFound.selector, id, type(uint256).max)
        );
        registry.getResponse(id, type(uint256).max);
    }

    // ---------------------------------------------------------------------------------------------
    // Nonexistent and withdrawn disputes
    // ---------------------------------------------------------------------------------------------

    function testFuzz_writesToNonexistentDisputeRevert(uint8 rawCount, uint256 id, address who) public {
        vm.assume(_usable(who));
        uint256 count = bound(rawCount, 0, 8);
        for (uint256 i; i < count; ++i) {
            _open(wallets[i % 5]);
        }
        vm.assume(id == 0 || id > count);

        bytes memory err = abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, id);
        vm.prank(who);
        vm.expectRevert(err);
        registry.respond(id, EVIDENCE_HASH, URI, "text");
        vm.prank(who);
        vm.expectRevert(err);
        registry.withdrawDispute(id);
        vm.expectRevert(err);
        registry.getDispute(id);
        vm.expectRevert(err);
        registry.responseCount(id);
        vm.expectRevert(err);
        registry.getResponse(id, 0);
        vm.expectRevert(err);
        registry.getResponses(id, 0, 1);
        assertEq(registry.disputeCount(), count, "a rejected write must not create anything");
    }

    function test_respondToJustPastTheEndIsRejectedThenAcceptedOnceItExists() public {
        _open(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotFound.selector, 2));
        registry.respond(2, EVIDENCE_HASH, URI, "early");
        _open(carol);
        assertEq(_respond(bob, 2, "on time"), 0);
        assertEq(registry.getResponse(2, 0).author, bob);
    }

    function testFuzz_noWalletCanRespondAfterWithdrawal(address challenger, uint256 seed) public {
        vm.assume(_usable(challenger));
        uint256 id = _open(challenger);
        _respond(bob, id, "before");
        vm.prank(challenger);
        registry.withdrawDispute(id);
        bytes32 responsesBefore = _allResponsesDigest(id);

        for (uint256 i; i < 6; ++i) {
            address who = i < 5 ? wallets[uint256(keccak256(abi.encode(seed, i))) % 5] : challenger;
            vm.prank(who);
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
            registry.respond(id, bytes32(uint256(keccak256(abi.encode(seed, i, "e")))), URI, "late");
        }
        assertEq(registry.responseCount(id), 1);
        assertEq(_allResponsesDigest(id), responsesBefore);
    }

    function test_withdrawalOfOneDisputeDoesNotBlockResponsesElsewhere() public {
        uint256 a = _open(alice);
        uint256 b = _open(bob);
        uint256 c = _open(carol);
        vm.prank(bob);
        registry.withdrawDispute(b);

        assertEq(_respond(dave, a, "to a"), 0);
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, b));
        registry.respond(b, EVIDENCE_HASH, URI, "to b");
        assertEq(_respond(dave, c, "to c"), 0);
        assertEq(registry.responseCount(a), 1);
        assertEq(registry.responseCount(b), 0);
        assertEq(registry.responseCount(c), 1);
    }

    function testFuzz_repeatWithdrawalIsRejectedAndTimestampFrozen(address challenger, uint8 rawAttempts)
        public
    {
        vm.assume(_usable(challenger));
        uint256 attempts = bound(rawAttempts, 1, 12);
        uint256 id = _open(challenger);
        vm.warp(vm.getBlockTimestamp() + 100);
        vm.prank(challenger);
        registry.withdrawDispute(id);
        uint64 withdrawnAt = registry.getDispute(id).withdrawnAt;
        assertEq(withdrawnAt, uint64(block.timestamp));
        bytes32 digest = _disputeDigest(id);

        for (uint256 i; i < attempts; ++i) {
            vm.warp(vm.getBlockTimestamp() + 7);
            vm.prank(challenger);
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
            registry.withdrawDispute(id);
        }
        assertEq(registry.getDispute(id).withdrawnAt, withdrawnAt);
        assertEq(_disputeDigest(id), digest);
    }

    // ---------------------------------------------------------------------------------------------
    // Preservation of records across state transitions
    // ---------------------------------------------------------------------------------------------

    function test_withdrawalChangesOnlyStatusAndWithdrawnAtAndKeepsPages() public {
        uint256 id = _open(alice);
        _open(bob);
        _respond(bob, id, "one");
        _respond(carol, id, _repeat(FOUR_BYTE, 70));
        _respond(alice, id, "three");

        IMDOracleDisputeRegistry.Dispute memory before = registry.getDispute(id);
        bytes32 responsesBefore = _allResponsesDigest(id);
        bytes32 pageBefore = keccak256(abi.encode(registry.getResponses(id, 0, 50)));
        bytes32 otherBefore = _disputeDigest(2);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(alice);
        registry.withdrawDispute(id);

        IMDOracleDisputeRegistry.Dispute memory after_ = registry.getDispute(id);
        assertEq(_immutableDigest(after_), _immutableDigest(before));
        assertEq(uint256(after_.status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn));
        assertEq(after_.withdrawnAt, uint64(block.timestamp));
        assertEq(before.withdrawnAt, 0);

        assertEq(_allResponsesDigest(id), responsesBefore);
        assertEq(keccak256(abi.encode(registry.getResponses(id, 0, 50))), pageBefore);
        assertEq(_disputeDigest(2), otherBefore);

        // The list view reflects the new status of the withdrawn one and nothing else.
        IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(0, 50);
        assertEq(page.length, 2);
        assertEq(keccak256(abi.encode(page[0])), keccak256(abi.encode(after_)));
        assertEq(keccak256(abi.encode(page[1])), otherBefore);
    }

    function testFuzz_randomWithdrawalAttemptsNeverTouchOtherRecords(uint256 seed) public {
        uint256 n = 4;
        uint256[] memory ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = _openWith(wallets[i], bytes16(uint128(i + 1)), i + 1, string(abi.encodePacked("r", i)));
            uint256 responses = 1 + (uint256(keccak256(abi.encode(seed, "n", i))) % 3);
            for (uint256 k; k < responses; ++k) {
                _respond(wallets[uint256(keccak256(abi.encode(seed, i, k))) % 5], ids[i], "resp");
            }
        }
        bytes32[] memory immutableDigests = new bytes32[](n);
        bytes32[] memory responseDigests = new bytes32[](n);
        bool[] memory withdrawn = new bool[](n);
        uint64[] memory withdrawnAt = new uint64[](n);
        for (uint256 i; i < n; ++i) {
            immutableDigests[i] = _immutableDigest(registry.getDispute(ids[i]));
            responseDigests[i] = _allResponsesDigest(ids[i]);
        }

        for (uint256 step; step < 10; ++step) {
            uint256 target = uint256(keccak256(abi.encode(seed, "t", step))) % n;
            address who = wallets[uint256(keccak256(abi.encode(seed, "w", step))) % 5];
            vm.warp(vm.getBlockTimestamp() + 1);
            vm.prank(who);
            if (who != wallets[target]) {
                vm.expectRevert(
                    abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, ids[target], who)
                );
                registry.withdrawDispute(ids[target]);
            } else if (withdrawn[target]) {
                vm.expectRevert(
                    abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, ids[target])
                );
                registry.withdrawDispute(ids[target]);
            } else {
                registry.withdrawDispute(ids[target]);
                withdrawn[target] = true;
                withdrawnAt[target] = uint64(block.timestamp);
            }

            for (uint256 i; i < n; ++i) {
                IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(ids[i]);
                assertEq(_immutableDigest(d), immutableDigests[i], "immutable field changed");
                assertEq(_allResponsesDigest(ids[i]), responseDigests[i], "response history changed");
                assertEq(d.withdrawnAt, withdrawnAt[i]);
                assertEq(
                    uint256(d.status),
                    uint256(
                        withdrawn[i]
                            ? IMDOracleDisputeRegistry.DisputeStatus.Withdrawn
                            : IMDOracleDisputeRegistry.DisputeStatus.Open
                    )
                );
            }
        }
        assertEq(registry.disputeCount(), n);
    }

    // ---------------------------------------------------------------------------------------------
    // Zero fields, empty and oversized strings, validation order
    // ---------------------------------------------------------------------------------------------

    function testFuzz_anyZeroFieldIsRejectedInDeclaredOrder(bool zReq, bool zChain, bool zSnap, bool zEv)
        public
    {
        vm.assume(zReq || zChain || zSnap || zEv);
        bytes memory err;
        if (zReq) {
            err = abi.encodeWithSelector(IMDOracleDisputeRegistry.ZeroRequestId.selector);
        } else if (zChain) {
            err = abi.encodeWithSelector(IMDOracleDisputeRegistry.ZeroSourceChainId.selector);
        } else if (zSnap) {
            err = abi.encodeWithSelector(IMDOracleDisputeRegistry.ZeroAttestationSnapshotHash.selector);
        } else {
            err = abi.encodeWithSelector(IMDOracleDisputeRegistry.ZeroEvidenceHash.selector);
        }

        vm.prank(alice);
        vm.expectRevert(err);
        registry.openDispute(
            zReq ? bytes16(0) : REQUEST_ID,
            zChain ? 0 : SOURCE_CHAIN,
            zSnap ? bytes32(0) : SNAPSHOT_HASH,
            zEv ? bytes32(0) : EVIDENCE_HASH,
            URI,
            RATIONALE
        );
        assertEq(registry.disputeCount(), 0);
    }

    function test_allZeroOpenReportsFirstFieldAndStoresNothing() public {
        vm.prank(alice);
        vm.expectRevert(IMDOracleDisputeRegistry.ZeroRequestId.selector);
        registry.openDispute(bytes16(0), 0, bytes32(0), bytes32(0), "", "");
        assertEq(registry.disputeCount(), 0);
    }

    function test_bothStringsEmptyReportsUriFirst() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 0));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, "", "");

        uint256 id = _open(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 0));
        registry.respond(id, EVIDENCE_HASH, "", "");
        // Oversized URI with empty text: URI error wins; valid URI with oversized text: text error.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 600));
        registry.respond(id, EVIDENCE_HASH, _ascii(600), "");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 1000));
        registry.respond(id, EVIDENCE_HASH, URI, _ascii(1000));
        assertEq(registry.responseCount(id), 0);
    }

    function test_respondOnWithdrawnDisputeFailsBeforeFieldValidation() public {
        // A withdrawn dispute rejects even a fully invalid response with DisputeNotOpen, not a field error.
        uint256 id = _open(alice);
        vm.prank(alice);
        registry.withdrawDispute(id);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
        registry.respond(id, bytes32(0), "", "");
    }

    function testFuzz_respondLengthBounds(uint16 rawUri, uint16 rawText) public {
        uint256 uriLen = bound(rawUri, 0, 700);
        uint256 textLen = bound(rawText, 0, 400);
        uint256 id = _open(alice);
        vm.prank(bob);
        if (uriLen == 0 || uriLen > 512) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, uriLen)
            );
        } else if (textLen == 0 || textLen > 280) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, textLen)
            );
        }
        registry.respond(id, EVIDENCE_HASH, _ascii(uriLen), _ascii(textLen));
        bool ok = uriLen >= 1 && uriLen <= 512 && textLen >= 1 && textLen <= 280;
        assertEq(registry.responseCount(id), ok ? 1 : 0);
        if (ok) {
            assertEq(bytes(registry.getResponse(id, 0).evidenceURI).length, uriLen);
            assertEq(bytes(registry.getResponse(id, 0).text).length, textLen);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // UTF-8 byte boundaries
    // ---------------------------------------------------------------------------------------------

    function test_rationaleMultiByteExactlyAtLimitIsAccepted() public {
        string memory twoByte = _repeat(TWO_BYTE, 140); // 280 bytes, 140 characters
        string memory fourByte = _repeat(FOUR_BYTE, 70); // 280 bytes, 70 characters
        string memory threeByte = _repeat(THREE_BYTE, 93); // 279 bytes, 93 characters
        assertEq(bytes(twoByte).length, 280);
        assertEq(bytes(fourByte).length, 280);
        assertEq(bytes(threeByte).length, 279);

        uint256 a = _openWith(alice, REQUEST_ID, SOURCE_CHAIN, twoByte);
        uint256 b = _openWith(bob, REQUEST_ID, SOURCE_CHAIN, fourByte);
        uint256 c = _openWith(carol, REQUEST_ID, SOURCE_CHAIN, threeByte);
        assertEq(keccak256(bytes(registry.getDispute(a).rationale)), keccak256(bytes(twoByte)));
        assertEq(keccak256(bytes(registry.getDispute(b).rationale)), keccak256(bytes(fourByte)));
        assertEq(keccak256(bytes(registry.getDispute(c).rationale)), keccak256(bytes(threeByte)));
    }

    function test_rationaleMultiByteOneCharacterOverIsRejectedByBytes() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 282));
        registry.openDispute(
            REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, _repeat(TWO_BYTE, 141)
        );
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 284));
        registry.openDispute(
            REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, _repeat(FOUR_BYTE, 71)
        );
        // 280 ASCII characters fit; 280 two-byte characters (560 bytes) do not.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 560));
        registry.openDispute(
            REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, _repeat(TWO_BYTE, 280)
        );
        assertEq(registry.disputeCount(), 0);
    }

    function test_responseTextMultiByteBoundaries() public {
        uint256 id = _open(alice);
        vm.prank(bob);
        registry.respond(id, EVIDENCE_HASH, URI, _repeat(THREE_BYTE, 93)); // 279 bytes
        vm.prank(bob);
        registry.respond(id, EVIDENCE_HASH, URI, _repeat(FOUR_BYTE, 70)); // 280 bytes
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 282));
        registry.respond(id, EVIDENCE_HASH, URI, _repeat(THREE_BYTE, 94));
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidTextLength.selector, 284));
        registry.respond(id, EVIDENCE_HASH, URI, _repeat(FOUR_BYTE, 71));
        assertEq(registry.responseCount(id), 2);
        assertEq(bytes(registry.getResponse(id, 0).text).length, 279);
        assertEq(bytes(registry.getResponse(id, 1).text).length, 280);
    }

    function test_uriMultiByteBoundaries() public {
        string memory atLimit = _repeat(FOUR_BYTE, 128); // 512 bytes
        string memory overLimit = _repeat(FOUR_BYTE, 129); // 516 bytes
        string memory twoByteAtLimit = _repeat(TWO_BYTE, 256); // 512 bytes
        vm.prank(alice);
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, atLimit, RATIONALE);
        vm.prank(alice);
        registry.openDispute(
            REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, twoByteAtLimit, RATIONALE
        );
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 516));
        registry.openDispute(REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, overLimit, RATIONALE);

        uint256 id = 1;
        vm.prank(bob);
        registry.respond(id, EVIDENCE_HASH, atLimit, "t");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidURILength.selector, 516));
        registry.respond(id, EVIDENCE_HASH, overLimit, "t");

        assertEq(keccak256(bytes(registry.getDispute(1).evidenceURI)), keccak256(bytes(atLimit)));
        assertEq(keccak256(bytes(registry.getDispute(2).evidenceURI)), keccak256(bytes(twoByteAtLimit)));
        assertEq(keccak256(bytes(registry.getResponse(id, 0).evidenceURI)), keccak256(bytes(atLimit)));
    }

    function test_splitCodepointAndNulBytesAreStoredVerbatim() public {
        // The registry counts bytes and does not validate UTF-8: a lead byte with no continuation, and a
        // NUL byte, are accepted and returned exactly as sent. This is documented; consumers must treat
        // the strings as untrusted bytes.
        bytes memory truncated = bytes.concat(bytes(_ascii(279)), hex"c3");
        assertEq(truncated.length, 280);
        uint256 a = _openWith(alice, REQUEST_ID, SOURCE_CHAIN, string(truncated));
        assertEq(keccak256(bytes(registry.getDispute(a).rationale)), keccak256(truncated));

        uint256 b = _openWith(bob, REQUEST_ID, SOURCE_CHAIN, string(hex"00"));
        assertEq(bytes(registry.getDispute(b).rationale).length, 1);
        assertEq(bytes(registry.getDispute(b).rationale)[0], bytes1(0));

        bytes memory invalidUtf8 = new bytes(1);
        invalidUtf8[0] = 0xff;
        bytes memory twoNuls = new bytes(2);
        vm.prank(carol);
        registry.respond(a, EVIDENCE_HASH, string(invalidUtf8), string(twoNuls));
        assertEq(keccak256(bytes(registry.getResponse(a, 0).evidenceURI)), keccak256(invalidUtf8));
        assertEq(keccak256(bytes(registry.getResponse(a, 0).text)), keccak256(twoNuls));
    }

    function testFuzz_arbitraryBytesRoundTripVerbatim(bytes memory rationale, bytes memory uri) public {
        vm.assume(rationale.length >= 1 && rationale.length <= 280);
        vm.assume(uri.length >= 1 && uri.length <= 512);
        vm.prank(alice);
        uint256 id = registry.openDispute(
            REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, string(uri), string(rationale)
        );
        IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(id);
        assertEq(keccak256(bytes(d.rationale)), keccak256(rationale));
        assertEq(keccak256(bytes(d.evidenceURI)), keccak256(uri));
        vm.prank(bob);
        uint256 idx = registry.respond(id, EVIDENCE_HASH, string(uri), string(rationale));
        IMDOracleDisputeRegistry.Response memory r = registry.getResponse(id, idx);
        assertEq(keccak256(bytes(r.text)), keccak256(rationale));
        assertEq(keccak256(bytes(r.evidenceURI)), keccak256(uri));
    }

    // ---------------------------------------------------------------------------------------------
    // Pagination edges
    // ---------------------------------------------------------------------------------------------

    function test_disputePageEdges() public {
        for (uint256 i; i < 5; ++i) {
            _open(wallets[i]);
        }
        // Last element alone, with the largest limit.
        IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(4, 50);
        assertEq(page.length, 1);
        assertEq(page[0].id, 5);
        assertEq(page[0].challenger, erin);
        // Smallest limit, first element.
        page = registry.getDisputes(0, 1);
        assertEq(page.length, 1);
        assertEq(page[0].id, 1);
        // Exact fit: limit equal to the remainder.
        page = registry.getDisputes(2, 3);
        assertEq(page.length, 3);
        assertEq(page[0].id, 3);
        assertEq(page[2].id, 5);
        // One past the last valid offset.
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 5, 5));
        registry.getDisputes(5, 1);
        // Limit exactly at both bounds.
        assertEq(registry.getDisputes(0, 50).length, 5);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 51));
        registry.getDisputes(0, 51);
        // Limit is validated before offset.
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 0));
        registry.getDisputes(99, 0);
    }

    function test_responsePageEdges() public {
        uint256 id = _open(alice);
        for (uint256 i; i < 5; ++i) {
            _respond(wallets[i], id, "r");
        }
        IMDOracleDisputeRegistry.Response[] memory page = registry.getResponses(id, 4, 50);
        assertEq(page.length, 1);
        assertEq(page[0].author, erin);
        page = registry.getResponses(id, 0, 1);
        assertEq(page.length, 1);
        assertEq(page[0].author, alice);
        page = registry.getResponses(id, 2, 3);
        assertEq(page.length, 3);
        assertEq(page[0].author, carol);
        assertEq(page[2].author, erin);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, 5, 5));
        registry.getResponses(id, 5, 1);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, 0));
        registry.getResponses(id, 99, 0);
        // Limit-1 walk visits each response exactly once in order.
        for (uint256 i; i < 5; ++i) {
            page = registry.getResponses(id, i, 1);
            assertEq(page.length, 1);
            assertEq(page[0].author, wallets[i]);
        }
    }

    function testFuzz_getDisputesForArbitraryOffsetAndLimit(
        uint8 rawCount,
        uint256 rawOffset,
        uint256 rawLimit
    ) public {
        uint256 count = bound(rawCount, 0, 60);
        for (uint256 i; i < count; ++i) {
            _open(wallets[i % 5]);
        }
        // Concentrate around the edges but keep a path to very large values.
        uint256 offset = rawOffset % 4 == 0 ? rawOffset : bound(rawOffset, 0, count + 2);
        uint256 limit = rawLimit % 4 == 0 ? rawLimit : bound(rawLimit, 0, 52);

        if (limit == 0 || limit > 50) {
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, limit));
            registry.getDisputes(offset, limit);
            return;
        }
        if (offset > count || (offset == count && count != 0)) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, offset, count)
            );
            registry.getDisputes(offset, limit);
            return;
        }
        IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(offset, limit);
        uint256 remaining = count - offset;
        assertEq(page.length, remaining < limit ? remaining : limit);
        for (uint256 i; i < page.length; ++i) {
            assertEq(page[i].id, offset + i + 1);
            assertEq(
                keccak256(abi.encode(page[i])),
                _disputeDigest(offset + i + 1),
                "page differs from single read"
            );
        }
    }

    function testFuzz_getResponsesForArbitraryOffsetAndLimit(
        uint8 rawCount,
        uint256 rawOffset,
        uint256 rawLimit
    ) public {
        uint256 count = bound(rawCount, 0, 60);
        uint256 id = _open(alice);
        _open(bob); // a second dispute so the wrong collection would be noticed
        for (uint256 i; i < count; ++i) {
            vm.prank(wallets[i % 5]);
            registry.respond(id, bytes32(i + 1), URI, "r");
        }
        uint256 offset = rawOffset % 4 == 0 ? rawOffset : bound(rawOffset, 0, count + 2);
        uint256 limit = rawLimit % 4 == 0 ? rawLimit : bound(rawLimit, 0, 52);

        if (limit == 0 || limit > 50) {
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.InvalidPageLimit.selector, limit));
            registry.getResponses(id, offset, limit);
            return;
        }
        if (offset > count || (offset == count && count != 0)) {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, offset, count)
            );
            registry.getResponses(id, offset, limit);
            return;
        }
        IMDOracleDisputeRegistry.Response[] memory page = registry.getResponses(id, offset, limit);
        uint256 remaining = count - offset;
        assertEq(page.length, remaining < limit ? remaining : limit);
        for (uint256 i; i < page.length; ++i) {
            assertEq(page[i].evidenceHash, bytes32(offset + i + 1));
            assertEq(page[i].author, wallets[(offset + i) % 5]);
            assertEq(keccak256(abi.encode(page[i])), _responseDigest(id, offset + i));
        }
        // The neighbouring dispute is untouched by all of this.
        assertEq(registry.responseCount(2), 0);
        assertEq(registry.getResponses(2, 0, 50).length, 0);
    }

    function testFuzz_responsePagesCoverExactlyOnce(uint8 rawCount, uint8 rawLimit) public {
        uint256 count = bound(rawCount, 0, 60);
        uint256 limit = bound(rawLimit, 1, 50);
        uint256 id = _open(alice);
        for (uint256 i; i < count; ++i) {
            vm.prank(wallets[i % 5]);
            registry.respond(id, bytes32(i + 1), URI, "r");
        }
        uint256 offset;
        while (offset < count) {
            IMDOracleDisputeRegistry.Response[] memory page = registry.getResponses(id, offset, limit);
            assertGt(page.length, 0);
            assertLe(page.length, limit);
            for (uint256 i; i < page.length; ++i) {
                assertEq(page[i].evidenceHash, bytes32(offset + i + 1));
            }
            offset += page.length;
        }
        assertEq(offset, count);
        if (count == 0) {
            assertEq(registry.getResponses(id, 0, limit).length, 0);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IMDOracleDisputeRegistry.OffsetOutOfBounds.selector, count, count)
            );
            registry.getResponses(id, count, limit);
        }
    }

    function test_pagesReflectMixedStatuses() public {
        for (uint256 i; i < 4; ++i) {
            _open(wallets[i]);
        }
        vm.prank(bob);
        registry.withdrawDispute(2);
        vm.prank(dave);
        registry.withdrawDispute(4);
        IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(0, 50);
        assertEq(page.length, 4);
        assertEq(uint256(page[0].status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));
        assertEq(uint256(page[1].status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn));
        assertEq(uint256(page[2].status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));
        assertEq(uint256(page[3].status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn));
        assertEq(page[1].withdrawnAt, uint64(block.timestamp));
        assertEq(page[0].withdrawnAt, 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Rejected ETH transfers
    // ---------------------------------------------------------------------------------------------

    function test_everySelectorRejectsEther() public {
        uint256 id = _open(alice);
        vm.deal(bob, 10 ether);

        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeCall(
            IMDOracleDisputeRegistry.openDispute,
            (REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE)
        );
        calls[1] = abi.encodeCall(IMDOracleDisputeRegistry.respond, (id, EVIDENCE_HASH, URI, "paid"));
        calls[2] = abi.encodeCall(IMDOracleDisputeRegistry.withdrawDispute, (id));
        calls[3] = abi.encodeCall(IMDOracleDisputeRegistry.disputeCount, ());
        calls[4] = abi.encodeCall(IMDOracleDisputeRegistry.responseCount, (id));
        calls[5] = abi.encodeCall(IMDOracleDisputeRegistry.getDispute, (id));
        calls[6] = abi.encodeCall(IMDOracleDisputeRegistry.getResponse, (id, 0));
        calls[7] = abi.encodeCall(IMDOracleDisputeRegistry.getDisputes, (0, 1));
        calls[8] = abi.encodeCall(IMDOracleDisputeRegistry.getResponses, (id, 0, 1));
        calls[9] = abi.encodeWithSignature("MAX_TEXT_BYTES()");

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(bob);
            (bool ok,) = address(registry).call{value: 1 wei}(calls[i]);
            assertFalse(ok, "a selector accepted ETH");
        }
        // Empty calldata, and empty calldata with a 2300 gas stipend (a `transfer`-style send).
        vm.prank(bob);
        (bool okEmpty,) = address(registry).call{value: 1 ether}("");
        assertFalse(okEmpty);
        vm.prank(bob);
        (bool okStipend,) = address(registry).call{value: 1 wei, gas: 2300}("");
        assertFalse(okStipend);

        assertEq(address(registry).balance, 0);
        assertEq(bob.balance, 10 ether, "a failed transfer must refund the sender");
        assertEq(registry.disputeCount(), 1);
        assertEq(registry.responseCount(id), 0);
        assertEq(uint256(_status(id)), uint256(IMDOracleDisputeRegistry.DisputeStatus.Open));

        // The same calldata with no value goes through, so value was the only reason for the rejection.
        vm.prank(bob);
        (bool okNoValue,) = address(registry).call(calls[1]);
        assertTrue(okNoValue);
        assertEq(registry.responseCount(id), 1);
    }

    function testFuzz_anyValueIsRejected(uint96 rawValue, uint8 selectorIndex) public {
        uint256 value = bound(rawValue, 1, type(uint96).max);
        uint256 id = _open(alice);
        vm.deal(carol, value);
        bytes memory data;
        uint256 which = selectorIndex % 3;
        if (which == 0) {
            data = abi.encodeCall(
                IMDOracleDisputeRegistry.openDispute,
                (REQUEST_ID, SOURCE_CHAIN, SNAPSHOT_HASH, EVIDENCE_HASH, URI, RATIONALE)
            );
        } else if (which == 1) {
            data = abi.encodeCall(IMDOracleDisputeRegistry.respond, (id, EVIDENCE_HASH, URI, "paid"));
        } else {
            data = abi.encodeCall(IMDOracleDisputeRegistry.withdrawDispute, (id));
        }
        vm.prank(carol);
        (bool ok,) = address(registry).call{value: value}(data);
        assertFalse(ok);
        assertEq(address(registry).balance, 0);
        assertEq(carol.balance, value);
        assertEq(registry.disputeCount(), 1);
        assertEq(registry.responseCount(id), 0);
    }
}

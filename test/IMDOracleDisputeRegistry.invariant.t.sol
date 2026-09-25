// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDOracleDisputeRegistry} from "../src/IMDOracleDisputeRegistry.sol";

/// @dev Drives the registry with a handful of wallets and mirrors what the contract should have stored so
/// the invariants can check that nothing is ever edited, deleted or reordered.
contract RegistryHandler is Test {
    IMDOracleDisputeRegistry public immutable registry;

    address[] public actors;

    struct DisputeShadow {
        address challenger;
        bytes16 requestId;
        uint256 sourceChainId;
        bytes32 snapshot;
        bytes32 evidence;
        uint64 createdAt;
        bool withdrawn;
        uint64 withdrawnAt;
    }

    struct ResponseShadow {
        address author;
        bytes32 evidence;
        uint64 createdAt;
    }

    DisputeShadow[] public shadowDisputes;
    mapping(uint256 => ResponseShadow[]) public shadowResponses;

    uint256 public opened;
    uint256 public responded;
    uint256 public withdrawn;
    uint256 public rejectedWithdrawals;
    uint256 public rejectedLateResponses;

    constructor(IMDOracleDisputeRegistry r) {
        registry = r;
        actors.push(makeAddr("h-alice"));
        actors.push(makeAddr("h-bob"));
        actors.push(makeAddr("h-carol"));
        actors.push(makeAddr("h-dave"));
    }

    function shadowDisputeCount() external view returns (uint256) {
        return shadowDisputes.length;
    }

    function shadowResponseCount(uint256 disputeId) external view returns (uint256) {
        return shadowResponses[disputeId].length;
    }

    function open(uint256 actorSeed, bytes16 requestId, uint256 chainId, bytes32 snapshot, bytes32 evidence)
        external
    {
        address who = actors[actorSeed % actors.length];
        if (requestId == bytes16(0)) requestId = bytes16(uint128(1));
        if (chainId == 0) chainId = 1;
        if (snapshot == 0) snapshot = bytes32(uint256(1));
        if (evidence == 0) evidence = bytes32(uint256(2));
        vm.warp(block.timestamp + 1);
        vm.prank(who);
        uint256 id = registry.openDispute(requestId, chainId, snapshot, evidence, "ipfs://evidence", "why");
        assertEq(id, shadowDisputes.length + 1);
        shadowDisputes.push(
            DisputeShadow({
                challenger: who,
                requestId: requestId,
                sourceChainId: chainId,
                snapshot: snapshot,
                evidence: evidence,
                createdAt: uint64(block.timestamp),
                withdrawn: false,
                withdrawnAt: 0
            })
        );
        opened++;
    }

    function respond(uint256 actorSeed, uint256 idSeed, bytes32 evidence) external {
        if (shadowDisputes.length == 0) return;
        uint256 id = (idSeed % shadowDisputes.length) + 1;
        address who = actors[actorSeed % actors.length];
        if (evidence == 0) evidence = bytes32(uint256(3));
        vm.warp(block.timestamp + 1);
        vm.prank(who);
        if (shadowDisputes[id - 1].withdrawn) {
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
            registry.respond(id, evidence, "ipfs://r", "text");
            rejectedLateResponses++;
            return;
        }
        uint256 idx = registry.respond(id, evidence, "ipfs://r", "text");
        assertEq(idx, shadowResponses[id].length);
        shadowResponses[id].push(
            ResponseShadow({author: who, evidence: evidence, createdAt: uint64(block.timestamp)})
        );
        responded++;
    }

    function withdraw(uint256 actorSeed, uint256 idSeed) external {
        if (shadowDisputes.length == 0) return;
        uint256 id = (idSeed % shadowDisputes.length) + 1;
        address who = actors[actorSeed % actors.length];
        DisputeShadow storage s = shadowDisputes[id - 1];
        vm.warp(block.timestamp + 1);
        vm.prank(who);
        if (who != s.challenger) {
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, who));
            registry.withdrawDispute(id);
            rejectedWithdrawals++;
            return;
        }
        if (s.withdrawn) {
            vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.DisputeNotOpen.selector, id));
            registry.withdrawDispute(id);
            rejectedWithdrawals++;
            return;
        }
        registry.withdrawDispute(id);
        s.withdrawn = true;
        s.withdrawnAt = uint64(block.timestamp);
        withdrawn++;
    }
}

contract IMDOracleDisputeRegistryInvariantTest is Test {
    IMDOracleDisputeRegistry internal registry;
    RegistryHandler internal handler;

    function setUp() public {
        vm.warp(1_700_000_000);
        registry = new IMDOracleDisputeRegistry();
        handler = new RegistryHandler(registry);
        targetContract(address(handler));
    }

    /// @dev Every dispute the handler ever opened is still there, byte for byte, with the status the
    /// handler expects; every response is still there in order with its original author.
    function invariant_historyIsAppendOnlyAndImmutable() public view {
        uint256 n = handler.shadowDisputeCount();
        assertEq(registry.disputeCount(), n);
        for (uint256 id = 1; id <= n; ++id) {
            _checkDispute(id);
            _checkResponses(id);
        }
    }

    function _checkDispute(uint256 id) internal view {
        (
            address challenger,
            bytes16 requestId,
            uint256 chainId,
            bytes32 snapshot,
            bytes32 evidence,
            uint64 createdAt,
            bool withdrawnFlag,
            uint64 withdrawnAt
        ) = handler.shadowDisputes(id - 1);
        IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(id);
        assertEq(d.id, id);
        assertEq(d.challenger, challenger);
        assertEq(d.requestId, requestId);
        assertEq(d.sourceChainId, chainId);
        assertEq(d.attestationSnapshotHash, snapshot);
        assertEq(d.evidenceHash, evidence);
        assertEq(d.createdAt, createdAt);
        assertEq(d.withdrawnAt, withdrawnAt);
        IMDOracleDisputeRegistry.DisputeStatus expected = withdrawnFlag
            ? IMDOracleDisputeRegistry.DisputeStatus.Withdrawn
            : IMDOracleDisputeRegistry.DisputeStatus.Open;
        assertEq(uint256(d.status), uint256(expected));
    }

    function _checkResponses(uint256 id) internal view {
        uint256 m = handler.shadowResponseCount(id);
        assertEq(registry.responseCount(id), m);
        for (uint256 i; i < m; ++i) {
            (address author, bytes32 rEvidence, uint64 rCreatedAt) = handler.shadowResponses(id, i);
            IMDOracleDisputeRegistry.Response memory r = registry.getResponse(id, i);
            assertEq(r.author, author);
            assertEq(r.evidenceHash, rEvidence);
            assertEq(r.createdAt, rCreatedAt);
        }
    }

    /// @dev Paginated reads agree with single-item reads and never exceed the page limit.
    function invariant_pagesMatchSingleReads() public view {
        uint256 n = registry.disputeCount();
        uint256 offset;
        while (offset < n) {
            IMDOracleDisputeRegistry.Dispute[] memory page = registry.getDisputes(offset, 7);
            assertLe(page.length, 7);
            assertGt(page.length, 0);
            for (uint256 i; i < page.length; ++i) {
                IMDOracleDisputeRegistry.Dispute memory d = registry.getDispute(offset + i + 1);
                assertEq(page[i].id, d.id);
                assertEq(page[i].challenger, d.challenger);
                assertEq(uint256(page[i].status), uint256(d.status));
            }
            offset += page.length;
        }
    }

    /// @dev The registry never holds ETH.
    function invariant_holdsNoEther() public view {
        assertEq(address(registry).balance, 0);
    }
}

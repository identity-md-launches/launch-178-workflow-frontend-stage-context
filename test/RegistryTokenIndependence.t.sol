// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDOracleDisputeRegistry} from "../src/IMDOracleDisputeRegistry.sol";
import {OracleChallengeToken} from "../src/OracleChallengeToken.sol";

/// @title Registry use is independent of OCTEST balances and approvals
/// @notice The workflow requires that holding or spending OCTEST is never needed to use the registry. These
/// tests deploy both contracts locally from explicit callers, then drive every registry operation from
/// wallets that hold zero OCTEST and have granted no approval, and show that token balances, allowances
/// and supply are untouched by registry activity and vice versa.
contract RegistryTokenIndependenceTest is Test {
    IMDOracleDisputeRegistry internal registry;
    OracleChallengeToken internal token;

    address internal factory;
    address internal registryDeployer;
    address internal alice;
    address internal bob;
    address internal carol;

    bytes16 internal constant REQUEST_ID = bytes16(0x0192d5f8a3b14c6e9f2a7b8c1d3e4f50);
    bytes32 internal constant HASH_A = keccak256("a");
    bytes32 internal constant HASH_B = keccak256("b");

    function setUp() public {
        vm.warp(1_700_000_000);
        factory = makeAddr("factory");
        registryDeployer = makeAddr("registry-deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        vm.prank(factory);
        token = new OracleChallengeToken();
        vm.prank(registryDeployer);
        registry = new IMDOracleDisputeRegistry();
    }

    function _assertNoTokenPosition(address who) internal view {
        assertEq(token.balanceOf(who), 0, "wallet must hold no OCTEST");
        assertEq(token.allowance(who, address(registry)), 0, "wallet must not have approved the registry");
        assertEq(token.allowance(address(registry), who), 0);
        assertEq(token.allowance(who, registryDeployer), 0);
        assertEq(token.allowance(who, factory), 0);
    }

    function _usable(address a) internal view returns (bool) {
        return a != address(0) && a.code.length == 0 && a != address(vm) && a != factory
            && a != 0x000000000000000000636F6e736F6c652e6c6f67 && uint160(a) > 0xff;
    }

    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0 || hay.length < needle.length) return false;
        for (uint256 i; i + needle.length <= hay.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < needle.length; ++j) {
                if (hay[i + j] != needle[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }

    function test_setupWalletsHoldNoTokensAndNoApprovals() public view {
        _assertNoTokenPosition(alice);
        _assertNoTokenPosition(bob);
        _assertNoTokenPosition(carol);
        _assertNoTokenPosition(registryDeployer);
        assertEq(token.balanceOf(address(registry)), 0);
        assertEq(token.balanceOf(factory), 10 ** 27);
    }

    function test_fullDisputeLifecycleWithZeroBalanceAndNoApproval() public {
        _assertNoTokenPosition(alice);
        _assertNoTokenPosition(bob);
        _assertNoTokenPosition(carol);

        vm.prank(alice);
        uint256 id = registry.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://evidence", "wrong answer");
        vm.prank(bob);
        uint256 r0 = registry.respond(id, HASH_A, "ipfs://r0", "disagree");
        vm.prank(carol);
        uint256 r1 = registry.respond(id, HASH_B, "ipfs://r1", "agree");
        vm.prank(alice);
        registry.withdrawDispute(id);

        assertEq(id, 1);
        assertEq(r0, 0);
        assertEq(r1, 1);
        assertEq(registry.getDispute(id).challenger, alice);
        assertEq(registry.getResponse(id, 0).author, bob);
        assertEq(registry.getResponse(id, 1).author, carol);
        assertEq(
            uint256(registry.getDispute(id).status), uint256(IMDOracleDisputeRegistry.DisputeStatus.Withdrawn)
        );

        // Nothing moved on the token side.
        _assertNoTokenPosition(alice);
        _assertNoTokenPosition(bob);
        _assertNoTokenPosition(carol);
        assertEq(token.balanceOf(address(registry)), 0);
        assertEq(token.balanceOf(factory), 10 ** 27);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function testFuzz_anyZeroBalanceWalletCanUseTheRegistry(address who, address responder) public {
        vm.assume(_usable(who) && _usable(responder) && who != responder);
        assertEq(token.balanceOf(who), 0);
        assertEq(token.balanceOf(responder), 0);
        assertEq(token.allowance(who, address(registry)), 0);
        assertEq(token.allowance(responder, address(registry)), 0);

        vm.prank(who);
        uint256 id = registry.openDispute(REQUEST_ID, 42, HASH_A, HASH_B, "ipfs://e", "r");
        vm.prank(responder);
        registry.respond(id, HASH_A, "ipfs://x", "t");
        vm.prank(who);
        registry.withdrawDispute(id);

        assertEq(registry.getDispute(id).challenger, who);
        assertEq(registry.getResponse(id, 0).author, responder);
        assertEq(token.balanceOf(who), 0);
        assertEq(token.balanceOf(responder), 0);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function test_tokenHolderHasNoRegistryPrivilege() public {
        // The factory holds the entire supply. It is an ordinary registry participant.
        vm.prank(alice);
        uint256 id = registry.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://e", "r");
        vm.prank(factory);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, id, factory));
        registry.withdrawDispute(id);

        vm.prank(factory);
        uint256 own = registry.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://e", "from the holder");
        assertEq(own, 2);
        assertEq(registry.getDispute(own).challenger, factory);
        // Being a holder does not let it act for alice, and alice cannot act for it.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, own, alice));
        registry.withdrawDispute(own);
        assertEq(token.balanceOf(factory), 10 ** 27, "registry activity did not move the holder's tokens");
    }

    function test_approvingTheRegistryChangesNothingAndIsNeverSpent() public {
        // Even if a user approves the registry (by mistake), the registry never pulls tokens: it has no
        // external-call opcode, so the allowance stays exactly as granted through every operation.
        vm.prank(factory);
        token.transfer(alice, 1_000e18);
        vm.prank(alice);
        token.approve(address(registry), type(uint256).max);

        vm.prank(alice);
        uint256 id = registry.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://e", "r");
        vm.prank(alice);
        registry.respond(id, HASH_A, "ipfs://x", "t");
        vm.prank(alice);
        registry.withdrawDispute(id);

        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(token.allowance(alice, address(registry)), type(uint256).max);
        assertEq(token.balanceOf(address(registry)), 0);
    }

    function test_tokenTransfersDoNotAffectRegistryRecords() public {
        vm.prank(alice);
        uint256 id = registry.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://e", "r");
        vm.prank(bob);
        registry.respond(id, HASH_A, "ipfs://x", "t");
        bytes32 disputeBefore = keccak256(abi.encode(registry.getDispute(id)));
        bytes32 responseBefore = keccak256(abi.encode(registry.getResponse(id, 0)));

        vm.prank(factory);
        token.transfer(alice, 10 ** 27); // alice now holds everything
        vm.prank(alice);
        token.transfer(bob, 10 ** 26);
        vm.prank(bob);
        token.approve(alice, 5);

        assertEq(keccak256(abi.encode(registry.getDispute(id))), disputeBefore);
        assertEq(keccak256(abi.encode(registry.getResponse(id, 0))), responseBefore);
        assertEq(registry.disputeCount(), 1);
        // Holding all the tokens gives alice no new power: she still cannot withdraw bob's dispute.
        vm.prank(bob);
        uint256 bobs = registry.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://e", "bob");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDOracleDisputeRegistry.NotChallenger.selector, bobs, alice));
        registry.withdrawDispute(bobs);
    }

    function test_registryExposesNoTokenOrValueSurface() public {
        string[10] memory signatures = [
            "token()",
            "paymentToken()",
            "octest()",
            "fee()",
            "bond()",
            "stake(uint256)",
            "deposit()",
            "withdraw(uint256)",
            "claim()",
            "setToken(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            (bool ok,) = address(registry).call(abi.encodeWithSignature(signatures[i], address(token)));
            assertFalse(ok, signatures[i]);
        }
    }

    function test_registryRuntimeCannotReachTheToken() public view {
        bytes memory code = address(registry).code;
        assertGt(code.length, 0);
        // No external-call opcode of any kind, so no ERC-20 call can be made.
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            assertTrue(op != 0xF1 && op != 0xF2 && op != 0xF4 && op != 0xFA, "external call opcode present");
        }
        // No ERC-20 selector is embedded in the registry's runtime either.
        assertFalse(
            _contains(code, abi.encodePacked(bytes4(keccak256("transferFrom(address,address,uint256)"))))
        );
        assertFalse(_contains(code, abi.encodePacked(bytes4(keccak256("transfer(address,uint256)")))));
        assertFalse(_contains(code, abi.encodePacked(bytes4(keccak256("balanceOf(address)")))));
        assertFalse(_contains(code, abi.encodePacked(bytes4(keccak256("allowance(address,address)")))));
        assertFalse(_contains(code, abi.encodePacked(address(token))));
    }

    function test_deploymentOrderDoesNotMatter() public {
        // Registry first, token second, from yet another pair of callers: same behaviour.
        address d1 = makeAddr("d1");
        address d2 = makeAddr("d2");
        vm.prank(d1);
        IMDOracleDisputeRegistry r = new IMDOracleDisputeRegistry();
        vm.prank(d2);
        OracleChallengeToken t = new OracleChallengeToken();
        assertEq(t.balanceOf(d2), 10 ** 27);
        assertEq(t.balanceOf(d1), 0);
        vm.prank(d1);
        uint256 id = r.openDispute(REQUEST_ID, 1, HASH_A, HASH_B, "ipfs://e", "r");
        vm.prank(carol);
        r.respond(id, HASH_A, "ipfs://x", "t");
        vm.prank(d1);
        r.withdrawDispute(id);
        assertEq(t.balanceOf(d1), 0);
        assertEq(t.balanceOf(carol), 0);
        assertEq(r.disputeCount(), 1);
    }
}

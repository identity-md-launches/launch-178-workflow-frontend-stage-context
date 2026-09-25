// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OracleChallengeToken} from "../src/OracleChallengeToken.sol";

/// @dev Deploys the token from a distinct "factory" address so the test contract itself is not the
/// supply holder by accident, mirroring how ProjectFactory receives the launch supply.
contract OracleChallengeTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    OracleChallengeToken internal token;
    address internal factory;
    address internal alice;
    address internal bob;

    function setUp() public {
        factory = makeAddr("factory");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        vm.prank(factory);
        token = new OracleChallengeToken();
    }

    function test_metadata() public view {
        assertEq(token.name(), "Oracle Challenge Test");
        assertEq(token.symbol(), "OCTEST");
        assertEq(token.decimals(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(SUPPLY, 1e27);
    }

    function test_mintsWholeSupplyToDeployerOnce() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(factory), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.recordLogs();
        vm.prank(alice);
        OracleChallengeToken fresh = new OracleChallengeToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event in the constructor");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
    }

    function test_creationCodeHasNoConstructorArguments() public {
        // Deploying the bare creation code (nothing appended) must succeed and mint to the deployer.
        bytes memory code = type(OracleChallengeToken).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(code, 0x20), mload(code))
        }
        assertTrue(deployed != address(0), "bare creation code failed");
        assertEq(IERC20(deployed).totalSupply(), SUPPLY);
        assertEq(IERC20(deployed).balanceOf(address(this)), SUPPLY);
    }

    function test_transferMovesExactAmount() public {
        vm.prank(factory);
        assertTrue(token.transfer(alice, 1_000e18));
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(token.balanceOf(factory), SUPPLY - 1_000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(factory);
        token.approve(alice, 500e18);
        assertEq(token.allowance(factory, alice), 500e18);
        vm.prank(alice);
        assertTrue(token.transferFrom(factory, bob, 200e18));
        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.allowance(factory, alice), 300e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 300e18, 301e18)
        );
        token.transferFrom(factory, bob, 301e18);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(factory);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_noMintOrAdminSelectorChangesSupply() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)"
        ];
        address[2] memory callers = [factory, address(0xBEEF)];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < signatures.length; ++i) {
                bytes memory data = abi.encodeWithSignature(signatures[i], callers[c], type(uint128).max);
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
                assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            }
        }
        assertEq(token.balanceOf(factory), SUPPLY);
        assertEq(token.balanceOf(address(0xBEEF)), 0);
    }

    function test_rejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    function testFuzz_transferConservesSupply(uint256 amount, address to) public {
        vm.assume(to != address(0) && to != factory);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(factory);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to) + token.balanceOf(factory), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

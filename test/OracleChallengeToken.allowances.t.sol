// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OracleChallengeToken} from "../src/OracleChallengeToken.sol";

/// @dev A contract that deploys the token in its own constructor, standing in for a factory contract.
contract TokenDeployer {
    OracleChallengeToken public immutable token;

    constructor() {
        token = new OracleChallengeToken();
    }
}

/// @title Supply, transfer and allowance tests for OracleChallengeToken
/// @notice Complements `OracleChallengeToken.t.sol` with the allowance surface, the insufficient-balance
/// and insufficient-allowance paths with their exact ERC-6093 arguments, deployments from several
/// distinct callers (EOA-style pranks and a deploying contract), and fuzzed sequences of transfers and
/// approvals that must leave the supply at exactly 10^27.
contract OracleChallengeTokenAllowancesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    OracleChallengeToken internal token;
    address internal factory;
    address internal alice;
    address internal bob;
    address internal carol;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        factory = makeAddr("factory");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        vm.prank(factory);
        token = new OracleChallengeToken();
    }

    function _usable(address a) internal view returns (bool) {
        return a != address(0) && a.code.length == 0 && a != address(vm)
            && a != 0x000000000000000000636F6e736F6c652e6c6f67 && uint160(a) > 0xff;
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and initial supply
    // ---------------------------------------------------------------------------------------------

    function test_metadataMatchesWorkflow() public view {
        assertEq(token.name(), "Oracle Challenge Test");
        assertEq(token.symbol(), "OCTEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.TOTAL_SUPPLY(), 10 ** 27);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_constructorCallerReceivesExactSupplyAndNobodyElse() public view {
        assertEq(token.balanceOf(factory), 10 ** 27);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_anyDeployerReceivesTheWholeSupply(address deployer) public {
        vm.assume(_usable(deployer));
        vm.prank(deployer);
        OracleChallengeToken fresh = new OracleChallengeToken();
        assertEq(fresh.totalSupply(), 10 ** 27);
        assertEq(fresh.balanceOf(deployer), 10 ** 27);
        assertEq(fresh.balanceOf(factory), 0, "an earlier deployer gets nothing from a new deployment");
        assertEq(token.totalSupply(), 10 ** 27, "a second deployment does not touch the first");
    }

    function test_contractDeployerReceivesTheWholeSupply() public {
        TokenDeployer d = new TokenDeployer();
        OracleChallengeToken fresh = d.token();
        assertEq(fresh.balanceOf(address(d)), 10 ** 27);
        assertEq(fresh.balanceOf(address(this)), 0, "the outer caller is not the constructor caller");
        assertEq(fresh.totalSupply(), 10 ** 27);
    }

    function test_independentDeploymentsHaveIndependentLedgers() public {
        vm.prank(alice);
        OracleChallengeToken second = new OracleChallengeToken();
        vm.prank(alice);
        second.transfer(bob, 5e18);
        assertEq(second.balanceOf(bob), 5e18);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(second.balanceOf(factory), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Standard transfers
    // ---------------------------------------------------------------------------------------------

    function test_transferChainAcrossSeveralAccountsConservesSupply() public {
        vm.prank(factory);
        assertTrue(token.transfer(alice, 300e18));
        vm.prank(alice);
        assertTrue(token.transfer(bob, 120e18));
        vm.prank(bob);
        assertTrue(token.transfer(carol, 20e18));
        vm.prank(carol);
        assertTrue(token.transfer(factory, 5e18));

        assertEq(token.balanceOf(alice), 180e18);
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(carol), 15e18);
        assertEq(token.balanceOf(factory), SUPPLY - 295e18);
        assertEq(
            token.balanceOf(factory) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol),
            SUPPLY
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEmitsExactEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(factory, alice, 7);
        vm.prank(factory);
        token.transfer(alice, 7);
    }

    function test_zeroAmountAndSelfTransferAreNoOps() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0), "zero transfer from an empty account is allowed");
        assertEq(token.balanceOf(bob), 0);

        vm.prank(factory);
        assertTrue(token.transfer(factory, 123e18));
        assertEq(token.balanceOf(factory), SUPPLY);

        vm.prank(factory);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalanceThenOneMoreWeiFails() public {
        vm.prank(factory);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(factory), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.prank(factory);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, factory, 0, 1));
        token.transfer(bob, 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, SUPPLY + 1)
        );
        token.transfer(bob, SUPPLY + 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_insufficientBalanceReportsExactShortfall() public {
        vm.prank(factory);
        token.transfer(alice, 100);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 100, 101)
        );
        token.transfer(bob, 101);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowances
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsOverwritesAndClears() public {
        assertEq(token.allowance(factory, alice), 0);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(factory, alice, 100e18);
        vm.prank(factory);
        assertTrue(token.approve(alice, 100e18));
        assertEq(token.allowance(factory, alice), 100e18);

        // approve overwrites rather than adds.
        vm.prank(factory);
        token.approve(alice, 40e18);
        assertEq(token.allowance(factory, alice), 40e18);

        vm.prank(factory);
        token.approve(alice, 0);
        assertEq(token.allowance(factory, alice), 0);

        // Allowances are directional and per pair.
        assertEq(token.allowance(alice, factory), 0);
        assertEq(token.allowance(factory, bob), 0);
    }

    function test_approveWithoutBalanceIsAllowedButSpendFails() public {
        // An empty account may grant an allowance; spending it fails on balance, not on allowance.
        vm.prank(alice);
        token.approve(bob, 50);
        assertEq(token.allowance(alice, bob), 50);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 50));
        token.transferFrom(alice, carol, 50);
        assertEq(token.allowance(alice, bob), 50, "a failed spend leaves the allowance intact");
    }

    function test_approveZeroAddressSpenderReverts() public {
        vm.prank(factory);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromWithoutAnyAllowanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(factory, alice, 1);
        assertEq(token.balanceOf(factory), SUPPLY);
    }

    function test_transferFromByOwnerStillNeedsAnAllowance() public {
        // Standard ERC-20 behaviour: transferFrom(from == msg.sender) reads allowance(from, from).
        vm.prank(factory);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, factory, 0, 1)
        );
        token.transferFrom(factory, alice, 1);
    }

    function test_transferFromSpendsExactlyAndStopsAtZero() public {
        vm.prank(factory);
        token.approve(alice, 100);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(factory, bob, 60);
        vm.prank(alice);
        assertTrue(token.transferFrom(factory, bob, 60));
        assertEq(token.allowance(factory, alice), 40);

        vm.prank(alice);
        assertTrue(token.transferFrom(factory, carol, 40));
        assertEq(token.allowance(factory, alice), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(factory, bob, 1);

        assertEq(token.balanceOf(bob), 60);
        assertEq(token.balanceOf(carol), 40);
        assertEq(token.balanceOf(factory), SUPPLY - 100);
        assertEq(token.balanceOf(alice), 0, "the spender receives nothing itself");
    }

    function test_transferFromInsufficientAllowanceReportsExactValues() public {
        vm.prank(factory);
        token.approve(alice, 99);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 99, 100)
        );
        token.transferFrom(factory, bob, 100);
        assertEq(token.allowance(factory, alice), 99);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromInsufficientBalanceWithSufficientAllowance() public {
        vm.prank(factory);
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 1000);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        token.transferFrom(alice, carol, 11);
        assertEq(token.allowance(alice, bob), 1000);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(factory);
        token.approve(alice, 5);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(factory, address(0), 5);
        assertEq(token.allowance(factory, alice), 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxAllowanceIsNotDecremented() public {
        vm.prank(factory);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(factory, bob, 1e18);
        assertEq(token.allowance(factory, alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 1e18);
    }

    function test_noLegacyAllowanceMutators() public {
        // OpenZeppelin v5 removed increaseAllowance/decreaseAllowance; the token exposes no such surface.
        vm.prank(factory);
        (bool okInc,) =
            address(token).call(abi.encodeWithSignature("increaseAllowance(address,uint256)", alice, 1));
        assertFalse(okInc);
        vm.prank(factory);
        (bool okDec,) =
            address(token).call(abi.encodeWithSignature("decreaseAllowance(address,uint256)", alice, 1));
        assertFalse(okDec);
        assertEq(token.allowance(factory, alice), 0);
    }

    function test_rejectsEtherOnEverySelector() public {
        vm.deal(alice, 1 ether);
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(IERC20.transfer, (bob, 0));
        calls[1] = abi.encodeCall(IERC20.approve, (bob, 0));
        calls[2] = abi.encodeCall(IERC20.transferFrom, (alice, bob, 0));
        calls[3] = abi.encodeCall(IERC20.balanceOf, (alice));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(alice);
            (bool ok,) = address(token).call{value: 1 wei}(calls[i]);
            assertFalse(ok, "token accepted ETH");
        }
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzzed supply conservation
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferFromRespectsBothLimits(
        uint256 rawBalance,
        uint256 rawAllowance,
        uint256 rawAmount
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 allowance = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(factory);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(bob, allowance);

        vm.prank(bob);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowance, amount
                )
            );
            token.transferFrom(alice, carol, amount);
            assertEq(token.balanceOf(alice), balance);
            assertEq(token.allowance(alice, bob), allowance);
        } else if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount)
            );
            token.transferFrom(alice, carol, amount);
            assertEq(token.balanceOf(alice), balance);
            assertEq(token.allowance(alice, bob), allowance);
        } else {
            assertTrue(token.transferFrom(alice, carol, amount));
            assertEq(token.balanceOf(alice), balance - amount);
            assertEq(token.balanceOf(carol), amount);
            assertEq(token.allowance(alice, bob), allowance - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(factory) + token.balanceOf(alice) + token.balanceOf(carol), SUPPLY);
    }

    function testFuzz_randomTransferSequenceKeepsSupplyFixed(uint256 seed) public {
        address[4] memory accounts = [factory, alice, bob, carol];
        for (uint256 step; step < 24; ++step) {
            bytes32 h = keccak256(abi.encode(seed, step));
            address from = accounts[uint8(h[0]) % 4];
            address to = accounts[uint8(h[1]) % 4];
            address spender = accounts[uint8(h[2]) % 4];
            uint256 amount = uint256(h) % (SUPPLY / 3);
            uint256 mode = uint8(h[3]) % 3;
            uint256 fromBefore = token.balanceOf(from);

            if (mode == 0) {
                vm.prank(from);
                if (amount > fromBefore) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientBalance.selector, from, fromBefore, amount
                        )
                    );
                }
                token.transfer(to, amount);
            } else if (mode == 1) {
                vm.prank(from);
                token.approve(spender, amount);
                assertEq(token.allowance(from, spender), amount);
            } else {
                uint256 allowed = token.allowance(from, spender);
                vm.prank(spender);
                if (amount > allowed) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount
                        )
                    );
                } else if (amount > fromBefore) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientBalance.selector, from, fromBefore, amount
                        )
                    );
                }
                token.transferFrom(from, to, amount);
            }

            assertEq(token.totalSupply(), SUPPLY, "supply drifted");
            assertEq(
                token.balanceOf(factory) + token.balanceOf(alice) + token.balanceOf(bob)
                    + token.balanceOf(carol),
                SUPPLY,
                "balances no longer sum to the supply"
            );
        }
    }

    function testFuzz_transferBetweenArbitraryAccountsIsExact(address to, uint256 rawAmount) public {
        vm.assume(_usable(to) && to != factory);
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(factory);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(factory), SUPPLY - amount);
        // And back again, from an account that never approved anyone.
        vm.prank(to);
        assertTrue(token.transfer(factory, amount));
        assertEq(token.balanceOf(to), 0);
        assertEq(token.balanceOf(factory), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

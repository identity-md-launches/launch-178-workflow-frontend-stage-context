// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Oracle Challenge Test (OCTEST)
/// @notice The separate, fixed-supply launch token for the IMD Oracle Challenges Sepolia experiment.
/// @dev Plain OpenZeppelin ERC-20 with no owner, minter, pauser, fee, hook, proxy or upgrade path.
/// The entire supply of exactly 1,000,000,000 tokens (10^27 minor units at 18 decimals) is minted once,
/// in the constructor, to `msg.sender`. When IMD's ProjectFactory deploys the token, the factory is that
/// caller and performs the policy allocations (liquidity, contributor rewards) itself. No function in this
/// contract can change the supply afterwards. The dispute registry never reads, holds or moves OCTEST.
contract OracleChallengeToken is ERC20 {
    /// @notice Total supply in minor units: 1,000,000,000 * 10^18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("Oracle Challenge Test", "OCTEST") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}

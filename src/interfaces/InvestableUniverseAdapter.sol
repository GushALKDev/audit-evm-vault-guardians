// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit-info - Unused imports should be removed
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// @audit-question - Why this interface is commented?
// @audit-info - The name of the file is InvestableUniverseAdapter.sol, it doesn't match with the name of the interface, IInvestableUniverseAdapter
interface IInvestableUniverseAdapter {
// function invest(IERC20 token, uint256 amount) external;
// function divest(IERC20 token, uint256 amount) external;
}

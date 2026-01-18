/**
 *  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _
 * |_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_|
 * |_|                                                                                          |_|
 * |_| █████   █████                      ████   █████                                          |_|
 * |_|░░███   ░░███                      ░░███  ░░███                                           |_|
 * |_| ░███    ░███   ██████   █████ ████ ░███  ███████                                         |_|
 * |_| ░███    ░███  ░░░░░███ ░░███ ░███  ░███ ░░░███░                                          |_|
 * |_| ░░███   ███    ███████  ░███ ░███  ░███   ░███                                           |_|
 * |_|  ░░░█████░    ███░░███  ░███ ░███  ░███   ░███ ███                                       |_|
 * |_|    ░░███     ░░████████ ░░████████ █████  ░░█████                                        |_|
 * |_|     ░░░       ░░░░░░░░   ░░░░░░░░ ░░░░░    ░░░░░                                         |_|
 * |_|                                                                                          |_|
 * |_|                                                                                          |_|
 * |_|                                                                                          |_|
 * |_|   █████████                                     █████  ███                               |_|
 * |_|  ███░░░░░███                                   ░░███  ░░░                                |_|
 * |_| ███     ░░░  █████ ████  ██████   ████████   ███████  ████   ██████   ████████    █████  |_|
 * |_|░███         ░░███ ░███  ░░░░░███ ░░███░░███ ███░░███ ░░███  ░░░░░███ ░░███░░███  ███░░   |_|
 * |_|░███    █████ ░███ ░███   ███████  ░███ ░░░ ░███ ░███  ░███   ███████  ░███ ░███ ░░█████  |_|
 * |_|░░███  ░░███  ░███ ░███  ███░░███  ░███     ░███ ░███  ░███  ███░░███  ░███ ░███  ░░░░███ |_|
 * |_| ░░█████████  ░░████████░░████████ █████    ░░████████ █████░░████████ ████ █████ ██████  |_|
 * |_|  ░░░░░░░░░    ░░░░░░░░  ░░░░░░░░ ░░░░░      ░░░░░░░░ ░░░░░  ░░░░░░░░ ░░░░ ░░░░░ ░░░░░░   |_|
 * |_| _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _ |_|
 * |_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_|
 */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
// @audit-info - This version of solidity contains the PUSH0 opcode, which is not compatible with all L2 networks.
// @audit-info - This problem is spread across the codebase.

import {VaultGuardiansBase, IERC20, SafeERC20} from "./VaultGuardiansBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* 
 * @title VaultGuardians
 * @author Vault Guardian
 * @notice This contract is the entry point for the Vault Guardian system.
 * @notice It includes all the functionality that the DAO has control over. 
 * @notice the VaultGuardiansBase has all the users & guardians functionality.
 */
contract VaultGuardians is Ownable, VaultGuardiansBase {
    using SafeERC20 for IERC20;

    // @audit-info - Unused custom error.
    error VaultGuardians__TransferFailed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event VaultGuardians__UpdatedStakePrice(uint256 oldStakePrice, uint256 newStakePrice);
    event VaultGuardians__UpdatedFee(uint256 oldFee, uint256 newFee);
    // @audit-info - Missing indexed parameter
    event VaultGuardians__SweptTokens(address asset);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address aavePool,
        address uniswapV2Router,
        address weth,
        address tokenOne,
        address tokenTwo,
        address vaultGuardiansToken
    )
        Ownable(msg.sender)
        VaultGuardiansBase(aavePool, uniswapV2Router, weth, tokenOne, tokenTwo, vaultGuardiansToken)
    {}

    /*
     * @notice Updates the stake price for guardians. 
     * @param newStakePrice The new stake price in wei
     */
     // @audit-info - Centralization issue, a compromised owner can update the stake price
     // @audit-answered-question - What is this price used for?
     // @audit-answer - It is the amount of tokens required to stake to become a guardian (Sybil protection / Economic spam filter).
     // @audit-answered-question - Should it be protected of zero value?
     // @audit-answer - Yes. Setting it to zero allows cost-free guardian creation, leading to potential spam/DoS of the registry with junk vaults.
    function updateGuardianStakePrice(uint256 newStakePrice) external onlyOwner {
        // @audit-issue - HIGH -> IMPACT: MEDIUM/HIGH - LIKELIHOOD: LOW
        // @audit-issue - Missing non-zero check for newStakePrice.
        // @audit-issue - If set to 0, it enables cost-free guardian creation (Spam/Sybil Attack vector).
        // @audit-issue - RECOMMENDED MITIGATION: require(newStakePrice > 0, "Stake price cannot be zero");
        s_guardianStakePrice = newStakePrice;
        // @audit-issue - MEDIUM -> IMPACT: LOW -> LIKELIHOOD: HIGH
        // @audit-issue - s_guardianStakePrice is already updated here, so, in the event is equal to the newStakePrice
        // @audit-issue - RECOMMENDED MITIGATION: Emit the old value before updating the state variable
        emit VaultGuardians__UpdatedStakePrice(s_guardianStakePrice, newStakePrice);
    }

    /*
     * @notice Updates the percentage shares guardians & Daos get in new vaults
     * @param newCut the new cut
     * @dev this value will be divided by the number of shares whenever a user deposits into a vault
     * @dev historical vaults will not have their cuts updated, only vaults moving forward
     */
     // @audit-answered-question - What is this cut used for?
     // @audit-answer - It is the percentage of the vault's share that guardians and DAOs receive when a new vault is created.
     // @audit-answered-question - What is the range of this cut and its exact formular?
     // @audit-answer - The cut is a percentage of the total shares, so it ranges from 0 to 100%.
     // @audit-answered-question - Should it be protected of zero value?
     // @audit-answer - Yes. Setting it to zero would allow guardians to receive no share of the vault's share, which could be exploited to prevent guardians from receiving any share of the vault's share.
     // @audit-info - Centralization issue, a compromised owner can update the cut
    function updateGuardianAndDaoCut(uint256 newCut) external onlyOwner {
        // @audit-issue - MEDIUM -> IMPACT: HIGH - LIKELIHOOD: LOW
        // @audit-issue - Missing validation for newCut.
        // @audit-issue - If set to 0, `VaultShares.deposit` will revert due to division by zero (shares / cut), causing DoS on all new vaults.
        // @audit-issue - If set to a small value (e.g. 1), it causes massive share inflation (100% fee).
        // @audit-issue - RECOMMENDED MITIGATION: require(newCut >= MIN_CUT, "Cut too small or zero");
        s_guardianAndDaoCut = newCut;
        // @audit-issue - MEDIUM -> IMPACT: LOW -> LIKELIHOOD: HIGH
        // @audit-issue - s_guardianAndDaoCut is already updated here, so, in the event is equal to the newCut
        // @audit-issue - RECOMMENDED MITIGATION: Emit the old value before updating the state variable
        // @audit-issue - MEDIUM -> IMPACT: LOW -> LIKELIHOOD: HIGH
        // @audit-issue - The name of this event is wrong, it should be VaultGuardians__UpdatedGuardianAndDaoCut
        // @audit-issue - RECOMMENDED MITIGATION: Rename the event to VaultGuardians__UpdatedGuardianAndDaoCut and create it.
        emit VaultGuardians__UpdatedStakePrice(s_guardianAndDaoCut, newCut);
    }

    /*
     * @notice Any excess ERC20s can be scooped up by the DAO. 
     * @notice This is often just little bits left around from swapping or rounding errors
     * @dev Since this is owned by the DAO, the funds will always go to the DAO. 
     * @param asset The ERC20 to sweep
     */
     // @audit-answered-question - Is any ERC20 sent to this contract at any point?
     // @audit-answer - Yes, this contract will hold the DAO fees.
    function sweepErc20s(IERC20 asset) external {
        uint256 amount = asset.balanceOf(address(this));
        emit VaultGuardians__SweptTokens(address(asset));
        // @audit-answered-question - Is the owner the right address to send the funds to?
        // @audit-answer - Yes, the owner is the DAO.
        asset.safeTransfer(owner(), amount);
    }
    
    // @audit-issue - HIGH -> IMPACT: HIGH -> LIKELIHOOD: HIGH
    // @audit-issue - ETH stuck in contract & Unsafe Token Fee withdrawal.
    // @audit-issue - ETH Fees: The contract receives ETH from `becomeGuardian` but has NO function to withdraw it. Funds are permanently locked.
    // @audit-issue - Token Fees: If DAO fees (shares) are sent to this contract, the only way to withdraw them is check-all `sweepErc20s`, which is intended for dust/error recovery, not regular fee management.
    // @audit-issue - RECOMMENDED MITIGATION: Add `withdrawEth()` and a dedicated `withdrawFees(token, amount)` function.
}

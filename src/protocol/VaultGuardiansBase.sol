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

import {VaultShares} from "./VaultShares.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultShares, IVaultData} from "../interfaces/IVaultShares.sol";
import {AStaticTokenData, IERC20} from "../abstract/AStaticTokenData.sol";
import {VaultGuardianToken} from "../dao/VaultGuardianToken.sol";

/*
 * @title VaultGuardiansBase
 * @author Vault Guardian
 * @notice This contract is the base contract for the VaultGuardians contract.
 * @notice it includes all the functionality of a user or guardian interacting with the protocol
 */


contract VaultGuardiansBase is AStaticTokenData, IVaultData {
    using SafeERC20 for IERC20;

    // @audit-info - Unused custom error.
    error VaultGuardiansBase__NotEnoughWeth(uint256 amount, uint256 amountNeeded);
    error VaultGuardiansBase__NotAGuardian(address guardianAddress, IERC20 token);
    // @audit-info - Unused custom error.
    error VaultGuardiansBase__CantQuitGuardianWithNonWethVaults(address guardianAddress);
    error VaultGuardiansBase__CantQuitWethWithThisFunction();
    error VaultGuardiansBase__TransferFailed();
    // @audit-info - Unused custom error.
    error VaultGuardiansBase__FeeTooSmall(uint256 fee, uint256 requiredFee);
    error VaultGuardiansBase__NotApprovedToken(address token);

    // @audit-info - Section without any content
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address private immutable i_aavePool;
    address private immutable i_uniswapV2Router;
    // @audit-answered-question - Is this the Governance token?
    // @audit-answer - Yes, this is the Governance token.
    VaultGuardianToken private immutable i_vgToken;

    // @audit-answered-question - Is this fee paid or received by the guardian?
    // @audit-answer - Fee paid by the guardian in ETH
    uint256 private constant GUARDIAN_FEE = 0.1 ether;

    // DAO updatable values
    // @audit-note // Amount staked by the guardian in Tokens
    // @audit-issue - HIGH -> IMPACT: HIGH -> LIKELIHOOD: HIGH
    // @audit-issue - 10 ether == 10e18, it's 10 tokens for an 18 decimals token, but it's 10e12 for a 6 decimals tokens like USDC 
    // @audit-issue - or 10e10 tokens for WBTC, this make no posible to create the vault for those tokens.
    // @audit-issue - In adition, the difference in value between tokens with 18 decimales I.E LINK and WETH make no sense.
    // @audit-issue - This value should be token dependant.
    uint256 internal s_guardianStakePrice = 10 ether;
    // @audit-note - Temporary fix for audit testing to support USDC (1e9 USDC) and WETH (0.001 ETH) - UNCOMMENT TO RUN FORK TESTS
    // @audit-note - uint256 internal s_guardianStakePrice = 1e15;
    // @audit-answered-question - Should this value be the same here and in the VaultShares?
    // @audit-answer - Yes, this value should be the same here and in the VaultShares.
    uint256 internal s_guardianAndDaoCut = 1000;

    // The guardian's address mapped to the asset, mapped to the allocation data
    // @audit-answered-question - IVaultShares ConstructorData has usdc and weth hardcoded, what about LINK?
    // @audit-answer - Not neccesary, USDC and WETH are there as the counterparty in Uniswap
    mapping(address guardianAddress => mapping(IERC20 asset => IVaultShares vaultShares)) private s_guardians;
    mapping(address token => bool approved) private s_isApprovedToken;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    // @audit-info - Missing indexed parameter
    event GuardianAdded(address guardianAddress, IERC20 token);
    // @audit-info - Missing indexed parameter
    // @audit-info - Typo in event name: GaurdianRemoved -> GuardianRemoved
    event GaurdianRemoved(address guardianAddress, IERC20 token);
    // @audit-info - Missing indexed parameter
    event InvestedInGuardian(address guardianAddress, IERC20 token, uint256 amount);
    // @audit-info - Missing indexed parameter
    // @audit-info - Typo in event name: DinvestedFromGuardian -> DivestedFromGuardian
    event DinvestedFromGuardian(address guardianAddress, IERC20 token, uint256 amount);
    // @audit-info - Missing indexed parameter
    event GuardianUpdatedHoldingAllocation(address guardianAddress, IERC20 token);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyGuardian(IERC20 token) {
        if (address(s_guardians[msg.sender][token]) == address(0)) {
            revert VaultGuardiansBase__NotAGuardian(msg.sender, token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address aavePool,
        address uniswapV2Router,
        address weth,
        address tokenOne, // USDC
        address tokenTwo, // LINK
        address vgToken
    ) AStaticTokenData(weth, tokenOne, tokenTwo) {
        s_isApprovedToken[weth] = true;
        s_isApprovedToken[tokenOne] = true;
        s_isApprovedToken[tokenTwo] = true;

        i_aavePool = aavePool;
        i_uniswapV2Router = uniswapV2Router;
        i_vgToken = VaultGuardianToken(vgToken);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice allows a user to become a guardian
     * @notice they have to send an ETH amount equal to the fee, and a WETH amount equal to the stake price
     * 
     * @param wethAllocationData the allocation data for the WETH vault
     */
    // @audit-note Vault Factory
    // @audit-answered-question - asset is always WETH?
    // @audit-answer - Yes, the vault is created for WETH, there are other function below for other tokens
    // @audit-answered-question - vaultName and vaultSymbol are hardcoded
    // @audit-answer - Yes, it's right, there are other function below for other tokens
    function becomeGuardian(AllocationData memory wethAllocationData) external returns (address) {
        VaultShares wethVault =
        new VaultShares(IVaultShares.ConstructorData({
            asset: i_weth,
            vaultName: WETH_VAULT_NAME,
            vaultSymbol: WETH_VAULT_SYMBOL,
            guardian: msg.sender,
            allocationData: wethAllocationData,
            aavePool: i_aavePool,
            uniswapRouter: i_uniswapV2Router,
            guardianAndDaoCut: s_guardianAndDaoCut,
            vaultGuardians: address(this),
            weth: address(i_weth),
            usdc: address(i_tokenOne)
        }));
        return _becomeTokenGuardian(i_weth, wethVault);
        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: MEDIUM
        // @audit-issue - Missing event emit
    }

    /**
     * @notice Allows anyone to become a vault guardian for any one of the other supported tokens (USDC, LINK)
     * @notice However, only WETH vault guardians can become vault guardians for other tokens
     * @param allocationData A struct indicating the ratio of asset tokens to hold, invest in Aave and Uniswap (based on Vault Guardian strategy)
     * @param token The token to become a Vault Guardian for
     */
     // @audit-answered-question - The stake should be refunded to the guardian if he close the vault?
     // @audit-answer - Yes, it should be refunded.
    function becomeTokenGuardian(AllocationData memory allocationData, IERC20 token)
        external
        onlyGuardian(i_weth)
        returns (address)
    {
        //slither-disable-next-line uninitialized-local
        VaultShares tokenVault;
        // @audit-note tokenOne -> USDC
        // @audit-info It's not a good practice to write the full object twice, we can use the same object with different values where necessary, what if we want 50 different tokens?
        if (address(token) == address(i_tokenOne)) {
            tokenVault =
            new VaultShares(IVaultShares.ConstructorData({
                asset: token,
                vaultName: TOKEN_ONE_VAULT_NAME,
                vaultSymbol: TOKEN_ONE_VAULT_SYMBOL,
                guardian: msg.sender,
                allocationData: allocationData,
                aavePool: i_aavePool,
                uniswapRouter: i_uniswapV2Router,
                guardianAndDaoCut: s_guardianAndDaoCut,
                vaultGuardians: address(this),
                weth: address(i_weth),
                usdc: address(i_tokenOne)
            }));
        // @audit-note tokenTwo -> LINK
        // @audit-issue - MEDIUM -> IMPACT: LOW - LIKELIHOOD: HIGH
        // @audit-issue - The vault name and symbol are wrong, it's using the USDC ones
        } else if (address(token) == address(i_tokenTwo)) {
            tokenVault =
            new VaultShares(IVaultShares.ConstructorData({
                asset: token,
                vaultName: TOKEN_ONE_VAULT_NAME,
                vaultSymbol: TOKEN_ONE_VAULT_SYMBOL,
                guardian: msg.sender,
                allocationData: allocationData,
                aavePool: i_aavePool,
                uniswapRouter: i_uniswapV2Router,
                guardianAndDaoCut: s_guardianAndDaoCut,
                vaultGuardians: address(this),
                weth: address(i_weth),
                usdc: address(i_tokenOne)
            }));
        } else {
            revert VaultGuardiansBase__NotApprovedToken(address(token));
        }
        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: MEDIUM
        // @audit-issue - Missing event emit
        return _becomeTokenGuardian(token, tokenVault);
    }

    /*
     * @notice allows a guardian to quit
     * @dev this will only work if they only have a WETH vault left, a guardian can't quit if they have other vaults
     * @dev they will need to approve this contract to spend their shares tokens
     * @dev this will set the vault to no longer be active, meaning users can only withdraw tokens, and no longer deposit to the vault
     * @dev tokens should also no longer be invested into the protocols
     */
    function quitGuardian() external onlyGuardian(i_weth) returns (uint256) {
        if (_guardianHasNonWethVaults(msg.sender)) {
            // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: MEDIUM
            // @audit-issue - The custom error is wrong, it should be `VaultGuardiansBase__CantQuitGuardianWithNonWethVaults()`.
            revert VaultGuardiansBase__CantQuitWethWithThisFunction();
        }
        return _quitGuardian(i_weth);
    }

    /*
     * See VaultGuardiansBase::quitGuardian()
     * The only difference here, is that this function is for non-WETH vaults
     */
    function quitGuardian(IERC20 token) external onlyGuardian(token) returns (uint256) {
        if (token == i_weth) {
            revert VaultGuardiansBase__CantQuitWethWithThisFunction();
        }
        return _quitGuardian(token);
    }

    /**
     * @notice Allows Vault Guardians to update their allocation ratio (and thus, their strategy of investment)
     * @param token The token vault whose allocation ratio is to be updated
     * @param tokenAllocationData The new allocation data
     */
    function updateHoldingAllocation(IERC20 token, AllocationData memory tokenAllocationData)
        external
        onlyGuardian(token)
    {
        emit GuardianUpdatedHoldingAllocation(msg.sender, token);
        s_guardians[msg.sender][token].updateHoldingAllocation(tokenAllocationData);
    }

    // @audit-info - Section without any content
    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @audit-info - Section without any content
    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _quitGuardian(IERC20 token) private returns (uint256) {
        // @audit-info - Double casting to IVaultShares, the mapping already returns an IVaultShares object
        IVaultShares tokenVault = IVaultShares(s_guardians[msg.sender][token]);
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - Setting the mapping to 0 breaks the connection to the vault.
        // @audit-issue - Users rely on this mapping to find the vault address to withdraw their funds.
        // @audit-issue - If we delete it, the vault becomes orphaned and users won't know where to properly withdraw, contradicting the docs.
        // @audit-issue - RECOMMENDED MITIGATION: Only set the vault as Not active, but do not reset the mapping to `address(0)`.
        s_guardians[msg.sender][token] = IVaultShares(address(0));
        emit GaurdianRemoved(msg.sender, token);
        tokenVault.setNotActive();
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - Guardian cannot quit because `VaultGuardians` calls `redeem()` on behalf of the guardian without allowance.
        // @audit-issue - When `VaultGuardians` calls `tokenVault.redeem()`, `msg.sender` is `VaultGuardians`, but `owner` is the guardian.
        // @audit-issue - ERC4626 requires allowance when `msg.sender != owner`, causing `ERC20InsufficientAllowance` revert.
        // @audit-issue - This blocks the guardian from withdrawing their stake and closing the vault.
        // @audit-issue - PoC: `GuardianForkFuzzTest::testFuzz_quitGuardian()`.
        // @audit-issue - RECOMMENDED MITIGATION: Add a bypass in `VaultShares.redeem()` when `VaultGuardians` redeems for the guardian:
        // @audit-issue - `if (msg.sender == i_vaultGuardians && owner == i_guardian) { /* bypass allowance */ }`
        // @audit-issue - TRADE-OFFS CONSIDERED:
        // @audit-issue - 1. Auto-approve in `deposit()`: Rejected because infinite allowances are a known attack vector.
        // @audit-issue - 2. Separate function `redeemForGuardian()`: More invasive, requires interface changes.
        // @audit-issue - 3. Two transactions (`quit` + manual `redeem`): Poor UX.
        // @audit-issue - The bypass solution is preferred because it has no persistent state, requires double validation, and is controlled by the guardian.
        uint256 maxRedeemable = tokenVault.maxRedeem(msg.sender);
        uint256 numberOfAssetsReturned = tokenVault.redeem(maxRedeemable, msg.sender, msg.sender);
        return numberOfAssetsReturned;
    }

    /**
     * @notice Checks if the vault guardian is owner of vaults other than WETH vaults
     * @param guardian the vault guardian
     */
    function _guardianHasNonWethVaults(address guardian) private view returns (bool) {
        if (address(s_guardians[guardian][i_tokenOne]) != address(0)) {
            return true;
        } else {
            return address(s_guardians[guardian][i_tokenTwo]) != address(0);
        }
    }

    // slither-disable-start reentrancy-eth
    /*
     * @notice allows a user to become a guardian
     * @notice guardians are given a VaultGuardianToken as payment
     * @param token the token that the guardian will be guarding
     * @param tokenVault the vault that the guardian will be guarding
     */
    // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
    // @audit-issue - The `GUARDIAN_FEE` in ETH is not received by the contract at any point.
    // @audit-issue - RECOMMENDED MITIGATION: Mark the function as `payable`, transfer the ETH to the contract and check if the amount is correct.
    // @audit-answered-question - What happens if someone calls in a loop to this function with the same token/vault?
    // @audit-answer - Users can call the public wrapper functions repeatedly. This overwrites the vault in the registry (orphaning the old one) AND allows infinite minting of VGT (See Governance Inflation Issue below).
    // @audit-info - Incompatible with Fee-On-Transfer tokens.
    // @audit-info - If a token with transfer fees is used, `quitGuardian` will fail because the contract
    // @audit-info - receives less than `s_guardianStakePrice` but tries to transfer back the full amount.
    // @audit-info - Ensure only standard ERC20s (WETH, USDC, LINK) are whitelisted.
    function _becomeTokenGuardian(IERC20 token, VaultShares tokenVault) private returns (address) {
        // @audit-info - Missing address zero check
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: MEDIUM
        // @audit-issue - Missing check to see if the guardian is already guarding this token, in affirmative case the vault will be replaced and the funds will be locked.
        // @audit-issue - RECOMMENDED MITIGATION: Check if the guardian is already guarding this token
        s_guardians[msg.sender][token] = IVaultShares(address(tokenVault));
        emit GuardianAdded(msg.sender, token);
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: MEDIUM
        // @audit-issue - Governance Inflation: Calling public wrapper functions in a loop allows infinite minting of VGT.
        // @audit-issue - The user can recover their stake by calling `redeem` directly on the orphaned vault (bypassing registry).
        // @audit-issue - PoC: VaultGuardiansTest::test_exploitInfiniteGovernanceMinting
        // @audit-issue - RECOMMENDED MITIGATION: Implement `burn` in VaultGuardianToken and burn VGT in `quitGuardian`, AND prevent overwriting active vaults.
        i_vgToken.mint(msg.sender, s_guardianStakePrice);
        // @audit-note - The Guardian send the deposit tokens to this contract
        token.safeTransferFrom(msg.sender, address(this), s_guardianStakePrice);
        // @audit-issue - MEDIUM -> IMPACT: MEDIUM - LIKELIHOOD: LOW
        // @audit-issue - Weird ERC20 could have weird returns
        // @audit-issue - RECOMMENDED MITIGATION: Use forceApprove from safeERC20 library
        // @audit-note - The deposit tokens are approved and deposite into the vault
        bool succ = token.approve(address(tokenVault), s_guardianStakePrice);
        if (!succ) {
            revert VaultGuardiansBase__TransferFailed();
        }
        uint256 shares = tokenVault.deposit(s_guardianStakePrice, msg.sender);
        // @audit-info - The shares must be always equal to the deposit amount, so it's better to use
        // @audit-info - `if (shares != s_guardianStakePrice) revert VaultGuardiansBase__TransferFailed();`
        // @audit-info - In this way we are sure that it's the first deposit and there is no an ERC4626 inflation attack.
        if (shares == 0) {
            revert VaultGuardiansBase__TransferFailed();
        }
        return address(tokenVault);
    }
    // slither-disable-end reentrancy-eth

    // @audit-info - Section without any content
    /*//////////////////////////////////////////////////////////////
                   INTERNAL AND PRIVATE VIEW AND PURE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Gets the vault for a given vault guardian and a given asset token
     * @param guardian the vault guardian
     * @param token the vault's underlying asset token
     */
    function getVaultFromGuardianAndToken(address guardian, IERC20 token) external view returns (IVaultShares) {
        return s_guardians[guardian][token];
    }

    /**
     * @notice Checks if the given token is supported by the protocol
     * @param token the token to check for
     */
    function isApprovedToken(address token) external view returns (bool) {
        return s_isApprovedToken[token];
    }

    /**
     * @return Address of the Aave pool
     */
    function getAavePool() external view returns (address) {
        return i_aavePool;
    }

    /**
     * @return Address of the Uniswap v2 router
     */
    function getUniswapV2Router() external view returns (address) {
        return i_uniswapV2Router;
    }

    /**
     * @return Retrieves the stake price that users have to stake to become vault guardians
     */
    function getGuardianStakePrice() external view returns (uint256) {
        return s_guardianStakePrice;
    }

    /**
     * @return The ratio of the amount in vaults that goes to the vault guardians and the DAO
     */
    function getGuardianAndDaoCut() external view returns (uint256) {
        return s_guardianAndDaoCut;
    }
}

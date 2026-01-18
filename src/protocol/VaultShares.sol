// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IVaultShares, IERC4626} from "../interfaces/IVaultShares.sol";
import {AaveAdapter, IPool} from "./investableUniverseAdapters/AaveAdapter.sol";
import {UniswapAdapter} from "./investableUniverseAdapters/UniswapAdapter.sol";
import {DataTypes} from "../vendor/DataTypes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// @audit-answered-question - Is ReentrancyGuard well positioned at the far right of inheritance?
// @audit-answer - Yes, the crucial part is using the nonReentrant modifier before other checks in functions.
contract VaultShares is ERC4626, IVaultShares, AaveAdapter, UniswapAdapter, ReentrancyGuard {
    error VaultShares__DepositMoreThanMax(uint256 amount, uint256 max);
    error VaultShares__NotGuardian();
    error VaultShares__NotVaultGuardianContract();
    error VaultShares__AllocationNot100Percent(uint256 totalAllocation);
    error VaultShares__NotActive();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 internal immutable i_uniswapLiquidityToken;
    IERC20 internal immutable i_aaveAToken;
    // @audit-note - i_guardian is the guardian of the vault
    address private immutable i_guardian;
    // @audit-note - i_vaultGuardians is the contract that manages the guardians
    address private immutable i_vaultGuardians;
    // @audit-note - i_guardianAndDaoCut is the percentage of the cut that goes to the guardian and the DAO
    uint256 private immutable i_guardianAndDaoCut;
    // @audit-note - s_isActive is a boolean that indicates if the vault is active
    bool private s_isActive;

    AllocationData private s_allocationData;
    
    uint256 private constant ALLOCATION_PRECISION = 1_000;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event UpdatedAllocation(AllocationData allocationData);
    event NoLongerActive();
    event FundsInvested();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    // @audit-info - GAS - Consider wrap modifiers logic inside internal functions to reduce code size
    modifier onlyGuardian() {
        if (msg.sender != i_guardian) {
            revert VaultShares__NotGuardian();
        }
        _;
    }

    // @audit-info - GAS - Consider wrap modifiers logic inside internal functions to reduce code size
    modifier onlyVaultGuardians() {
        if (msg.sender != i_vaultGuardians) {
            revert VaultShares__NotVaultGuardianContract();
        }
        _;
    }

    // @audit-info - GAS - Consider wrap modifiers logic inside internal functions to reduce code size
    modifier isActive() {
        if (!s_isActive) {
            revert VaultShares__NotActive();
        }
        _;
    }

    // slither-disable-start reentrancy-eth
    /**
     * @notice removes all supplied liquidity from Uniswap and supplied lending amount from Aave and then re-invests it back into them only if the vault is active
     */
     // @audit-info - Modifiers should be used to data validation, access control and other non-business logic. Use them as business logic is a bad practice than can conduct to reentrancy attacks and other unexpected behavior.
     // @audit-info - RECOMMENDED MITIGATION: Uses independent internal functions for divest and invest actions.
     // @audit-answered-question - Could this modifier have a reentrancy issue?
     // @audit-answer - Yes, because it depends on the order of modifiers in the function.
     // @audit-issue - MEDIUM -> IMPACT: LOW/MEDIUM - LIKELIHOOD: HIGH
     // @audit-issue - This design is inefficient. Divesting and investing everything on every `deposit`/`withdraw`/`redeem` is expensive in gas terms and could lead to sandwich attacks if the vault manages a large amount of funds.
     // @audit-issue - In addition, integration with other protocols will fail because `totalAssets()` will return only the assets held in the vault, not the total amount including invested funds.
     // @audit-issue - RECOMMENDED MITIGATION: Implement active accounting for `totalAssets` and partial divest/invest actions.
    modifier divestThenInvest() {
        uint256 uniswapLiquidityTokensBalance = i_uniswapLiquidityToken.balanceOf(address(this));
        uint256 aaveAtokensBalance = i_aaveAToken.balanceOf(address(this));

        // Divest
        if (uniswapLiquidityTokensBalance > 0) {
        // @audit-answered-question - Is necessary this returned value?
        // @audit-answer - No, not for bussiness logic but yes for an event
        // @audit-info - Missing return value, that could be used for an event
            _uniswapDivest(IERC20(asset()), uniswapLiquidityTokensBalance);
        }
        if (aaveAtokensBalance > 0) {
        // @audit-answered-question - Is necessary this returned value?
        // @audit-answer - No, not for bussiness logic but yes for an event
        // @audit-info - Missing return value, that could be used for an event
            _aaveDivest(IERC20(asset()), aaveAtokensBalance);
        }

        _;

        // Reinvest
        if (s_isActive) {
            // @audit-note - This function invests all underlying token that the contract has
            _investFunds(IERC20(asset()).balanceOf(address(this)));
        }
        // @audit-info - Missing event for this divestThenInvest action
    }
    // slither-disable-end reentrancy-eth

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // We use a struct to avoid stack too deep errors. Thanks Solidity
    // @audit-info - Missing constructor NatSpec documentation
    // @audit-note - Asset is the underlying token of the vault
    // @audit-note - Vault name is the name of the vault
    // @audit-note - Vault symbol is the symbol of the vault
    // @audit-note - Aave pool is the Aave pool of the vault
    // @audit-note - Uniswap router is the Uniswap router of the vault
    // @audit-note - WETH is the WETH token of the vault
    // @audit-note - USDC is the USDC token of the vault
    // @audit-note - Guardian is the guardian of the vault
    // @audit-note - Guardian and DAO cut is the percentage of the cut that goes to the guardian and the DAO
    // @audit-note - Vault guardians is the contract that manages the guardians
    // @audit-answered-question - What tokens can be used as underlying token?
    // @audit-answer - WETH,USDC and LINK.
    // @audit-answered-question - Is is protected in any way?
    // @audit-answer - Yes, It's protected at VaultGuardiansBase::becomeGuardian() and VaultGuardiansBase::becomeTokenGuardian()
    constructor(ConstructorData memory constructorData)
        ERC4626(constructorData.asset)
        ERC20(constructorData.vaultName, constructorData.vaultSymbol)
        AaveAdapter(constructorData.aavePool)
        UniswapAdapter(constructorData.uniswapRouter, constructorData.weth, constructorData.usdc)
    {
        i_guardian = constructorData.guardian;
        i_guardianAndDaoCut = constructorData.guardianAndDaoCut;
        i_vaultGuardians = constructorData.vaultGuardians;
        s_isActive = true;
        updateHoldingAllocation(constructorData.allocationData);

        // External calls
        // @audit-note - Get aToken and LP addresses for this underlying token from Aave and Uniswap
        i_aaveAToken =
            IERC20(IPool(constructorData.aavePool).getReserveData(address(constructorData.asset)).aTokenAddress);
        i_uniswapLiquidityToken = IERC20(i_uniswapFactory.getPair(address(constructorData.asset), address(i_weth)));
        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - When asset is WETH, this calls `getPair(WETH, WETH)` which returns `address(0)`.
        // @audit-issue - The modifier `divestThenInvest` calls `balanceOf` on `address(0)`, causing revert.
        // @audit-issue - This breaks `quitGuardian`, `redeem`, `withdraw`, and `deposit` for WETH vaults.
        // @audit-issue - PoC: `GuardianForkFuzzTest::testFuzz_quitGuardian()` on mainnet fork.
        // @audit-issue - RECOMMENDED MITIGATION: Use USDC as counterparty when asset is WETH:
        // @audit-issue - `address pairToken = address(constructorData.asset) == address(i_weth) ? address(i_tokenOne) : address(i_weth);`
        // @audit-issue - FIX: When asset is WETH, pair with USDC (`i_tokenOne`). Otherwise pair with WETH.

        // @audit-note - Added on audit for testing purposes - UNCOMMENT TO FIX TESTS
        // @audit-note - address pairToken = address(constructorData.asset) == address(i_weth) 
        // @audit-note -     ? address(i_tokenOne) 
        // @audit-note -     : address(i_weth);
        // @audit-note - i_uniswapLiquidityToken = IERC20(i_uniswapFactory.getPair(address(constructorData.asset), pairToken));
    }
    
    /**
     * @notice Sets the vault as not active, which means that the vault guardian has quit
     * @notice Users will not be able to invest in this vault, however, they will be able to withdraw their deposited assets
     */
    // @audit-info - GAS - This function could me marked as external
    function setNotActive() public onlyVaultGuardians isActive {
        s_isActive = false;
        emit NoLongerActive();
    }

    /**
     * @notice Allows Vault Guardians to update their allocation ratio (and thus, their strategy of investment)
     * @param tokenAllocationData The new allocation data
     */
    function updateHoldingAllocation(AllocationData memory tokenAllocationData) public onlyVaultGuardians isActive {
        uint256 totalAllocation = tokenAllocationData.holdAllocation + tokenAllocationData.uniswapAllocation
            + tokenAllocationData.aaveAllocation;
        if (totalAllocation != ALLOCATION_PRECISION) {
            revert VaultShares__AllocationNot100Percent(totalAllocation);
        }
        s_allocationData = tokenAllocationData;
        emit UpdatedAllocation(tokenAllocationData);
        // @audit-issue - MEDIUM -> IMPACT: LOW/MEDIUM - LIKELIHOOD: HIGH
        // @audit-issue - Updating allocation data without rebalancing creates a discrepancy between the intended strategy and the actual location of funds.
        // @audit-issue - RECOMMENDED MITIGATION: Call `rebalanceFunds()` automatically (or based in a boolean parameter) or clearly document that rebalancing is "lazy" and must be triggered manually/by user interaction.
    }

    /**
     * @dev See {IERC4626-deposit}. Overrides the Openzeppelin implementation.
     *
     * @notice Mints shares to the DAO and the guardian as a fee
     */
    // slither-disable-start reentrancy-eth
    // @audit-info - The nonReentrant modifier should occur before all other modifiers, This is a best-practice to protect against reentrancy in other modifiers.
    // @audit-info - GAS - This function could me marked as external
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        isActive
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) {
            revert VaultShares__DepositMoreThanMax(assets, maxDeposit(receiver));
        }

        uint256 shares = previewDeposit(assets);
        // @audit-info - There is no a reentrancy issue here because it is using the nonReentrant modifier, but it's always recommended to execute the effects (mints) before the external calls (trasferFrom inside _deposit()).
        _deposit(_msgSender(), receiver, assets, shares);

        // @audit-issue - HIGH - IMPACT: MEDIUM - LIKELIHOOD: HIGH
        // @audit-issue - The minting of shares to the guardian and the DAO are inflating the total supply of the vault, they should be deducted from the shares to be minted to avoid dilution. After a user deposit of 100 assets, the vault will mint 100% of previewed shares to the user, but it will also mint (`shares / i_guardianAndDaoCut`) to the guardian and (`shares / i_guardianAndDaoCut`) to the DAO.
        // @audit-issue - PoC: `VaultSharesTest::testSharesDilutionOnDeposit()`.
        // @audit-issue - RECOMMENDED MITIGATION: Deducting the guardian's and the DAO's shares from the total shares to be minted.

        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - MISSING OVERRIDE OF `mint()`: The `mint()` function from ERC4626 is not overridden and lacks the `divestThenInvest` modifier.
        // @audit-issue - An attacker can call `mint()` when funds are invested (`totalAssets()` ~ 0).
        // @audit-issue - Due to broken accounting, `previewMint()` calculates 0 assets required for new shares.
        // @audit-issue - Attacker mints shares for free, then calls `redeem()` (which pulls funds) to drain the vault.
        // @audit-issue - PoC: `VaultGuardiansTest::test_exploitMintTheft()`.
        // @audit-issue - RECOMMENDED MITIGATION: Override `mint()` and apply `divestThenInvest`, or fix internal accounting.
        _mint(i_guardian, shares / i_guardianAndDaoCut);
        _mint(i_vaultGuardians, shares / i_guardianAndDaoCut);

        // @audit-issue - LOW -> IMPACT: LOW - LIKELIHOOD: HIGH
        // @audit-issue - Missing deposit event

        _investFunds(assets);
        return shares;
    }

    /**
     * @notice Invests user deposited assets into the investable universe (hold, Uniswap, or Aave) based on the allocation data set by the vault guardian
     * @param assets The amount of assets to invest
     */
    function _investFunds(uint256 assets) private {
        uint256 uniswapAllocation = (assets * s_allocationData.uniswapAllocation) / ALLOCATION_PRECISION;
        uint256 aaveAllocation = (assets * s_allocationData.aaveAllocation) / ALLOCATION_PRECISION;

        emit FundsInvested();

        // @audit-issue - HIGH -> IMPACT: HIGH - LIKELIHOOD: HIGH
        // @audit-issue - Missing check for zero amount before calling adapters.
        // @audit-issue - When `uniswapAllocation=0` or `aaveAllocation=0`, the adapters are called with `amount=0`.
        // @audit-issue - Aave rejects `supply(0)` with error 26 (`INVALID_AMOUNT`).
        // @audit-issue - This breaks `becomeGuardian()` and `deposit()` for any allocation where one of them is 0.
        // @audit-issue - PoC: `GuardianForkFuzzTest::testFuzz_becomeGuardian()` on mainnet fork.
        // @audit-issue - RECOMMENDED MITIGATION: Add checks before calling adapters:
        // @audit-issue - `if (uniswapAllocation > 0) { _uniswapInvest(...); }`
        // @audit-issue - `if (aaveAllocation > 0) { _aaveInvest(...); }`

        _uniswapInvest(IERC20(asset()), uniswapAllocation);
        _aaveInvest(IERC20(asset()), aaveAllocation);

        // @audit-note - Added on audit for testing purposes - UNCOMMENT TO FIX TESTS
        // @audit-note - if (uniswapAllocation > 0) {
        // @audit-note -     _uniswapInvest(IERC20(asset()), uniswapAllocation);
        // @audit-note - }
        // @audit-note - if (aaveAllocation > 0) {
        // @audit-note -     _aaveInvest(IERC20(asset()), aaveAllocation);
        // @audit-note - }
    }

    // slither-disable-start reentrancy-benign
    /* 
     * @notice Unintelligently just withdraws everything, and then reinvests it all. 
     * @notice Anyone can call this and pay the gas costs to rebalance the portfolio at any time. 
     * @dev We understand that this is horrible for gas costs. 
     */
     // @audit-issue - LOW - IMPACT: MEDIUM/LOW - LIKELIHOOD: LOW
     // @audit-issue - The `nonReentrant` `modifier` should occur before all other modifiers, This is a best-practice to protect against reentrancy in other modifiers.
     // @audit-info - Empty blocks is a bad practice
     // @audit-info - GAS - This function could me marked as external
    function rebalanceFunds() public isActive divestThenInvest nonReentrant {}

    /**
     * @dev See {IERC4626-withdraw}.
     *
     * We first divest our assets so we get a good idea of how many assets we hold.
     * Then, we redeem for the user, and automatically reinvest.
     */
     // @audit-issue - LOW - IMPACT: MEDIUM/LOW - LIKELIHOOD: LOW
     // @audit-issue - The `nonReentrant` `modifier` should occur before all other modifiers, This is a best-practice to protect against reentrancy in other modifiers.
     // @audit-info - GAS - This function could me marked as external
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(IERC4626, ERC4626)
        divestThenInvest
        nonReentrant
        returns (uint256)
    {
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }

    /**
     * @dev See {IERC4626-redeem}.
     *
     * We first divest our assets so we get a good idea of how many assets we hold.
     * Then, we redeem for the user, and automatically reinvest.
     */
     // @audit-issue - LOW - IMPACT: MEDIUM/LOW - LIKELIHOOD: LOW
     // @audit-issue - The `nonReentrant` `modifier` should occur before all other modifiers, This is a best-practice to protect against reentrancy in other modifiers.
     // @audit-info - GAS - This function could me marked as external
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(IERC4626, ERC4626)
        divestThenInvest
        nonReentrant
        returns (uint256)
    {
        // @audit-note - Fix for 'Guardian cannot quit because VaultGuardians calls redeem on behalf of the guardian without allowance.' issue.
        // @audit-note - If VaultGuardians is redeeming on behalf of the guardian, bypass allowance check - UNCOMMENT TO FIX TESTS
        // @audit-note - if (msg.sender == i_vaultGuardians && owner == i_guardian) {
        // @audit-note -     uint256 guardianAssets = previewRedeem(shares);
        // @audit-note -     _burn(owner, shares);
        // @audit-note -     IERC20(asset()).transfer(receiver, guardianAssets);
        // @audit-note -     emit Withdraw(msg.sender, receiver, owner, guardianAssets, shares);
        // @audit-note -     return guardianAssets;
        // @audit-note - }
        
        uint256 assets = super.redeem(shares, receiver, owner);
        return assets;
    }
    // slither-disable-end reentrancy-eth
    // slither-disable-end reentrancy-benign

    /*//////////////////////////////////////////////////////////////
                             VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    /**
     * @return The guardian of the vault
     */
    function getGuardian() external view returns (address) {
        return i_guardian;
    }

    /**
     * @return The ratio of the amount in vaults that goes to the vault guardians and the DAO
     */
    function getGuardianAndDaoCut() external view returns (uint256) {
        return i_guardianAndDaoCut;
    }

    /**
     * @return Gets the address of the Vault Guardians protocol
     */
    function getVaultGuardians() external view returns (address) {
        return i_vaultGuardians;
    }

    /**
     * @return A bool indicating if the vault is active (has an active vault guardian and is accepting deposits) or not
     */
    function getIsActive() external view returns (bool) {
        return s_isActive;
    }

    /**
     * @return The Aave aToken for the vault's underlying asset
     */
    function getAaveAToken() external view returns (address) {
        return address(i_aaveAToken);
    }

    /**
     * @return Uniswap's LP token
     */
    /**
     * @return Uniswap's LP token
     */
    // @audit-info - Typo in function name: getUniswapLiquidtyToken -> getUniswapLiquidityToken
    function getUniswapLiquidtyToken() external view returns (address) {
        return address(i_uniswapLiquidityToken);
    }

    /**
     * @return The allocation data set by the vault guardian
     */
    function getAllocationData() external view returns (AllocationData memory) {
        return s_allocationData;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVaultData {
    /**
     * @notice The ratio of vault's underlying asset tokens to invest is set by the vault guardian and is stored in this struct
     * @notice holdAllocation is the ratio of tokens to hold in the vault. This is not invested in Uniswap v2 or Aave v3
     * @notice uniswapAllocation is the ratio of tokens to add as liquidity in Uniswap v2
     * @notice aaveAllocation is the ratio of tokens to provide as lending amount in Aave v3
     */
     // @audit-answered-question - How is ratio stored or calculated?
     // @audit-answer - The ratio is stored as a percentage, the sum of all ratios should be 100% -> 1000
     // @audit-note - This is the "investable universe"
    struct AllocationData {
        uint256 holdAllocation; // hodl
        uint256 uniswapAllocation; // Simmilar to T-Swap
        uint256 aaveAllocation; // Similar to Thunder Loan
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {IERC20} from "../../../src/protocol/VaultGuardians.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title VaultGuardiansFuzzTest
 * @notice Fuzz tests for VaultGuardians that don't require real Uniswap/Aave.
 * @notice Tests that interact with protocols are in GuardianForkFuzzTest.
 */
contract VaultGuardiansFuzzTest is Base_Test {
    event OwnershipTransferred(address oldOwner, address newOwner);

    address public user;

    function setUp() public override {
        Base_Test.setUp();
        user = makeAddr("user");
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz: Ownership transfer.
     * Tests that ownership can be transferred to any non-zero address.
     */
    function testFuzz_transferOwner(address newOwner) public {
        vm.assume(newOwner != address(0));

        vm.startPrank(vaultGuardians.owner());
        vaultGuardians.transferOwnership(newOwner);
        vm.stopPrank();

        assertEq(vaultGuardians.owner(), newOwner);
    }

    /**
     * @notice Fuzz: Stake price update.
     * Tests that owner can set any stake price value.
     */
    function testFuzz_updateGuardianStakePrice(uint256 newStakePrice) public {
        vm.prank(vaultGuardians.owner());
        vaultGuardians.updateGuardianStakePrice(newStakePrice);

        assertEq(vaultGuardians.getGuardianStakePrice(), newStakePrice);
    }

    /**
     * @notice Fuzz: DAO cut update.
     * Tests that owner can set any cut value.
     * Note: Zero cut causes division by zero - separate issue.
     */
    function testFuzz_updateGuardianAndDaoCut(uint256 newCut) public {
        vm.prank(vaultGuardians.owner());
        vaultGuardians.updateGuardianAndDaoCut(newCut);

        assertEq(vaultGuardians.getGuardianAndDaoCut(), newCut);
    }

    /**
     * @notice Fuzz: Token sweep.
     * Tests that owner can recover any ERC20 tokens sent to the contract.
     */
    function testFuzz_sweepErc20s(uint256 amount, uint256 seed) public {
        IERC20 token = _getToken(seed);
        deal(address(token), address(vaultGuardians), amount);
        vm.prank(vaultGuardians.owner());
        vaultGuardians.sweepErc20s(token);
        assertEq(token.balanceOf(address(vaultGuardians)), 0);
        assertEq(token.balanceOf(vaultGuardians.owner()), amount);
    }

    /**
     * @notice Fuzz: Invalid allocation rejection.
     * Tests that allocations summing to more than 1000 revert.
     * Should revert with VaultShares__AllocationNot100Percent error.
     */
    function testFuzz_becomeGuardianInvalidAllocation(uint256 seed1, uint256 seed2) public {
        AllocationData memory allocationData = _getInvalidTokenAllocation(seed1, seed2);
        uint256 totalAllocation = allocationData.holdAllocation + allocationData.uniswapAllocation + allocationData.aaveAllocation;

        vm.startPrank(user);
        weth.approve(address(vaultGuardians), vaultGuardians.getGuardianStakePrice());
        
        vm.expectRevert(abi.encodeWithSelector(VaultShares.VaultShares__AllocationNot100Percent.selector, totalAllocation));
        vaultGuardians.becomeGuardian(allocationData);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz: Become token guardian (non-WETH).
     * Tests becoming a guardian for a non-WETH token (USDC, LINK) after initial WETH registration.
     */
    function testFuzz_becomeTokenGuardian(uint256 seed1, uint256 seed2, uint256 tokenSeed) public {
        AllocationData memory allocationData = _getTokenAllocation(seed1, seed2);
        
        // Use a valid token (non-WETH ideally to test becomeTokenGuardian)
        // Choice 1: USDC
        // Choice 2: LINK
        uint256 choice = bound(tokenSeed, 1, 2);
        IERC20 token = (choice == 1) ? usdc : link;
        
        uint256 stakePrice = vaultGuardians.getGuardianStakePrice();
        
        // 1. First become WETH guardian
        deal(address(weth), user, stakePrice);
        vm.startPrank(user);
        weth.approve(address(vaultGuardians), stakePrice);
        vaultGuardians.becomeGuardian(allocationData);
        
        // 2. Become Token Guardian
        // Deal enough token (deal handles large amounts in mocks)
        deal(address(token), user, stakePrice);
        token.approve(address(vaultGuardians), stakePrice);
        
        address vaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, token);
        vm.stopPrank();
        
        VaultShares vault = VaultShares(vaultAddress);
        assertEq(vault.getGuardian(), user);
        assertEq(vault.asset(), address(token));
        assertEq(vault.getIsActive(), true);
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getToken(uint256 seed) internal view returns (IERC20) {
        uint256 choice = bound(seed, 0, 2);
        if (choice == 0) return weth;
        if (choice == 1) return usdc;
        return link;
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

    function _getInvalidTokenAllocation(uint256 seed1, uint256 seed2) internal view returns (AllocationData memory) {
        AllocationData memory data = _getTokenAllocation(seed1, seed2);
        // Increment total sum by at least 1 to 1000
        uint256 extra = bound(seed1, 1, 1000);
        uint256 choice = seed2 % 3;

        if (choice == 0) data.holdAllocation += extra;
        else if (choice == 1) data.uniswapAllocation += extra;
        else data.aaveAllocation += extra;
        
        return data;
    }
}

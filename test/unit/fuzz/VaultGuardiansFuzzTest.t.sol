// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
// @audit-info - Unused imports should be removed
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
// @audit-info - Unused imports should be removed
import {IERC20} from "../../../src/protocol/VaultGuardians.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
// @audit-info - Unused imports should be removed
import {VaultGuardiansBase} from "../../../src/protocol/VaultGuardiansBase.sol";

contract VaultGuardiansFuzzTest is Base_Test {
    event OwnershipTransferred(address oldOwner, address newOwner);

    function setUp() public override {
        Base_Test.setUp();
    }

    function testFuzz_transferOwner(address newOwner) public {
        vm.assume(newOwner != address(0));

        vm.startPrank(vaultGuardians.owner());
        vaultGuardians.transferOwnership(newOwner);
        vm.stopPrank();

        assertEq(vaultGuardians.owner(), newOwner);
    }
}

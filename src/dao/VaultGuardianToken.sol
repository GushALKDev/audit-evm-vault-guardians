// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
 
contract VaultGuardianToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    constructor() ERC20("VaultGuardianToken", "VGT") ERC20Permit("VaultGuardianToken") Ownable(msg.sender) {}

    // The following functions are overrides required by Solidity.
    // @audit-answered-question - Is this necessary?
    // @audit-answer - Yes, it is required by Solidity to resolve inheritance conflict between ERC20 and ERC20Votes overrides.
    // @audit-answered-question - Should it be protected by onlyOwner?
    // @audit-answer - No. _update is internal and called on every transfer/mint/burn.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    // @audit-info - GAS - This function could me marked as external
    function nonces(address ownerOfNonce) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(ownerOfNonce);
    }

    // @audit-info - Centralization issue, a compromised owner can mint tokens
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

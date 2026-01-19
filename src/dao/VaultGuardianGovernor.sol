// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes, IVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

contract VaultGuardianGovernor is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    constructor(IVotes _voteToken)
        Governor("VaultGuardianGovernor")
        GovernorVotes(_voteToken)
        GovernorVotesQuorumFraction(4)
    {}
    // @audit-issue-written - MEDIUM -> IMPACT: LOW - LIKELIHOOD: HIGH
    // @audit-issue-written - `votingDelay()` and `votingPeriod()` return seconds, but OpenZeppelin Governor expects blocks.
    // @audit-issue-written - `1 days` (86400) is interpreted as 86,400 blocks (~12 days at 12s/block) instead of 1 day.
    // @audit-issue-written - `7 days` (604800) is interpreted as 604,800 blocks (~84 days) instead of 7 days.
    // @audit-issue-written - RECOMMENDED MITIGATION: Use block counts: `7200` for 1 day delay, `50400` for 7 days period.
    // @audit-info - GAS - This function could me marked as external
    function votingDelay() public pure override returns (uint256) {
        return 1 days;
    }

    // @audit-info - GAS - This function could me marked as external
    function votingPeriod() public pure override returns (uint256) {
        return 7 days;
    }

    // The following functions are overrides required by Solidity.

    // @audit-info - GAS - This function could me marked as external
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }
}

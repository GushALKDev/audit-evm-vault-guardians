// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VaultGuardianToken} from "../../../src/dao/VaultGuardianToken.sol";
import {VaultGuardianGovernor} from "../../../src/dao/VaultGuardianGovernor.sol";

contract DaoIntegrationTest is Test {
    VaultGuardianToken token;
    VaultGuardianGovernor governor;
    
    address user = makeAddr("user");
    // This address simulates the VaultGuardians contract which owns the token
    address guardianRegistry = makeAddr("guardianRegistry");

    function setUp() public {
        vm.startPrank(guardianRegistry); 
        token = new VaultGuardianToken();
        governor = new VaultGuardianGovernor(token);
        vm.stopPrank();
    }

    /**
     * @notice test for the DAO governance cycle: Mint -> Delegate -> Propose -> Vote -> Execute
     */
    function test_daoGovernanceCycle() public {
        // Mint tokens to user (simulating earning them as a guardian)
        vm.prank(guardianRegistry);
        token.mint(user, 100e18);

        // User delegates votes to themselves to activate voting power
        vm.prank(user);
        token.delegate(user);
        
        // Check voting power matches balance
        assertEq(token.getVotes(user), 100e18);

        // Create Proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);

        // Call a harmless view function to ensure execution succeeds
        calldatas[0] = abi.encodeWithSignature("totalSupply()"); 
        string memory description = "Proposal #1: Test Proposal";

        vm.prank(user);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Advance Voting Delay (1 day) to turn proposal Active
        vm.roll(block.number + governor.votingDelay() + 1);
        
        // Check state is Active (1)
        assertEq(uint256(governor.state(proposalId)), 1); 

        // Vote (1 = For)
        vm.prank(user);
        governor.castVote(proposalId, 1);

        // Advance Voting Period (7 days) for voting to end
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check state is Succeeded (4)
        // Pending=0, Active=1, Canceled=2, Defeated=3, Succeeded=4
        assertEq(uint256(governor.state(proposalId)), 4);
        
        // If we wanted to test execution, we would need to queue (if Timelock) and execute.
        // Since no Timelock, we could execute directly.
        // But our target was dummy (empty call to token), so execution is trivial.
        
        description = "Proposal #1: Test Proposal";
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.execute(targets, values, calldatas, descriptionHash);
        
        // State should be Executed (7)
        assertEq(uint256(governor.state(proposalId)), 7);
    }
}

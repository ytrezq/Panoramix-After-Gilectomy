// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Setup } from "test/utils/Setup.sol";
import { IMajorityVoting } from "src/interfaces/yb/IYBTokenVoting.sol";
import { Action } from "src/interfaces/yb/IYBTokenVoting.sol";

contract OperatorDaoVotingTest is Setup {
    address public daoVoter = address(0x3);
    address public user = address(0x5);

    event DaoVoterUpdated(address indexed voter, bool isVoter);

    function setUp() public override {
        super.setUp();
        vm.prank(operator.owner());
        operator.authorizeDaoVoter(daoVoter, true);
        assertGt(getPastVotingPower(block.timestamp), 0, "Voting power is 0");
        increaseLock(address(locker), 1_000_000e18);
    }

    // ============================================
    // Create DAO Proposal Tests
    // ============================================

    function test_CreateDaoProposalViaOperatorWithPermission() public {
        grantCreateProposalPermission();
        assertTrue(hasProposalPermissions(), "Permissions not granted");

        bytes memory metadata = bytes("Test Proposal");
        Action[] memory actions = new Action[](0);
        uint64 startDate = uint64(block.timestamp + 10);
        uint64 endDate = uint64(block.timestamp + 7 days + 10);
        bytes memory data = "";

        vm.prank(daoVoter);
        operator.createDaoProposal(metadata, actions, startDate, endDate, data);
    }

    function test_CreateDaoProposalRevertsWhenNotAuthorized() public {
        vm.expectRevert("!dao voter");
        vm.prank(user);
        operator.createDaoProposal(bytes("Test Proposal"), new Action[](0), uint64(block.timestamp), uint64(block.timestamp + 7 days), bytes(""));
    }

    // ============================================
    // Cast DAO Vote Tests
    // ============================================

    function test_CastDaoVote() public {
        uint256 proposalId = createDaoProposal();
        vm.prank(daoVoter);
        operator.castDaoVote(proposalId, 1);
    }

    function test_CastDaoVoteAllowsOwner() public {
        uint256 proposalId = createDaoProposal();
        operator.castDaoVote(proposalId, 2);
    }

    function test_CastDaoVoteRevertsWhenNotAuthorized() public {
        uint256 proposalId = createDaoProposal();
        vm.expectRevert("!dao voter");
        vm.prank(user);
        operator.castDaoVote(proposalId, 1);
    }

    // ============================================
    // Cast Split DAO Vote Tests
    // ============================================

    function test_CastSplitDaoVote() public {
        uint256 proposalId = createDaoProposal();
        IMajorityVoting.Tally memory votes =
            IMajorityVoting.Tally({abstain: 100, yes: 500, no: 200});

        vm.prank(daoVoter);
        operator.castSplitDaoVote(proposalId, votes);
    }

    function test_CastSplitDaoVoteAllowsOwner() public {
        uint256 proposalId = createDaoProposal();
        IMajorityVoting.Tally memory votes =
            IMajorityVoting.Tally({abstain: 100, yes: 500, no: 200});

        operator.castSplitDaoVote(proposalId, votes);
    }

    function test_CastSplitDaoVoteRevertsWhenNotAuthorized() public {
        uint256 proposalId = createDaoProposal();
        IMajorityVoting.Tally memory votes =
            IMajorityVoting.Tally({abstain: 100, yes: 500, no: 200});

        vm.expectRevert("!dao voter");
        vm.prank(user);
        operator.castSplitDaoVote(proposalId, votes);
    }
}

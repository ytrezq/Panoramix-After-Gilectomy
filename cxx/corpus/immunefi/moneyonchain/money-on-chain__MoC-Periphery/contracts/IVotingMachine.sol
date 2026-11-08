// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

interface IVotingMachine {
    /**
        get current contract state
        */
    function getState() external view returns (uint256);

    /**
        return the current voting round
        */
    function getVotingRound() external view returns (uint256);

    /**
    Pre Vote a proposal

    @param _proposal Address of the change contract that will be executed if this vote is successful
    */
    function preVote(address _proposal) external;

    /**
    Vote a proposal

    @param _inFavorAgainst Type of vote
    */
    function vote(bool _inFavorAgainst) external;

    /**
    There is a veto Condition

    */
    function vetoCondition() external;

    /**
    Veto
    */
    function veto() external;

    function readyToPreVoteStep() external view returns (bool);

    /**
    preVoteStep
    */
    function preVoteStep() external;

    function readyToVoteStep() external view returns (bool);

    /**
    voteStep
    */
    function voteStep() external;

    /**
    vetoStep
    */
    function vetoStep() external;

    /**
    acceptedStep
    */
    function acceptedStep() external;

    /**
    Get the pre-voting registered proposal count.
    */
    function getProposalCount() external view returns (uint256);

    /**
    Get pre-voting proposal address and information by index

    @param _index Index of proposal to query.
    */
    function getProposalByIndex(
        uint256 _index
    )
        external
        view
        returns (
            address proposalAddress,
            uint256 proposalVotingRound,
            uint256 proposalVotes,
            uint256 proposalExpirationTimeStamp
        );

    /**
    Get voting data
    */
    function getVotingData()
        external
        view
        returns (address winnerProposal, uint256 inFavorVotes, uint256 againstVotes, uint256 votingExpirationTime);

    /**
        Get user vote
    */
    function getUserVote(address user) external view returns (address voteAddress, uint256 voteRound);

    /**
    will the call to unregister be successfull?

    @param _proposal Address of the change contract that will be executed if this vote is successful
    */
    function canUnregister(address _proposal) external view returns (bool);

    /**
    Unregister a proposal, free the assets it uses.

    @param _proposal Address of the change contract that will be executed if this vote is successful
    */
    function unregister(address _proposal) external;
}

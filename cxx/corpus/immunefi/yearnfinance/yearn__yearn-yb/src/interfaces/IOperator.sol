// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILocker} from "src/interfaces/ILocker.sol";
import {IYBVotingEscrow} from "src/interfaces/yb/IYBVotingEscrow.sol";
import {IMajorityVoting} from "src/interfaces/yb/IYBTokenVoting.sol";

interface IOperator {
    // =========================
    // Events
    // =========================

    event GaugeVoterUpdated(address indexed voter, bool isVoter);
    event DaoVoterUpdated(address indexed voter, bool isVoter);
    event LockerUpdated(address indexed locker, bool isLocker);

    // =========================
    // Immutable / View Getters
    // =========================

    /// @notice The underlying Locker contract.
    function locker() external view returns (ILocker);

    /// @notice The Yield Basis voting escrow contract.
    function escrow() external view returns (IYBVotingEscrow);

    /// @notice The underlying token used for locking/voting.
    function token() external view returns (address);

    /// @notice The GaugeController contract address.
    function gaugeController() external view returns (address);

    /// @notice The DAO voting (TokenVoting) contract address.
    function daoVoting() external view returns (address);

    /// @notice Returns the owner (proxied from the Locker).
    function owner() external view returns (address);

    /// @notice Whether an address is authorized as a gauge voter.
    function gaugeVoters(address account) external view returns (bool);

    /// @notice Whether an address is authorized as a DAO voter.
    function daoVoters(address account) external view returns (bool);

    /// @notice Whether an address is authorized as a locker manager.
    function lockers(address account) external view returns (bool);

    // =========================
    // Gauge Voting
    // =========================

    /// @notice Forward a gauge weight vote to the GaugeController.
    /// @param _gauges Gauge addresses.
    /// @param _weights Weights for each gauge.
    function voteForGaugeWeights(address[] calldata _gauges, uint256[] calldata _weights) external;

    // =========================
    // DAO Voting
    // =========================

    /// @notice Cast a simple (single-option) vote on a DAO proposal.
    /// @param _proposalId The proposal ID.
    /// @param _voteOption Encoded vote option.
    function castDaoVote(uint256 _proposalId, uint8 _voteOption) external;

    /// @notice Cast a split vote (tally-style) on a DAO proposal.
    /// @param _proposalId The proposal ID.
    /// @param _votes Tally struct with weighted allocations.
    function castSplitDaoVote(
        uint256 _proposalId,
        IMajorityVoting.Tally calldata _votes
    ) external;

    // =========================
    // Lock Management
    // =========================

    /// @notice Increase the lock for this proxy in the voting escrow.
    /// @param amount Amount to lock.
    function lock(uint256 amount) external;

    /// @notice Get remaining lock time for the underlying Locker’s position.
    function getLockTimeRemaining() external view returns (uint256);

    /// @notice Get the current voting power / locked balance associated with this proxy.
    function getVotes() external view returns (uint256);

    // =========================
    // Admin Setters
    // =========================

    /// @notice Set or unset an address as authorized gauge voter.
    function authorizeGaugeVoter(address _voter, bool _isVoter) external;

    /// @notice Set or unset an address as authorized DAO voter.
    function authorizeDaoVoter(address _voter, bool _isVoter) external;

    /// @notice Set or unset an address as authorized locker manager.
    function authorizeLocker(address _locker, bool _isLocker) external;

    /// @notice Callback for receiving ERC721 NFTs (veYB position transfers)
    function nftTransferCallback(address from, uint256 tokenId, address recipient) external;
}
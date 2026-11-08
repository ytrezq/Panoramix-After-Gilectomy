// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/// @title IMultisig
/// @author Aragon X - 2022-2024
/// @notice An interface for an on-chain multisig governance plugin in which a proposal passes
///         if X out of Y approvals are met.
/// @custom:security-contact sirt@aragon.org
interface IMultisig {
    /// @notice Adds new members to the address list. Previously, it checks if the new address
    ///         list length would be greater than `type(uint16).max`, the maximal number of approvals.
    /// @param _members The addresses of the members to be added.
    function addAddresses(address[] calldata _members) external;

    /// @notice Removes existing members from the address list. Previously, it checks if the
    ///         new address list length is at least as long as the minimum approvals parameter requires.
    ///         Note that `minApprovals` is must be at least 1 so the address list cannot become empty.
    /// @param _members The addresses of the members to be removed.
    function removeAddresses(address[] calldata _members) external;

    /// @notice Records an approval for a proposal and, if specified, attempts execution if certain conditions are met.
    /// @param _proposalId The ID of the proposal to approve.
    /// @param _tryExecution If `true`, attempts execution of the proposal after approval, without reverting on failure.
    function approve(uint256 _proposalId, bool _tryExecution) external;

    /// @notice Checks if an account is eligible to participate in a proposal vote.
    ///         Confirms that the proposal is open, the account is listed as a member,
    ///         and the account has not previously voted or approved this proposal.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The address of the account to check.
    /// @return True if the account is eligible to vote.
    function canApprove(uint256 _proposalId, address _account) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);

    /// @notice Returns whether the account has approved the proposal.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return The vote option cast by a voter for a certain proposal.
    function hasApproved(uint256 _proposalId, address _account) external view returns (bool);

    /// @notice Executes a proposal if all execution conditions are met.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;
}

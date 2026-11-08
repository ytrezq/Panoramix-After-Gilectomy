// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";

// solhint-disable-next-line max-line-length
import {Proposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/Proposal.sol";
import {Plugin} from "@aragon/osx-commons-contracts/src/plugin/Plugin.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/// @title Admin
/// @author Aragon X - 2022-2024
/// @notice The admin governance plugin giving execution permission on the DAO to a single address.
/// @dev v1.2 (Release 1, Build 2)
/// @custom:security-contact sirt@aragon.org
contract AdminZkSync is IMembership, Plugin, Proposal {
    using SafeCastUpgradeable for uint256;

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant ADMIN_INTERFACE_ID = this.executeProposal.selector;

    /// @notice The ID of the permission required to call the `executeProposal` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @dev Thrown if the `execute` function is called.
    error FunctionNotSupported();

    /// @notice Initializes the contract.
    /// @param _dao The associated DAO.
    /// @param _targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 2.
    constructor(IDAO _dao, TargetConfig memory _targetConfig) Plugin(_dao) {
        _setTargetConfig(_targetConfig);

        emit MembershipContractAnnounced({definingContract: address(_dao)});
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(Plugin, Proposal) returns (bool) {
        return
            _interfaceId == ADMIN_INTERFACE_ID ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        return
            dao().hasPermission({
                _where: address(this),
                _who: _account,
                _permissionId: EXECUTE_PROPOSAL_PERMISSION_ID,
                _data: bytes("")
            });
    }

    /// @inheritdoc IProposal
    function customProposalParamsABI() external pure override returns (string memory) {
        return "(uint256 allowFailureMap)";
    }

    /// @inheritdoc IProposal
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint64,
        uint64,
        bytes memory _data
    ) public override returns (uint256 proposalId) {
        uint256 allowFailureMap;

        if (_data.length > 0) {
            allowFailureMap = abi.decode(_data, (uint256));
        }

        // Uses public function for permission check.
        proposalId = executeProposal(_metadata, _actions, allowFailureMap);
    }

    /// @inheritdoc IProposal
    function hasSucceeded(uint256) public view virtual override returns (bool) {
        return true;
    }

    /// @inheritdoc IProposal
    function canExecute(uint256) public view virtual override returns (bool) {
        return true;
    }

    /// @inheritdoc IProposal
    /// @dev Note that this function will always revert since this contract doesn't store
    ///      proposals and only executes the actions at run-time. This function is still
    ///      necessary to allow compiling the contract as `Admin` inherits from `IProposal`.
    function execute(uint256) public view virtual override {
        revert FunctionNotSupported();
    }

    /// @notice Creates and executes a new proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions to be executed.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    ///     If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value
    ///     of 0 requires every action to not revert.
    function executeProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap
    ) public auth(EXECUTE_PROPOSAL_PERMISSION_ID) returns (uint256 proposalId) {
        uint64 currentTimestamp = block.timestamp.toUint64();

        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata)));

        TargetConfig memory targetConfig = getTargetConfig();

        _execute(
            targetConfig.target,
            bytes32(proposalId),
            _actions,
            _allowFailureMap,
            targetConfig.operation
        );

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            currentTimestamp,
            currentTimestamp,
            _metadata,
            _actions,
            _allowFailureMap
        );

        emit ProposalExecuted(proposalId);
    }
}

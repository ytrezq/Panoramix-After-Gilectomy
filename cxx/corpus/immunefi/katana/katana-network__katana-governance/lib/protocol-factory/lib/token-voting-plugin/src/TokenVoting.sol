// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {DAO, IDAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {MajorityVotingBase} from "./base/MajorityVotingBase.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {_applyRatioCeiled} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC6372Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC6372Upgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title TokenVoting
/// @author Aragon X - 2021-2025
/// @notice The majority voting implementation using an
///         [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
///         compatible governance token.
/// @dev v1.4 (Release 1, Build 4). For each upgrade, if the reinitialization step is required,
///      increment the version numbers in the modifier for both the initialize and initializeFrom functions.
/// @custom:security-contact sirt@aragon.org
contract TokenVoting is IMembership, MajorityVotingBase {
    using SafeCastUpgradeable for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant TOKEN_VOTING_INTERFACE_ID = this.getVotingToken.selector;

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
    ///         compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingToken; // Slot 0

    /// @notice Wether the token contract indexes past voting power by timestamp.
    bool public tokenIndexedByTimestamp; // Slot 0

    /// @notice The list of addresses excluded from voting
    EnumerableSet.AddressSet internal excludedAccounts; // Slot 1

    /// @notice Emitted when an account's balance is considered as non-circulating supply. Its balance will be excluded from the token supply computation.
    /// @param accounts The addresses whose balance is considered as not circulating
    event ExcludedFromSupply(address[] accounts);

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();

    /// @notice Thrown if the token reports an inconsistent clock mode and clock value
    error TokenClockMismatch();

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _votingSettings The voting settings.
    /// @param _token The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token to use for voting.
    ///     If the given token implements https://eips.ethereum.org/EIPS/eip-6372,
    ///     then `CLOCK_MODE()` or `clock()` will determine the clock type used by the plugin.
    ///     The token will be assumed to use a block number based clock otherwise.
    /// @param _targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    /// @param _minApprovals The minimal amount of approvals the proposal needs to succeed.
    /// @param _pluginMetadata The plugin specific information encoded in bytes.
    ///     This can also be an ipfs cid encoded in bytes.
    function initialize(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        IVotesUpgradeable _token,
        TargetConfig calldata _targetConfig,
        uint256 _minApprovals,
        bytes calldata _pluginMetadata,
        address[] memory _excludedAccounts
    ) external onlyCallAtInitialization reinitializer(3) {
        __MajorityVotingBase_init(_dao, _votingSettings, _targetConfig, _minApprovals, _pluginMetadata);

        votingToken = _token;

        _detectTokenClock();

        for (uint256 i; i < _excludedAccounts.length;) {
            excludedAccounts.add(_excludedAccounts[i]);

            unchecked {
                ++i;
            }
        }
        if (_excludedAccounts.length > 0) {
            emit ExcludedFromSupply(_excludedAccounts);
        }

        emit MembershipContractAnnounced({definingContract: address(_token)});
    }

    /// @notice Reinitializes the TokenVoting after an upgrade from a previous build version. For each
    ///         reinitialization step, use the `_fromBuild` version to decide which internal functions to
    ///         call for reinitialization.
    /// @dev WARNING: The contract should only be upgradeable through PSP to ensure that _fromBuild is not
    ///      incorrectly passed, and that the appropriate permissions for the upgrade are properly configured.
    /// @param _fromBuild Build version number of previous implementation contract this upgrade is transitioning from.
    /// @param _initData The initialization data to be passed to via `upgradeToAndCall`
    ///     (see [ERC-1967](https://docs.openzeppelin.com/contracts/4.x/api/proxy#ERC1967Upgrade)).
    function initializeFrom(uint16 _fromBuild, bytes calldata _initData) external reinitializer(3) {
        if (_fromBuild < 3) {
            (uint256 minApprovals, TargetConfig memory targetConfig, bytes memory pluginMetadata) =
                abi.decode(_initData, (uint256, TargetConfig, bytes));

            _updateMinApprovals(minApprovals);

            _setTargetConfig(targetConfig);

            _setMetadata(pluginMetadata);
        }
        if (_fromBuild < 4) {
            _detectTokenClock();

            // @dev The list of excluded accounts are intentionally skipped here
            //      Changing the excluded supply on the fly could break important governance invariants,
            //      therefore such feature is only allowed during the first initialization.
        }
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == TOKEN_VOTING_INTERFACE_ID || _interfaceId == type(IMembership).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    /// @notice getter function for the voting token.
    /// @dev public function also useful for registering interfaceId
    ///      and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }

    /// @notice Returns the total voting power checkpointed for a specific timestamp or block number, subtracting the balance of excluded addresses.
    /// @param _timePoint The block number or timestamp.
    /// @return The effective voting power.
    function totalVotingPower(uint256 _timePoint) public view override returns (uint256) {
        uint256 _excludedSupply;
        for (uint256 i; i < excludedAccounts.length();) {
            _excludedSupply += votingToken.getPastVotes(excludedAccounts.at(i), _timePoint);

            unchecked {
                ++i;
            }
        }
        return votingToken.getPastTotalSupply(_timePoint) - _excludedSupply;
    }

    /// @inheritdoc MajorityVotingBase
    /// @dev Requires the `CREATE_PROPOSAL_PERMISSION_ID` permission.
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) public override auth(CREATE_PROPOSAL_PERMISSION_ID) returns (uint256 proposalId) {
        uint256 snapshotTimepoint;
        unchecked {
            // The time point must be already mined (block) or in the past (timestamp) to
            // protect against backrunning transactions causing census changes.
            if (tokenIndexedByTimestamp) {
                snapshotTimepoint = block.timestamp - 1;
            } else {
                snapshotTimepoint = block.number - 1;
            }
        }

        uint256 totalVotingPower_ = totalVotingPower(snapshotTimepoint);

        if (totalVotingPower_ == 0) {
            revert NoVotingPower();
        }

        (_startDate, _endDate) = _validateProposalDates(_startDate, _endDate);

        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata)));

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        if (proposal_.parameters.snapshotTimepoint != 0) {
            revert ProposalAlreadyExists(proposalId);
        }

        proposal_.parameters.startDate = _startDate;
        proposal_.parameters.endDate = _endDate;
        proposal_.parameters.snapshotTimepoint = snapshotTimepoint.toUint64();
        proposal_.parameters.votingMode = votingMode();
        proposal_.parameters.supportThreshold = supportThreshold();
        proposal_.parameters.minVotingPower = _applyRatioCeiled(totalVotingPower_, minParticipation());

        proposal_.minApprovalPower = _applyRatioCeiled(totalVotingPower_, minApproval());

        proposal_.targetConfig = getTargetConfig();

        // Reduce costs
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length;) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        if (_voteOption != VoteOption.None) {
            vote(proposalId, _voteOption, _tryEarlyExecution);
        }

        _emitProposalCreatedEvent(_metadata, _actions, _allowFailureMap, proposalId, _startDate, _endDate);
    }

    /// @inheritdoc IProposal
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint64 _startDate,
        uint64 _endDate,
        bytes memory _data
    ) external override returns (uint256 proposalId) {
        // Note that this calls public function for permission check.
        uint256 allowFailureMap;
        VoteOption _voteOption = VoteOption.None;
        bool tryEarlyExecution;

        if (_data.length != 0) {
            (allowFailureMap, _voteOption, tryEarlyExecution) = abi.decode(_data, (uint256, VoteOption, bool));
        }

        proposalId =
            createProposal(_metadata, _actions, allowFailureMap, _startDate, _endDate, _voteOption, tryEarlyExecution);
    }

    /// @inheritdoc IProposal
    function customProposalParamsABI() external pure override returns (string memory) {
        return "(uint256 allowFailureMap, uint8 voteOption, bool tryEarlyExecution)";
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        // A member must own at least one token or have at least one token delegated to her/him.
        return votingToken.getVotes(_account) > 0 || IERC20Upgradeable(address(votingToken)).balanceOf(_account) > 0;
    }

    /// @inheritdoc MajorityVotingBase
    function _vote(uint256 _proposalId, VoteOption _voteOption, address _voter, bool _tryEarlyExecution)
        internal
        override
    {
        Proposal storage proposal_ = proposals[_proposalId];

        // This could re-enter, though we can assume the governance token is not malicious
        uint256 votingPower = votingToken.getPastVotes(_voter, proposal_.parameters.snapshotTimepoint);
        VoteOption state = proposal_.voters[_voter];

        // If voter had previously voted, decrease count
        if (state == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes - votingPower;
        } else if (state == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no - votingPower;
        } else if (state == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain - votingPower;
        }

        // write the updated/new vote for the voter.
        if (_voteOption == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes + votingPower;
        } else if (_voteOption == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no + votingPower;
        } else if (_voteOption == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain + votingPower;
        }

        proposal_.voters[_voter] = _voteOption;

        emit VoteCast({proposalId: _proposalId, voter: _voter, voteOption: _voteOption, votingPower: votingPower});

        if (!_tryEarlyExecution) {
            return;
        }

        if (
            _canExecute(_proposalId)
                && dao().hasPermission(address(this), _voter, EXECUTE_PROPOSAL_PERMISSION_ID, _msgData())
        ) {
            _execute(_proposalId);
        }
    }

    /// @inheritdoc MajorityVotingBase
    function _canVote(uint256 _proposalId, address _account, VoteOption _voteOption)
        internal
        view
        override
        returns (bool)
    {
        Proposal storage proposal_ = proposals[_proposalId];

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        // The voter votes `None` which is not allowed.
        if (_voteOption == VoteOption.None) {
            return false;
        }

        // The voter has no voting power.
        if (votingToken.getPastVotes(_account, proposal_.parameters.snapshotTimepoint) == 0) {
            return false;
        }

        // The voter has already voted but vote replacment is not allowed.
        if (
            proposal_.voters[_account] != VoteOption.None
                && proposal_.parameters.votingMode != VotingMode.VoteReplacement
        ) {
            return false;
        }

        return true;
    }

    /// @dev Helper function to identify the clock mode used by the given voting token.
    function _detectTokenClock() private {
        bool clockModeTimestamp;
        bool clockTimestamp;

        try IERC6372Upgradeable(address(votingToken)).CLOCK_MODE() returns (string memory clockMode) {
            clockModeTimestamp = keccak256(bytes(clockMode)) == keccak256(bytes("mode=timestamp"));
        } catch {}
        try IERC6372Upgradeable(address(votingToken)).clock() returns (uint48 timePoint) {
            clockTimestamp = (timePoint == block.timestamp);
        } catch {}

        if (clockModeTimestamp != clockTimestamp) {
            revert TokenClockMismatch();
        } else if (clockModeTimestamp) {
            tokenIndexedByTimestamp = true;
        } else {
            // Assuming that the token indexes by block number
        }
    }

    /// @dev Helper function to avoid stack too deep in non via-ir compilation mode.
    function _emitProposalCreatedEvent(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint256 proposalId,
        uint64 _startDate,
        uint64 _endDate
    ) private {
        emit ProposalCreated(proposalId, _msgSender(), _startDate, _endDate, _metadata, _actions, _allowFailureMap);
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[47] private __gap;
}

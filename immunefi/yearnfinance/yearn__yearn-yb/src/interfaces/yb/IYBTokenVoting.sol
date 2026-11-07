// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYBTokenVotingOption {
    function vote(
        uint256 _proposalId,
        uint8 _voteOption,
        bool _tryEarlyExecution
    ) external;
}
interface IYBTokenVoting {
    error AlreadyInitialized();
    error DaoUnauthorized(
        address dao,
        address where,
        address who,
        bytes32 permissionId
    );
    error DateOutOfBounds(uint64 limit, uint64 actual);
    error DelegateCallFailed();
    error FunctionDeprecated();
    error InvalidDecayMidpoint(uint32 decayMidpointBasisPoints);
    error InvalidTargetConfig(IPlugin.TargetConfig targetConfig);
    error MinDurationOutOfBounds(uint64 limit, uint64 actual);
    error NoVotingPower();
    error NonexistentProposal(uint256 proposalId);
    error ProposalAlreadyExists(uint256 proposalId);
    error ProposalCooldownNotMet(uint256 remainingCooldown);
    error ProposalExecutionForbidden(uint256 proposalId);
    error RatioOutOfBounds(uint256 limit, uint256 actual);
    error TokenClockMismatch();
    error VoteCastForbidden(
        uint256 proposalId,
        address account,
        IMajorityVoting.Tally votes
    );
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
    event CooldownSettingsUpdated(uint32 cooldownPeriod);
    event DecaySettingsUpdated(uint32 decayMidpointBasisPoints);
    event ExcludedFromSupply(address[] accounts);
    event Initialized(uint8 version);
    event MembersAdded(address[] members);
    event MembersRemoved(address[] members);
    event MembershipContractAnnounced(address indexed definingContract);
    event MetadataSet(bytes metadata);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event TargetSet(IPlugin.TargetConfig newTargetConfig);
    event Upgraded(address indexed implementation);
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        IMajorityVoting.Tally votes
    );
    event VotingMinApprovalUpdated(uint256 minApprovals);
    event VotingSettingsUpdated(
        uint8 votingMode,
        uint32 supportThreshold,
        uint32 minParticipation,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );

    function CREATE_PROPOSAL_PERMISSION_ID() external view returns (bytes32);

    function EXECUTE_PROPOSAL_PERMISSION_ID() external view returns (bytes32);

    function SET_METADATA_PERMISSION_ID() external view returns (bytes32);

    function SET_TARGET_CONFIG_PERMISSION_ID() external view returns (bytes32);

    function UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        external
        view
        returns (bytes32);

    function UPGRADE_PLUGIN_PERMISSION_ID() external view returns (bytes32);

    function canExecute(uint256 _proposalId) external view returns (bool);

    function canVote(
        uint256 _proposalId,
        address _account,
        uint8 _voteOption
    ) external view returns (bool);

    function canVote(
        uint256 _proposalId,
        address _account,
        IMajorityVoting.Tally memory _votes
    ) external view returns (bool);

    // function createProposal(
    //     bytes memory _metadata,
    //     Action[] memory _actions,
    //     uint256 _allowFailureMap,
    //     uint64 _startDate,
    //     uint64 _endDate,
    //     uint8 _voteOption,
    //     bool _tryEarlyExecution
    // ) external returns (uint256 proposalId);

    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 _endDate,
        bytes memory _data
    ) external returns (uint256 proposalId);

    function customProposalParamsABI() external pure returns (string memory);

    function dao() external view returns (address);

    function execute(uint256 _proposalId) external;

    function grant(
        address _where,
        address _who,
        bytes32 _permissionId
    ) external;

    function revoke(
        address _where,
        address _who,
        bytes32 _permissionId
    ) external;

    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes memory _data
    ) external view returns (bool);

    function getCurrentTargetConfig()
        external
        view
        returns (IPlugin.TargetConfig memory);

    function getDecayMidpointBasisPoints() external view returns (uint32);

    function getMetadata() external view returns (bytes memory);

    function getProposal(uint256 _proposalId)
        external
        view
        returns (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory parameters,
            IMajorityVoting.Tally memory tally,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        );

    function getProposalCooldownPeriod() external view returns (uint32);

    function getTargetConfig()
        external
        view
        returns (IPlugin.TargetConfig memory);

    function getUserLastProposalTimestamp(address _user)
        external
        view
        returns (uint256);

    function getVotes(uint256 _proposalId, address _account)
        external
        view
        returns (IMajorityVoting.Tally memory);

    function getVotingToken() external view returns (address);

    function hasSucceeded(uint256 _proposalId) external view returns (bool);

    function implementation() external view returns (address);

    function initialize(
        address _dao,
        MajorityVotingBase.VotingSettings memory _votingSettings,
        address _token,
        IPlugin.TargetConfig memory _targetConfig,
        bytes memory _pluginMetadata,
        TokenVoting.ExtendedParams memory _extendedParams
    ) external;

    function isMember(address _account) external view returns (bool);

    function isMinApprovalReached(uint256 _proposalId)
        external
        view
        returns (bool);

    function isMinParticipationReached(uint256 _proposalId)
        external
        view
        returns (bool);

    function isSupportThresholdReached(uint256 _proposalId)
        external
        view
        returns (bool);

    function isSupportThresholdReachedEarly(uint256 _proposalId)
        external
        view
        returns (bool);

    function minApproval() external view returns (uint256);

    function minDuration() external view returns (uint64);

    function minParticipation() external view returns (uint32);

    function minProposerVotingPower() external view returns (uint256);

    function pluginType() external pure returns (uint8);

    function proposalCount() external view returns (uint256);

    function protocolVersion() external pure returns (uint8[3] memory);

    function proxiableUUID() external view returns (bytes32);

    function setMetadata(bytes memory _metadata) external;

    function setTargetConfig(IPlugin.TargetConfig memory _targetConfig)
        external;

    function supportThreshold() external view returns (uint32);

    function supportsInterface(bytes4 _interfaceId)
        external
        view
        returns (bool);

    function tokenIndexedByTimestamp() external view returns (bool);

    function totalVotingPower(uint256 _timePoint)
        external
        view
        returns (uint256);

    function updateCooldownSettings(uint32 _cooldownPeriod) external;

    function updateDecaySettings(uint32 _decayMidpointBasisPoints) external;

    function updateMinApprovals(uint256 _minApprovals) external;

    function updateVotingSettings(
        MajorityVotingBase.VotingSettings memory _votingSettings
    ) external;

    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data)
        external
        payable;

    function vote(
        uint256 _proposalId,
        IMajorityVoting.Tally memory _votes,
        bool _tryEarlyExecution
    ) external;

    function votingMode() external view returns (uint8);
}

interface IPlugin {
    struct TargetConfig {
        address target;
        uint8 operation;
    }
}

interface IMajorityVoting {
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }
}

interface MajorityVotingBase {
    struct ProposalParameters {
        uint8 votingMode;
        uint32 supportThreshold;
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotTimepoint;
        uint256 minVotingPower;
    }

    struct VotingSettings {
        uint8 votingMode;
        uint32 supportThreshold;
        uint32 minParticipation;
        uint64 minDuration;
        uint256 minProposerVotingPower;
    }
}

interface TokenVoting {
    struct ExtendedParams {
        uint256 minApprovals;
        address[] excludedAccounts;
        uint32 decayMidpointBasisPoints;
        uint32 proposalCreationCooldownPeriod;
    }
}

struct Action {
    address to;
    uint256 value;
    bytes data;
}
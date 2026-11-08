// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SimpleBuilder} from "./builders/SimpleBuilder.sol";
import {TestBase} from "./lib/TestBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {TokenVoting} from "../src/TokenVoting.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {VotingPowerCondition} from "../src/condition/VotingPowerCondition.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IProtocolVersion} from "@aragon/osx-commons-contracts/src/utils/versioning/IProtocolVersion.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {IMajorityVoting} from "../src/base/IMajorityVoting.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";

import {MajorityVotingBase} from "../src/base/MajorityVotingBase.sol";

contract MajorityVotingBaseTest is TestBase {
    DAO internal dao;
    TokenVoting internal plugin;
    IVotesUpgradeable internal token;
    VotingPowerCondition internal condition;
    MajorityVotingBase.VotingSettings internal defaultNewVotingSettings;

    bytes4 internal constant MAJORITY_VOTING_BASE_INTERFACE_ID = MajorityVotingBase.minDuration.selector
        ^ MajorityVotingBase.minProposerVotingPower.selector ^ MajorityVotingBase.votingMode.selector
        ^ MajorityVotingBase.totalVotingPower.selector ^ MajorityVotingBase.getProposal.selector
        ^ MajorityVotingBase.updateVotingSettings.selector ^ MajorityVotingBase.updateMinApprovals.selector
        ^ bytes4(keccak256("createProposal(bytes,(address,uint256,bytes)[],uint256,uint64,uint64,uint8,bool)"));

    error AlreadyInitialized();

    function setUp() public {
        SimpleBuilder builder = new SimpleBuilder();
        (dao, plugin, token, condition) = builder.build();

        defaultNewVotingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
            supportThreshold: 500_000,
            minParticipation: 200_000,
            minDuration: 1 hours,
            minProposerVotingPower: 0
        });
    }

    modifier givenTheContractIsAlreadyInitialized() {
        _;
    }

    function test_WhenCallingInitialize() external givenTheContractIsAlreadyInitialized {
        // It reverts if trying to re-initialize
        vm.expectRevert(abi.encodeWithSelector(AlreadyInitialized.selector));
        plugin.initialize(
            dao,
            MajorityVotingBase.VotingSettings({
                votingMode: MajorityVotingBase.VotingMode.Standard,
                supportThreshold: 500_000,
                minParticipation: 100_000,
                minDuration: 1 hours,
                minProposerVotingPower: 0
            }),
            token,
            IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call),
            0,
            "",
            new address[](0)
        );
    }

    modifier givenTheContractIsDeployed() {
        _;
    }

    function test_WhenCallingSupportsInterfaceWithTheEmptyInterface() external view givenTheContractIsDeployed {
        // It does not support the empty interface
        assertFalse(plugin.supportsInterface(0xffffffff));
    }

    function test_WhenCallingSupportsInterfaceWithTheIERC165UpgradeableInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IERC165Upgradeable` interface
        assertTrue(plugin.supportsInterface(type(IERC165Upgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIPluginInterface() external view givenTheContractIsDeployed {
        // It supports the `IPlugin` interface
        assertTrue(plugin.supportsInterface(type(IPlugin).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIProtocolVersionInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IProtocolVersion` interface
        assertTrue(plugin.supportsInterface(type(IProtocolVersion).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIProposalInterface() external view givenTheContractIsDeployed {
        // It supports the `IProposal` interface
        assertTrue(plugin.supportsInterface(type(IProposal).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIMajorityVotingInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IMajorityVoting` interface
        assertTrue(plugin.supportsInterface(type(IMajorityVoting).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIMajorityVotingOLDInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IMajorityVoting` OLD interface
        // The old interface is the current one without `isMinApprovalReached` and `minApproval`.
        bytes4 oldInterfaceId =
            type(IMajorityVoting).interfaceId ^ plugin.isMinApprovalReached.selector ^ plugin.minApproval.selector;
        assertTrue(plugin.supportsInterface(oldInterfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheMajorityVotingBaseInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `MajorityVotingBase` interface
        assertTrue(plugin.supportsInterface(MAJORITY_VOTING_BASE_INTERFACE_ID));
    }

    function test_WhenCallingSupportsInterfaceWithTheMajorityVotingBaseOLDInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `MajorityVotingBase` OLD interface
        // The old interface is the current one without `updateMinApprovals`.
        bytes4 oldInterfaceId = MAJORITY_VOTING_BASE_INTERFACE_ID ^ plugin.updateMinApprovals.selector;
        assertTrue(plugin.supportsInterface(oldInterfaceId));
    }

    modifier givenThePluginIsInitialized() {
        dao.grant(address(plugin), address(this), plugin.UPDATE_VOTING_SETTINGS_PERMISSION_ID());

        _;
    }

    modifier givenTheCallerIsUnauthorized() {
        _;
    }

    function test_WhenCallingUpdateVotingSettings() external givenThePluginIsInitialized givenTheCallerIsUnauthorized {
        // It reverts if caller is unauthorized

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                bob,
                plugin.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    function test_WhenCallingUpdateVotingSettingsWhereSupportThresholdEquals100()
        external
        givenThePluginIsInitialized
    {
        // It reverts if the support threshold specified equals 100%
        defaultNewVotingSettings.supportThreshold = uint32(RATIO_BASE);

        vm.expectRevert(
            abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE - 1, defaultNewVotingSettings.supportThreshold)
        );
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    function test_WhenCallingUpdateVotingSettingsWhereSupportThresholdExceeds100()
        external
        givenThePluginIsInitialized
    {
        // It reverts if the support threshold specified exceeds 100%
        defaultNewVotingSettings.supportThreshold = uint32(RATIO_BASE) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE - 1, defaultNewVotingSettings.supportThreshold)
        );
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    // This is a duplicate test title from the source file, testing a threshold > 100%
    function test_WhenCallingUpdateVotingSettingsWhereSupportThresholdEquals1002()
        external
        givenThePluginIsInitialized
    {
        // It reverts if the support threshold specified equals 100%
        defaultNewVotingSettings.supportThreshold = uint32(RATIO_BASE) + 100;

        vm.expectRevert(
            abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE - 1, defaultNewVotingSettings.supportThreshold)
        );
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    function test_WhenCallingUpdateVotingSettingsWhereMinimumParticipationExceeds100()
        external
        givenThePluginIsInitialized
    {
        // It reverts if the minimum participation specified exceeds 100%
        defaultNewVotingSettings.minParticipation = uint32(RATIO_BASE) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE, defaultNewVotingSettings.minParticipation)
        );
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    function test_WhenCallingUpdateVotingSettingsWhereMinimalDurationIsShorterThanOneHour()
        external
        givenThePluginIsInitialized
    {
        // It reverts if the minimal duration is shorter than one hour
        defaultNewVotingSettings.minDuration = 1 hours - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.MinDurationOutOfBounds.selector, 1 hours, defaultNewVotingSettings.minDuration
            )
        );
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    function test_WhenCallingUpdateVotingSettingsWhereMinimalDurationIsLongerThanOneYear()
        external
        givenThePluginIsInitialized
    {
        // It reverts if the minimal duration is longer than one year
        defaultNewVotingSettings.minDuration = 365 days + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.MinDurationOutOfBounds.selector, 365 days, defaultNewVotingSettings.minDuration
            )
        );
        plugin.updateVotingSettings(defaultNewVotingSettings);
    }

    function test_WhenCallingUpdateVotingSettings2() external givenThePluginIsInitialized {
        // It should change the voting settings successfully

        vm.expectEmit(true, true, true, true);
        emit MajorityVotingBase.VotingSettingsUpdated(
            defaultNewVotingSettings.votingMode,
            defaultNewVotingSettings.supportThreshold,
            defaultNewVotingSettings.minParticipation,
            defaultNewVotingSettings.minDuration,
            defaultNewVotingSettings.minProposerVotingPower
        );

        plugin.updateVotingSettings(defaultNewVotingSettings);

        (
            MajorityVotingBase.VotingMode mode,
            uint32 support,
            uint32 participation,
            uint64 duration,
            uint256 proposerPower
        ) = (
            plugin.votingMode(),
            plugin.supportThreshold(),
            plugin.minParticipation(),
            plugin.minDuration(),
            plugin.minProposerVotingPower()
        );

        assertEq(uint8(mode), uint8(defaultNewVotingSettings.votingMode));
        assertEq(support, defaultNewVotingSettings.supportThreshold);
        assertEq(participation, defaultNewVotingSettings.minParticipation);
        assertEq(duration, defaultNewVotingSettings.minDuration);
        assertEq(proposerPower, defaultNewVotingSettings.minProposerVotingPower);
    }

    modifier givenThePluginIsInitialized2() {
        dao.grant(address(plugin), address(this), plugin.UPDATE_VOTING_SETTINGS_PERMISSION_ID());

        _;
    }

    modifier givenTheCallerIsUnauthorized2() {
        _;
    }

    function test_WhenCallingUpdateMinApprovals() external givenThePluginIsInitialized2 givenTheCallerIsUnauthorized2 {
        // It reverts if caller is unauthorized
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                bob,
                plugin.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.updateMinApprovals(100_000);
    }

    function test_WhenCallingUpdateMinApprovalsWhereTheMinimumApprovalExceeds100()
        external
        givenThePluginIsInitialized2
    {
        // It reverts if the minimum approval specified exceeds 100%
        uint256 newMinApproval = RATIO_BASE + 1;

        vm.expectRevert(abi.encodeWithSelector(RatioOutOfBounds.selector, RATIO_BASE, newMinApproval));
        plugin.updateMinApprovals(newMinApproval);
    }

    function test_WhenCallingUpdateMinApprovals2() external givenThePluginIsInitialized2 {
        // It should change the minimum approval successfully
        uint256 newMinApproval = 100_000; // 10%

        vm.expectEmit(true, false, false, true);
        emit MajorityVotingBase.VotingMinApprovalUpdated(newMinApproval);

        plugin.updateMinApprovals(newMinApproval);

        assertEq(plugin.minApproval(), newMinApproval);
    }

    modifier givenThePluginIsInitializedAndTheCallerHasTheSETTARGETCONFIGPERMISSIONID() {
        dao.grant(address(plugin), address(this), plugin.SET_TARGET_CONFIG_PERMISSION_ID());
        _;
    }

    function test_WhenCallingSetTargetConfig()
        external
        givenThePluginIsInitializedAndTheCallerHasTheSETTARGETCONFIGPERMISSIONID
    {
        // It should change the target config successfully
        IPlugin.TargetConfig memory newConfig = IPlugin.TargetConfig(randomAddress, IPlugin.Operation.DelegateCall);

        plugin.setTargetConfig(newConfig);

        assertEq(plugin.getTargetConfig().target, newConfig.target);
        assertEq(uint8(plugin.getTargetConfig().operation), uint8(newConfig.operation));
    }
}

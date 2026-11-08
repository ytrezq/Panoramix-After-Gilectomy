// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {ForkBuilder} from "../builders/ForkBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {TokenVotingSetup} from "../../src/TokenVotingSetup.sol";
import {TokenVoting} from "../../src/TokenVoting.sol";
import {IMajorityVoting} from "../../src/base/IMajorityVoting.sol";
import {NON_EMPTY_BYTES} from "../constants.sol";

// Aragon OSx Contracts
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {
    PluginSetupRef,
    hashHelpers,
    hashPermissions
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

// Plugin Contracts
import {MajorityVotingBase} from "../../src/base/MajorityVotingBase.sol";
import {GovernanceERC20} from "../../src/erc20/GovernanceERC20.sol";

// OZ Contracts
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract PluginSetupForkTest is ForkTestBase {
    // An address of the official TokenVoting plugin repository on Sepolia
    address private constant TOKEN_VOTING_REPO_ADDRESS = 0x424F4cA6FA9c24C03f2396DF0E96057eD11CF7dF;

    DAO internal dao;
    PluginRepo internal repo = PluginRepo(TOKEN_VOTING_REPO_ADDRESS);

    function setUp() public virtual {
        dao = new ForkBuilder().build();
    }

    function test_simpleFlow() public view {
        // Check the Repo
        PluginRepo.Version memory version = repo.getLatestVersion(repo.latestRelease());
        assertEq(version.buildMetadata, bytes("ipfs://bafkreifsn2562ftambmmfoqa64wfxviu4g47evmcj5ydsjdmmsmqhqrn3i"));

        // Check the DAO
        assertEq(keccak256(bytes(dao.daoURI())), keccak256(bytes("http://host/")));
    }

    modifier givenTheDeployerHasAllNecessaryPermissionsForInstallationAndUninstallation() {
        _;
    }

    function test_WhenInstallingAndThenUninstallingTheCurrentBuildUsingAnExistingToken()
        external
        givenTheDeployerHasAllNecessaryPermissionsForInstallationAndUninstallation
    {
        // It installs & uninstalls the current build with a token

        // SETUP with an existing token
        GovernanceERC20 existingToken;
        {
            address[] memory receivers = new address[](1);
            receivers[0] = alice;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 100 ether;
            GovernanceERC20.MintSettings memory initialMint = GovernanceERC20.MintSettings(receivers, amounts, true);
            existingToken = new GovernanceERC20(dao, "Existing Token", "EXIST", initialMint);
        }

        // PERMISSIONS: Grant the necessary permissions to the PluginSetupProcessor
        dao.grant(address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID());
        dao.grant(
            address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_UNINSTALLATION_PERMISSION_ID()
        );
        dao.grant(address(dao), address(pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        PluginSetupRef memory setupRef = PluginSetupRef({versionTag: getLatestTag(repo), pluginSetupRepo: repo});

        // INSTALLATION
        // Prepare installation data using the existing token
        bytes memory installData;
        {
            MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings(
                MajorityVotingBase.VotingMode.EarlyExecution, 500_000, 200_000, 1 hours, 0
            );
            TokenVotingSetup.TokenSettings memory tokenSettings =
                TokenVotingSetup.TokenSettings({addr: address(existingToken), name: "Test Token", symbol: "TTK"});
            GovernanceERC20.MintSettings memory emptyMintSettings =
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0), false);
            IPlugin.TargetConfig memory targetConfig = IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call);

            installData = abi.encode(
                votingSettings, tokenSettings, emptyMintSettings, targetConfig, 0, "some-metadata", new address[](0)
            );
        }

        // Prepare and apply the installation
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        {
            PluginSetupProcessor.PrepareInstallationParams memory prepareInstallParams =
                PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: setupRef, data: installData});

            (pluginAddr, preparedSetupData) =
                pluginSetupProcessor.prepareInstallation(address(dao), prepareInstallParams);

            vm.label(pluginAddr, "NewTokenVoting");

            PluginSetupProcessor.ApplyInstallationParams memory applyInstallParams = PluginSetupProcessor
                .ApplyInstallationParams({
                pluginSetupRef: setupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyInstallation(address(dao), applyInstallParams);

            vm.assertTrue(
                dao.isGranted(address(dao), pluginAddr, dao.EXECUTE_PERMISSION_ID(), ""), "Plugin should be installed"
            );
        }

        // Assert that the installation was successful and configured correctly
        {
            TokenVoting tokenVotingPlugin = TokenVoting(pluginAddr);
            assertEq(address(tokenVotingPlugin.getVotingToken()), address(existingToken), "Token address mismatch");
            assertTrue(tokenVotingPlugin.isMember(alice), "Alice should be a member");
            assertFalse(tokenVotingPlugin.isMember(bob), "Bob should not be a member");
        }

        // Move forward (avoid collisions)
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // UNINSTALLATION
        // Prepare and apply the uninstallation
        {
            PluginSetupProcessor.PrepareUninstallationParams memory uninstallParams = PluginSetupProcessor
                .PrepareUninstallationParams({
                pluginSetupRef: setupRef,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: pluginAddr,
                    currentHelpers: preparedSetupData.helpers,
                    data: ""
                })
            });
            PermissionLib.MultiTargetPermission[] memory uninstallPermissions =
                pluginSetupProcessor.prepareUninstallation(address(dao), uninstallParams);

            PluginSetupProcessor.ApplyUninstallationParams memory applyUninstallParams = PluginSetupProcessor
                .ApplyUninstallationParams({plugin: pluginAddr, pluginSetupRef: setupRef, permissions: uninstallPermissions});
            pluginSetupProcessor.applyUninstallation(address(dao), applyUninstallParams);
        }

        // Assert that the plugin was successfully uninstalled
        vm.assertFalse(
            dao.isGranted(address(dao), pluginAddr, dao.EXECUTE_PERMISSION_ID(), ""), "Plugin should be uninstalled"
        );
    }

    modifier givenTheDeployerHasAllNecessaryPermissionsForInstallationAndUninstallation2() {
        _;
    }

    function test_WhenInstallingAndThenUninstallingTheCurrentBuildCreatingANewToken()
        external
        givenTheDeployerHasAllNecessaryPermissionsForInstallationAndUninstallation2
    {
        // It installs & uninstalls the current build without a token

        // PERMISSIONS: Grant the necessary permissions
        dao.grant(address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID());
        dao.grant(
            address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_UNINSTALLATION_PERMISSION_ID()
        );
        dao.grant(address(dao), address(pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        PluginSetupRef memory setupRef = PluginSetupRef({versionTag: getLatestTag(repo), pluginSetupRepo: repo});

        // INSTALLATION
        // Prepare installation data to create a new token
        bytes memory installData;

        {
            MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings(
                MajorityVotingBase.VotingMode.EarlyExecution, 500_000, 200_000, 1 hours, 0
            );
            TokenVotingSetup.TokenSettings memory tokenSettings =
                TokenVotingSetup.TokenSettings({addr: address(0), name: "New Token", symbol: "NEW"});
            address[] memory receivers = new address[](1);
            receivers[0] = alice;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1000 ether;
            GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(receivers, amounts, true);
            IPlugin.TargetConfig memory targetConfig = IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call);

            installData = abi.encode(votingSettings, tokenSettings, mintSettings, targetConfig, 0, "some-metadata");
        }

        // Prepare and apply the installation
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;

        {
            PluginSetupProcessor.PrepareInstallationParams memory prepareInstallParams =
                PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: setupRef, data: installData});

            (pluginAddr, preparedSetupData) =
                pluginSetupProcessor.prepareInstallation(address(dao), prepareInstallParams);

            vm.label(pluginAddr, "NewTokenVoting");

            PluginSetupProcessor.ApplyInstallationParams memory applyInstallParams = PluginSetupProcessor
                .ApplyInstallationParams({
                pluginSetupRef: setupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyInstallation(address(dao), applyInstallParams);

            vm.assertTrue(
                dao.isGranted(address(dao), pluginAddr, dao.EXECUTE_PERMISSION_ID(), ""), "Plugin should be installed"
            );
        }

        // Assert that the installation created and configured the new token correctly
        {
            TokenVoting tokenVotingPlugin = TokenVoting(pluginAddr);
            IVotesUpgradeable newToken = tokenVotingPlugin.getVotingToken();
            assertNotEq(address(newToken), address(0), "New token should have been created");
            assertTrue(tokenVotingPlugin.isMember(alice), "Alice should be a member");
            assertFalse(tokenVotingPlugin.isMember(bob), "Bob should not be a member");
        }

        // Move forward (avoid collisions)
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // UNINSTALLATION
        // Prepare and apply the uninstallation
        {
            PluginSetupProcessor.PrepareUninstallationParams memory uninstallParams = PluginSetupProcessor
                .PrepareUninstallationParams({
                pluginSetupRef: setupRef,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: pluginAddr,
                    currentHelpers: preparedSetupData.helpers,
                    data: ""
                })
            });
            PermissionLib.MultiTargetPermission[] memory uninstallPermissions =
                pluginSetupProcessor.prepareUninstallation(address(dao), uninstallParams);

            PluginSetupProcessor.ApplyUninstallationParams memory applyUninstallParams = PluginSetupProcessor
                .ApplyUninstallationParams({plugin: pluginAddr, pluginSetupRef: setupRef, permissions: uninstallPermissions});
            pluginSetupProcessor.applyUninstallation(address(dao), applyUninstallParams);
        }

        // Assert that the plugin was successfully uninstalled
        vm.assertFalse(
            dao.isGranted(address(dao), pluginAddr, dao.EXECUTE_PERMISSION_ID(), ""), "Plugin should be uninstalled"
        );
    }

    modifier givenAPreviousPluginBuild2IsInstalledAndTheDeployerHasUpdatePermissions() {
        _;
    }

    function test_WhenUpdatingFromBuild2ToTheCurrentBuild()
        external
        givenAPreviousPluginBuild2IsInstalledAndTheDeployerHasUpdatePermissions
    {
        // It updates from build 2 to the current build

        // SETUP: Create a DAO
        dao = new ForkBuilder().build();

        // PERMISSIONS: Grant installation and update permissions
        PluginRepo liveRepo = PluginRepo(TOKEN_VOTING_REPO_ADDRESS);

        dao.grant(address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID());
        dao.grant(address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_UPDATE_PERMISSION_ID());
        dao.grant(address(dao), address(pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        // INSTALL OLD BUILD (v1.2)
        PluginSetupRef memory oldSetupRef =
            PluginSetupRef({versionTag: PluginRepo.Tag({release: 1, build: 2}), pluginSetupRepo: liveRepo});

        // Prepare installation data compatible with build 2
        // Assumes build 1 `prepareInstallation` signature was: (VotingSettings, TokenSettings, MintSettings)
        MajorityVotingBase.VotingSettings memory votingSettings =
            MajorityVotingBase.VotingSettings(MajorityVotingBase.VotingMode.Standard, 500_000, 100_000, 1 hours, 0);
        TokenVotingSetup.TokenSettings memory tokenSettings =
            TokenVotingSetup.TokenSettings({addr: address(0), name: "Old Token", symbol: "OLD"});
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings(new address[](0), new uint256[](0), false);
        bytes memory installDataV1 = abi.encode(votingSettings, tokenSettings, mintSettings);

        bytes memory initializeFromData;
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        {
            uint256 newMinApprovals = 200_000;
            IPlugin.TargetConfig memory newTargetConfig =
                IPlugin.TargetConfig(makeAddr("newTarget-2"), IPlugin.Operation.Call);
            bytes memory newMetadata = "0x22";
            initializeFromData = abi.encode(newMinApprovals, newTargetConfig, newMetadata);
        }

        address pluginAddr;
        address oldImplementation;
        {
            PluginSetupProcessor.PrepareInstallationParams memory prepareInstallParams =
                PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: oldSetupRef, data: installDataV1});

            (pluginAddr, preparedSetupData) =
                pluginSetupProcessor.prepareInstallation(address(dao), prepareInstallParams);

            vm.label(pluginAddr, "NewTokenVoting");
            oldImplementation = TokenVoting(pluginAddr).implementation();

            PluginSetupProcessor.ApplyInstallationParams memory applyInstallParams = PluginSetupProcessor
                .ApplyInstallationParams({
                pluginSetupRef: oldSetupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyInstallation(address(dao), applyInstallParams);

            vm.assertTrue(
                dao.isGranted(address(dao), pluginAddr, dao.EXECUTE_PERMISSION_ID(), ""), "Plugin should be installed"
            );

            // Move forward (avoid collisions)
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);

            // UPDATE TO LATEST BUILD
            dao.grant(pluginAddr, address(pluginSetupProcessor), TokenVoting(pluginAddr).UPGRADE_PLUGIN_PERMISSION_ID());
            PluginSetupRef memory latestSetupRef =
                PluginSetupRef({versionTag: getLatestTag(liveRepo), pluginSetupRepo: liveRepo});

            // Prepare update data for the latest build

            // Prepare and apply the update
            PluginSetupProcessor.PrepareUpdateParams memory updateParams = PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: oldSetupRef.versionTag,
                newVersionTag: latestSetupRef.versionTag,
                pluginSetupRepo: repo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: pluginAddr,
                    currentHelpers: preparedSetupData.helpers,
                    data: initializeFromData
                })
            });

            bytes memory initData;
            (initData, preparedSetupData) = pluginSetupProcessor.prepareUpdate(address(dao), updateParams);
            PluginSetupProcessor.ApplyUpdateParams memory applyUpdateParams = PluginSetupProcessor.ApplyUpdateParams({
                plugin: pluginAddr,
                pluginSetupRef: latestSetupRef,
                initData: initData,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyUpdate(address(dao), applyUpdateParams);
        }

        // ASSERTIONS
        {
            TokenVoting tokenVotingPlugin = TokenVoting(pluginAddr);
            assertNotEq(tokenVotingPlugin.implementation(), oldImplementation, "Implementation not updated");
            assertEq(tokenVotingPlugin.minApproval(), 200_000, "minApproval not updated");
            assertEq(tokenVotingPlugin.getTargetConfig().target, makeAddr("newTarget-2"), "Target address not updated");
            assertEq(
                uint8(tokenVotingPlugin.getTargetConfig().operation),
                uint8(IPlugin.Operation.Call),
                "Target operation not updated"
            );
        }
    }
}

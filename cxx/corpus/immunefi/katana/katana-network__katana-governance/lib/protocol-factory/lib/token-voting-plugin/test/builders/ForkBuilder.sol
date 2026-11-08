// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {DAO, IDAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";

contract ForkBuilder is ForkTestBase {
    // Add your own parameters here

    // Override methods

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build() public returns (DAO dao) {
        // DAO settings
        DAOFactory.DAOSettings memory daoSettings =
            DAOFactory.DAOSettings({trustedForwarder: address(0), daoURI: "http://host/", subdomain: "", metadata: ""});

        // No plugins, the sender can execute
        DAOFactory.PluginSettings[] memory installSettings = new DAOFactory.PluginSettings[](0);

        // Create DAO
        DAOFactory.InstalledPlugin[] memory installedPlugins;
        (dao, installedPlugins) = daoFactory.createDao(daoSettings, installSettings);

        // Set msg.sender as the owner
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (address(dao), msg.sender, dao.ROOT_PERMISSION_ID()))
        });
        dao.execute(bytes32(0), actions, 0);

        // Labels
        vm.label(address(dao), "DAO");

        // Moving forward to avoid collisions
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IMigrator } from "../../modules/migrator/contracts/interfaces/IMigrator.sol";

import { IMapleToken }  from "../../contracts/interfaces/IMapleToken.sol";

import { EmergencyModule }        from "../../contracts/EmergencyModule.sol";
import { RecapitalizationModule } from "../../contracts/RecapitalizationModule.sol";

import { RecapitalizationModuleHealthChecker } from "../health-checkers/RecapitalizationModuleHealthChecker.sol";

import { IGlobalsLike } from "../utils/Interfaces.sol";
import { console }      from "../utils/TestBase.sol";

import { LifecycleBase } from "../e2e/MigrationAndLifecycle.t.sol";

import { ProcedureAddressRegistry as AddressRegistry } from "./ProcedureAddressRegistry.sol";

contract LifecycleValidation is LifecycleBase, AddressRegistry {

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _globals                = IGlobalsLike(globals);
        _token                  = IMapleToken(mplv2Proxy);
        _migrator               = IMigrator(migrator);
        _recapitalizationModule = RecapitalizationModule(recapitalizationModule);
        _emergencyModule        = new EmergencyModule(address(_globals), address(_token));

        _claimer         = securityAdmin;
        _governor        = governor;
        _treasury        = mapleTreasury;

        healthChecker = new RecapitalizationModuleHealthChecker();

        // Since the procedure doesn't do that, add emergency module
        vm.startPrank(governor);

        _globals.scheduleCall(
            address(_token),
            "MT:ADD_MODULE",
            abi.encodeWithSelector(IMapleToken.addModule.selector, address(_emergencyModule))
        );

        vm.warp(block.timestamp + 7 days + 1);
        _token.addModule(address(_emergencyModule));

        vm.stopPrank();

        setupHandlers();
    }

    function test_lifecycleValidation(uint256 seed) external{
        runLifecycle(seed);
    }

}

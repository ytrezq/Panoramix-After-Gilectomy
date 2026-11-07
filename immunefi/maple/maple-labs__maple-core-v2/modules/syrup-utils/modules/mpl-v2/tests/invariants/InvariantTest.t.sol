// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IEmergencyModule }        from "../../contracts/interfaces/IEmergencyModule.sol";
import { IMapleToken }             from "../../contracts/interfaces/IMapleToken.sol";
import { IRecapitalizationModule } from "../../contracts/interfaces/IRecapitalizationModule.sol";

import { EmergencyModule }        from "../../contracts/EmergencyModule.sol";
import { MapleToken }             from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer }  from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }        from "../../contracts/MapleTokenProxy.sol";
import { RecapitalizationModule } from "../../contracts/RecapitalizationModule.sol";

import { IGlobalsLike } from "../utils/Interfaces.sol";
import { TestBase }     from "../utils/TestBase.sol";

import { DistributionHandler } from "./DistributionHandler.sol";
import { ModuleHandler }       from "./ModuleHandler.sol";
import { ModuleInvariants }    from "./ModuleInvariants.sol";

contract InvariantTest is ModuleInvariants {

    address claimer  = makeAddr("claimer");
    address governor = makeAddr("governor");
    address migrator = makeAddr("migrator");
    address treasury = makeAddr("treasury");

    IGlobalsLike mapleGlobals;
    IMapleToken  mapleToken;

    IEmergencyModule        emergencyModule;
    IRecapitalizationModule recapitalizationModule;

    DistributionHandler distributionHandler;
    ModuleHandler       moduleHandler;

    function setUp() external {
        deployContracts();
        configureContracts();
        setupHandlers();
    }

    function deployContracts() internal {
        mapleGlobals = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));
        mapleToken   = IMapleToken(address(new MapleTokenProxy(
            address(mapleGlobals),
            address(new MapleToken()),
            address(new MapleTokenInitializer()),
            migrator
        )));

        emergencyModule        = new EmergencyModule(address(mapleGlobals), address(mapleToken));
        recapitalizationModule = new RecapitalizationModule(address(mapleToken));
    }

    function configureContracts() internal {
        vm.startPrank(governor);

        mapleGlobals.setMapleTreasury(treasury);
        mapleGlobals.setValidInstanceOf("RECAPITALIZATION_CLAIMER", claimer, true);

        mapleGlobals.scheduleCall(
            address(mapleToken),
            "MT:ADD_MODULE",
            abi.encodeWithSelector(IMapleToken.addModule.selector, address(emergencyModule))
        );

        mapleToken.addModule(address(emergencyModule));

        mapleGlobals.scheduleCall(
            address(mapleToken),
            "MT:ADD_MODULE",
            abi.encodeWithSelector(IMapleToken.addModule.selector, address(recapitalizationModule))
        );

        mapleToken.addModule(address(recapitalizationModule));

        mapleGlobals.setDefaultTimelockParameters(7 days, 2 days);

        vm.stopPrank();
    }

    function setupHandlers() internal {
        bytes4[] memory selectors = new bytes4[](5);

        selectors[0] = ModuleHandler.warp.selector;
        selectors[1] = ModuleHandler.claim.selector;
        selectors[2] = ModuleHandler.schedule.selector;
        selectors[3] = ModuleHandler.emergencyMint.selector;
        selectors[4] = ModuleHandler.emergencyBurn.selector;

        uint256[] memory weights = new uint256[](5);

        weights[0] = 120;
        weights[1] = 60;
        weights[2] = 10;
        weights[3] = 5;
        weights[4] = 5;

        moduleHandler       = new ModuleHandler(mapleGlobals, mapleToken, emergencyModule, recapitalizationModule, claimer);
        distributionHandler = new DistributionHandler(address(moduleHandler), selectors, weights);

        targetContract(address(distributionHandler));
    }

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /**************************************************************************************************************************************/

    function statefulFuzz_assertInvariants() external {
        assert_recapitalizationModule_invariant_A(recapitalizationModule);
        assert_recapitalizationModule_invariant_B(recapitalizationModule);
        assert_recapitalizationModule_invariant_C(recapitalizationModule);
        assert_recapitalizationModule_invariant_D(recapitalizationModule);
        assert_recapitalizationModule_invariant_E(recapitalizationModule);
        assert_recapitalizationModule_invariant_F(recapitalizationModule);
        assert_recapitalizationModule_invariant_G(recapitalizationModule);
        assert_recapitalizationModule_invariant_H(recapitalizationModule, moduleHandler.blockTimestamp());
        assert_recapitalizationModule_invariant_I(recapitalizationModule);
    }

}

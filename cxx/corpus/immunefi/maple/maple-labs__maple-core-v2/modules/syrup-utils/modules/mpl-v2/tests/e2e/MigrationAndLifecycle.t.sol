// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IMigrator } from "../../modules/migrator/contracts/interfaces/IMigrator.sol";

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IEmergencyModule }        from "../../contracts/interfaces/IEmergencyModule.sol";
import { IMapleToken }             from "../../contracts/interfaces/IMapleToken.sol";
import { IRecapitalizationModule } from "../../contracts/interfaces/IRecapitalizationModule.sol";

import { EmergencyModule }        from "../../contracts/EmergencyModule.sol";
import { MapleToken }             from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer }  from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }        from "../../contracts/MapleTokenProxy.sol";
import { RecapitalizationModule } from "../../contracts/RecapitalizationModule.sol";

import { RecapitalizationModuleHealthChecker } from "../health-checkers/RecapitalizationModuleHealthChecker.sol";

import { DistributionHandler } from "../invariants/DistributionHandler.sol";
import { ModuleHandler }       from "../invariants/ModuleHandler.sol";
import { ModuleInvariants }    from "../invariants/ModuleInvariants.sol";

import { IGlobalsLike, IXmplLike } from "../utils/Interfaces.sol";
import { console }                 from "../utils/TestBase.sol";

contract LifecycleBase is ModuleInvariants {

    uint256 constant OLD_SUPPLY    = 10_000_000e18;
    uint256 constant ACTIONS_COUNT = 20;

    address constant XMPL      = 0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c;
    address constant OLD_TOKEN = 0x33349B282065b0284d756F0577FB39c158F935e6;

    address _claimer;
    address _governor;
    address _migratorAddress;
    address _treasury;

    uint256 start;

    // Note using `_` prefix to not clash with address registry variables.
    IGlobalsLike            _globals;
    IMapleToken             _token;
    IMigrator               _migrator;
    IEmergencyModule        _emergencyModule;
    IRecapitalizationModule _recapitalizationModule;

    DistributionHandler _distributionHandler;
    ModuleHandler       _moduleHandler;

    IMapleToken oldToken = IMapleToken(OLD_TOKEN);
    IXmplLike   _xmpl    = IXmplLike(XMPL);

    RecapitalizationModuleHealthChecker healthChecker;

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

        _moduleHandler       = new ModuleHandler(_globals, _token, _emergencyModule, _recapitalizationModule, _claimer);
        _distributionHandler = new DistributionHandler(address(_moduleHandler), selectors, weights);
    }

    function runLifecycle(uint256 seed) internal {
        // Perform some actions before asserting the invariants
        for (uint i = 0; i < ACTIONS_COUNT; i++) {
            _distributionHandler.entryPoint(uint256(keccak256(abi.encode(seed, i, "weight"))), uint256(keccak256(abi.encode(seed, i))));
        }

        // Check module invariants.
        assert_recapitalizationModule_invariant_A(_recapitalizationModule);
        assert_recapitalizationModule_invariant_B(_recapitalizationModule);
        assert_recapitalizationModule_invariant_C(_recapitalizationModule);
        assert_recapitalizationModule_invariant_D(_recapitalizationModule);
        assert_recapitalizationModule_invariant_E(_recapitalizationModule);
        assert_recapitalizationModule_invariant_F(_recapitalizationModule);
        assert_recapitalizationModule_invariant_G(_recapitalizationModule);
        assert_recapitalizationModule_invariant_H(_recapitalizationModule, _moduleHandler.blockTimestamp());
        assert_recapitalizationModule_invariant_I(_recapitalizationModule);

        // Check health checker invariants.
        RecapitalizationModuleHealthChecker.Invariants memory invariants = healthChecker.checkInvariants(_recapitalizationModule);

        assertTrue(invariants.invariantA, "Invariant A");
        assertTrue(invariants.invariantB, "Invariant B");
        assertTrue(invariants.invariantC, "Invariant C");
        assertTrue(invariants.invariantD, "Invariant D");
        assertTrue(invariants.invariantE, "Invariant E");
        assertTrue(invariants.invariantF, "Invariant F");
        assertTrue(invariants.invariantG, "Invariant G");
        assertTrue(invariants.invariantH, "Invariant H");
        assertTrue(invariants.invariantI, "Invariant I");
    }

}

contract xMPLMigration is LifecycleBase {

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 17622100);

        _claimer         = makeAddr("claimer");
        _governor        = makeAddr("governor");
        _migratorAddress = makeAddr("migrator");
        _treasury        = makeAddr("treasury");

        _globals  = IGlobalsLike(address(new NonTransparentProxy(_governor, deployGlobals())));
        _token    = IMapleToken(address(new MapleTokenProxy(address(_globals), address(new MapleToken()), address(new MapleTokenInitializer()), _migratorAddress)));
        _migrator = IMigrator(deployMigrator(address(oldToken), address(_token)));

        _emergencyModule        = new EmergencyModule(address(_globals), address(_token));
        _recapitalizationModule = new RecapitalizationModule(address(_token));

        healthChecker = new RecapitalizationModuleHealthChecker();

        configureContracts();
        setupHandlers();

        start = block.timestamp;
    }

    function test_e2e_lifecycle(uint256 seed) external {
        migrateXmpl();
        runLifecycle(seed);
    }

    /**************************************************************************************************************************************/
    /*** Helper Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function migrateXmpl() internal {
        address owner = _xmpl.owner();
        // Schedule migration on xMPL contract
        vm.prank(owner);
        _xmpl.scheduleMigration(address(_migrator), address(_token));

        vm.warp(start + 864000 + 1 seconds);

        vm.prank(owner);
        _xmpl.performMigration();
    }

    function deployMigrator(address oldToken_, address newToken_) internal returns (address migratorAddress_) {
        address deployedAddress = deployCode("Migrator.sol", abi.encode(oldToken_, newToken_));
        migratorAddress_ = _migratorAddress;

        // Using etch to always get a deterministic address for the migrator
        vm.etch(migratorAddress_, deployedAddress.code);
    }

    function configureContracts() internal {
        vm.startPrank(_governor);

        _globals.setMapleTreasury(_treasury);
        _globals.setValidInstanceOf("RECAPITALIZATION_CLAIMER", _claimer, true);

        _globals.scheduleCall(
            address(_token),
            "MT:ADD_MODULE",
            abi.encodeWithSelector(IMapleToken.addModule.selector, address(_emergencyModule))
        );

        _token.addModule(address(_emergencyModule));

        _globals.scheduleCall(
            address(_token),
            "MT:ADD_MODULE",
            abi.encodeWithSelector(IMapleToken.addModule.selector, address(_recapitalizationModule))
        );

        _token.addModule(address(_recapitalizationModule));

        _globals.setDefaultTimelockParameters(7 days, 2 days);

        vm.stopPrank();
    }

}

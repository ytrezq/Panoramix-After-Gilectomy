// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test } from "../../modules/forge-std/src/Test.sol";
import { MockERC20 }                 from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { IERC20Like, IERC4626Like } from "../../contracts/interfaces/Interfaces.sol";

import { MapleStrategyFactory } from "../../contracts/proxy/MapleStrategyFactory.sol";

import { MapleAaveStrategyInitializer }  from "../../contracts/proxy/aaveStrategy/MapleAaveStrategyInitializer.sol";
import { MapleBasicStrategyInitializer } from "../../contracts/proxy/basicStrategy/MapleBasicStrategyInitializer.sol";
import { MapleSkyStrategyInitializer }   from "../../contracts/proxy/skyStrategy/MapleSkyStrategyInitializer.sol";

import { MapleBasicStrategy } from "../../contracts/MapleBasicStrategy.sol";
import { MapleSkyStrategy }   from "../../contracts/MapleSkyStrategy.sol";

import { MapleAaveStrategyHarness } from "./Harnesses.sol";

import {
    MockAavePool,
    MockAaveToken,
    MockAaveRewardsController,
    MockFactory,
    MockGlobals,
    MockPool,
    MockPoolManager,
    MockPSM,
    MockVault
} from "./Mocks.sol";

contract TestBase is Test {

    address internal governor         = makeAddr("governor");
    address internal lp               = makeAddr("lp");
    address internal operationalAdmin = makeAddr("operationalAdmin");
    address internal poolDelegate     = makeAddr("poolDelegate");
    address internal securityAdmin    = makeAddr("securityAdmin");
    address internal strategyManager  = makeAddr("strategyManager");
    address internal treasury         = makeAddr("treasury");

    address internal implementation;
    address internal initializer;

    MockERC20       internal asset;
    MockGlobals     internal globals;
    MockFactory     internal poolManagerFactory;
    MockPool        internal pool;
    MockPoolManager internal poolManager;

    MapleStrategyFactory internal factory;

    function setUp() public virtual {
        // Create all mocks.
        asset              = new MockERC20("USD Coin", "USDC", 6);
        globals            = new MockGlobals(address(governor));
        pool               = new MockPool("Maple Pool", "MP-USDC", 6, address(asset), poolDelegate);
        poolManager        = new MockPoolManager(address(pool), poolDelegate, address(globals));
        poolManagerFactory = new MockFactory();

        pool.__setPoolManager(address(poolManager));

        poolManager.__setFactory(address(poolManagerFactory));

        poolManagerFactory.__setIsInstance(true);

        globals.__setCanDeploy(true);
        globals.__setIsInstanceOf(true);
        globals.__setOperationalAdmin(operationalAdmin);
        globals.__setSecurityAdmin(securityAdmin);
        globals.__setMapleTreasury(treasury);

        factory = new MapleStrategyFactory(address(globals));
    }

}

contract BasicStrategyTestBase is TestBase {

    event StrategyDeactivated();
    event StrategyFeesCollected(uint256 feeAmount);
    event StrategyFeeRateSet(uint256 feeRate);
    event StrategyFunded(uint256 assetsIn, uint256 shares);
    event StrategyImpaired();
    event StrategyReactivated(bool updateAccounting);
    event StrategyWithdrawal(uint256 assets, uint256 shares);

    MapleBasicStrategy internal strategy;
    MockVault          internal vault;

    function setUp() public virtual override {
        super.setUp();

        implementation = address(new MapleBasicStrategy());
        initializer    = address(new MapleBasicStrategyInitializer());

        vm.startPrank(governor);
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        vault = new MockVault(address(asset));

        // Create the strategy instance.
        strategy = MapleBasicStrategy(factory.createInstance({
            arguments_: abi.encode(address(poolManager), address(vault)),
            salt_:      "SALT"
        }));

    }

    function currentTotalAssets() internal view returns (uint256) {
        return IERC4626Like(address(vault)).convertToAssets(IERC20Like(address(vault)).balanceOf(address(strategy)));
    }

}

contract SkyStrategyTestBase is TestBase {

    event PsmSet(address indexed psm);
    event StrategyDeactivated();
    event StrategyFeesCollected(uint256 fee);
    event StrategyFeeRateSet(uint256 feeRate);
    event StrategyFunded(uint256 assetsIn, uint256 shares);
    event StrategyImpaired();
    event StrategyReactivated(bool updateAccounting);
    event StrategyWithdrawal(uint256 assetsOut, uint256 shares);

    uint256 internal tin  = 0.01e18;
    uint256 internal tout = 0.02e18;

    MapleSkyStrategy  strategy;
    MockPSM           psm;
    MockVault         vault;
    MockERC20         usds;

    function setUp() public virtual override {
        super.setUp();

        implementation = address(new MapleSkyStrategy());
        initializer    = address(new MapleSkyStrategyInitializer());

        vm.startPrank(governor);
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        psm   = new MockPSM();
        usds  = new MockERC20("usds", "USDS", 18);
        vault = new MockVault(address(usds));

        psm.__setUsds(address(usds));
        psm.__setGem(address(asset));
        psm.__setTin(tin);
        psm.__setTout(tout);

        //Create the strategy instance.
        strategy = MapleSkyStrategy(factory.createInstance({
            arguments_: abi.encode(address(poolManager), address(vault), address(psm)),
            salt_:      "SALT"
        }));
    }

    function _gemForUsds(uint256 usdsAmount_) internal view returns (uint256 gemAmount_) {
        uint256 tout_ = MockPSM(psm).tout();
        uint256 to18ConversionFactor_ = MockPSM(psm).to18ConversionFactor();

        // Inverse of the previous calculation
        gemAmount_ = (usdsAmount_ * 1e18) / (to18ConversionFactor_ * (1e18 + tout_));
    }

    function _usdsForGem(uint256 gemAmount_) internal view returns (uint256 usdsAmount_) {
        uint256 tout_ = MockPSM(psm).tout();
        uint256 to18ConversionFactor_ = MockPSM(psm).to18ConversionFactor();

        usdsAmount_ = (gemAmount_  * to18ConversionFactor_ * (1e18 + tout_)) / 1e18;
    }

    function currentTotalAssets() internal view returns (uint256) {
        return _gemForUsds(IERC4626Like(address(vault)).convertToAssets(IERC20Like(address(vault)).balanceOf(address(strategy))));
    }

}

contract AaveStrategyTestBase is TestBase {

    event RewardsClaimed(address indexed rewardToken, uint256 amount);
    event StrategyDeactivated();
    event StrategyFeesCollected(uint256 fee);
    event StrategyFeeRateSet(uint256 feeRate);
    event StrategyFunded(uint256 assetsIn);
    event StrategyImpaired();
    event StrategyReactivated(bool updateAccounting);
    event StrategyWithdrawal(uint256 assetsOut);

    MockAavePool                 aavePool;
    MockAaveRewardsController    aaveRewardsController;
    MockAaveToken                aaveToken;

    MapleAaveStrategyHarness strategy;

    function setUp() public virtual override {
        super.setUp();

        implementation = address(new MapleAaveStrategyHarness());
        initializer    = address(new MapleAaveStrategyInitializer());

        aaveRewardsController = new MockAaveRewardsController();
        aavePool              = new MockAavePool();
        aaveToken             = new MockAaveToken(address(aavePool), address(asset), address(aaveRewardsController));

        vm.startPrank(governor);
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        // Create the strategy instance.
        strategy = MapleAaveStrategyHarness(factory.createInstance({
            arguments_: abi.encode(address(poolManager), address(aaveToken)),
            salt_:      "SALT"
        }));
    }

}

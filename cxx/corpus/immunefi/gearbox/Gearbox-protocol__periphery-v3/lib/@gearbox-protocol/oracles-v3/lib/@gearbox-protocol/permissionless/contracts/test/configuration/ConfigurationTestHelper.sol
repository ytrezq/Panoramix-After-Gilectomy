// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestKeys} from "../helpers/TestKeys.sol";

import {CrossChainMultisig, CrossChainCall} from "../../global/CrossChainMultisig.sol";
import {InstanceManager} from "../../instance/InstanceManager.sol";
import {PriceFeedStore} from "../../instance/PriceFeedStore.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";
import {ICreditConfigureActions} from "../../factories/CreditFactory.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "@gearbox-protocol/core-v3/contracts/test/mocks/token/ERC20Mock.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {MockLossPolicy} from "../mocks/MockLossPolicy.sol";

import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";

import {VmSafe} from "forge-std/Vm.sol";

import {
    AP_PRICE_FEED_STORE,
    AP_INSTANCE_MANAGER_PROXY,
    AP_INTEREST_RATE_MODEL_FACTORY,
    AP_CREDIT_FACTORY,
    AP_POOL_FACTORY,
    AP_PRICE_ORACLE_FACTORY,
    AP_RATE_KEEPER_FACTORY,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_LOSS_POLICY_FACTORY,
    AP_GOVERNOR,
    AP_POOL,
    AP_POOL_QUOTA_KEEPER,
    AP_PRICE_ORACLE,
    AP_MARKET_CONFIGURATOR,
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    AP_INTEREST_RATE_MODEL_LINEAR,
    AP_RATE_KEEPER_TUMBLER,
    AP_RATE_KEEPER_GAUGE,
    AP_CREDIT_MANAGER,
    AP_CREDIT_FACADE,
    AP_CREDIT_CONFIGURATOR,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";

import {DeployParams} from "../../interfaces/Types.sol";
import {CreditFacadeParams, CreditManagerParams} from "../../factories/CreditFactory.sol";

import {GlobalSetup} from "../helpers/GlobalSetup.sol";
import {MarketConfigurator} from "../../market/MarketConfigurator.sol";
import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";

contract ConfigurationTestHelper is Test, GlobalSetup {
    address public admin;
    address public emergencyAdmin;

    address public WETH;
    address public USDC;
    address public GEAR;
    address public CHAINLINK_ETH_USD;
    address public CHAINLINK_USDC_USD;

    string constant name = "Test Market ETH";
    string constant symbol = "dETH";

    MarketConfigurator public marketConfigurator;
    address public addressProvider;

    IPoolV3 public pool;
    ICreditManagerV3 public creditManager;
    ICreditFacadeV3 public creditFacade;
    ICreditConfiguratorV3 public creditConfigurator;

    address public instanceOwner;
    VmSafe.Wallet internal bytecodeAuthor;
    VmSafe.Wallet internal auditor;

    function setUp() public virtual {
        vm.chainId(1);

        TestKeys testKeys = new TestKeys();

        bytecodeAuthor = testKeys.bytecodeAuthor();
        auditor = testKeys.auditor();

        _deployGlobalContracts(
            testKeys.initialSigners(),
            bytecodeAuthor,
            auditor,
            "Initial Auditor",
            testKeys.threshold(),
            testKeys.dao().addr
        );
        _deployMockTokens();

        instanceOwner = testKeys.instanceOwner().addr;

        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = _generateActivateCall(1, instanceOwner, makeAddr("TREASURY"), WETH, GEAR);
        _submitBatchAndSign("Activate instance", calls);

        _setupPriceFeedStore();

        _addMockLossPolicy();

        admin = makeAddr("admin");
        emergencyAdmin = makeAddr("emergencyAdmin");

        addressProvider = instanceManager.addressProvider();

        address mcf =
            IAddressProvider(addressProvider).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        vm.prank(admin);
        marketConfigurator = MarketConfigurator(
            MarketConfiguratorFactory(mcf).createMarketConfigurator(emergencyAdmin, address(0), "Test Curator", false)
        );

        pool = IPoolV3(_deployTestPool());
        creditManager = ICreditManagerV3(_deployTestCreditSuite());
        creditFacade = ICreditFacadeV3(creditManager.creditFacade());
        creditConfigurator = ICreditConfiguratorV3(creditManager.creditConfigurator());
    }

    function _isTestMode() internal pure virtual override returns (bool) {
        return true;
    }

    function _deployMockTokens() internal {
        // Deploy mock tokens
        WETH = address(new ERC20Mock("Mock WETH", "WETH", 18));
        USDC = address(new ERC20Mock("Mock USDC", "USDC", 6));
        GEAR = address(new ERC20Mock("Mock GEAR", "GEAR", 18));

        // Mint initial supply
        ERC20Mock(WETH).mint(address(this), 1000000 ether);
        ERC20Mock(USDC).mint(address(this), 1000000000 * 10 ** 6);
        ERC20Mock(GEAR).mint(address(this), 1000000 ether);

        // Deploy mock price feeds
        CHAINLINK_ETH_USD = address(new MockPriceFeed());
        CHAINLINK_USDC_USD = address(new MockPriceFeed());

        // Set initial prices
        MockPriceFeed(CHAINLINK_ETH_USD).setPrice(2000 * 10 ** 8); // $2000
        MockPriceFeed(CHAINLINK_USDC_USD).setPrice(1 * 10 ** 8); // $1
    }

    function _setupPriceFeedStore() internal {
        _addPriceFeed(instanceOwner, CHAINLINK_ETH_USD, 1 days, "ETH/USD");
        _addPriceFeed(instanceOwner, CHAINLINK_USDC_USD, 1 days, "USDC/USD");

        _allowPriceFeed(instanceOwner, WETH, CHAINLINK_ETH_USD);
        _allowPriceFeed(instanceOwner, USDC, CHAINLINK_USDC_USD);
    }

    function _addMockLossPolicy() internal {
        CrossChainCall[] memory calls = new CrossChainCall[](1);

        bytes32 bytecodeHash = _uploadByteCodeAndSign(
            bytecodeAuthor, auditor, type(MockLossPolicy).creationCode, "LOSS_POLICY::MOCK", 3_10
        );

        calls[0] = _generateAllowPublicContractCall(bytecodeHash);

        _submitBatchAndSign("Allow public contracts", calls);
    }

    function _deployTestPool() internal returns (address) {
        IERC20(WETH).transfer(address(marketConfigurator), 1e18);

        address _pool = marketConfigurator.previewCreateMarket(3_10, WETH, name, symbol);

        DeployParams memory interestRateModelParams = DeployParams({
            postfix: "LINEAR", salt: 0, constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
        });
        DeployParams memory rateKeeperParams =
            DeployParams({postfix: "TUMBLER", salt: 0, constructorParams: abi.encode(_pool, 7 days)});
        DeployParams memory lossPolicyParams =
            DeployParams({postfix: "MOCK", salt: 0, constructorParams: abi.encode(_pool, addressProvider)});

        vm.prank(admin);
        _pool = marketConfigurator.createMarket({
            minorVersion: 3_10,
            underlying: WETH,
            name: name,
            symbol: symbol,
            interestRateModelParams: interestRateModelParams,
            rateKeeperParams: rateKeeperParams,
            lossPolicyParams: lossPolicyParams,
            underlyingPriceFeed: CHAINLINK_ETH_USD
        });

        return _pool;
    }

    function _deployTestCreditSuite() internal returns (address) {
        DeployParams memory accountFactoryParams =
            DeployParams({postfix: "DEFAULT", salt: 0, constructorParams: abi.encode(addressProvider)});

        CreditManagerParams memory creditManagerParams = CreditManagerParams({
            maxEnabledTokens: 4,
            feeInterest: 10_00,
            feeLiquidation: 1_50,
            liquidationPremium: 1_50,
            feeLiquidationExpired: 1_50,
            liquidationPremiumExpired: 1_50,
            minDebt: 1e18,
            maxDebt: 20e18,
            name: "Credit Manager ETH",
            accountFactoryParams: accountFactoryParams
        });

        CreditFacadeParams memory facadeParams =
            CreditFacadeParams({degenNFT: address(0), expirable: false, migrateBotList: false});

        bytes memory creditSuiteParams = abi.encode(creditManagerParams, facadeParams);

        vm.prank(admin);
        return marketConfigurator.createCreditSuite(3_10, address(pool), creditSuiteParams);
    }

    function _addUSDC() internal {
        vm.prank(admin);
        marketConfigurator.addToken(address(pool), USDC, CHAINLINK_USDC_USD);
    }
}

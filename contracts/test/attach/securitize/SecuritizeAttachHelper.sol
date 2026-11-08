// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {AttachBase} from "@gearbox-protocol/permissionless/contracts/test/suite/AttachBase.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

import {
    SecuritizeOnRampAdapter
} from "@gearbox-protocol/integrations-v3/contracts/adapters/securitize/SecuritizeOnRampAdapter.sol";
import {
    SecuritizeRedemptionGatewayAdapter
} from "@gearbox-protocol/integrations-v3/contracts/adapters/securitize/SecuritizeRedemptionGatewayAdapter.sol";
import {
    SecuritizeLiquidator
} from "@gearbox-protocol/integrations-v3/contracts/helpers/securitize/SecuritizeLiquidator.sol";
import {
    SecuritizeRedemptionGateway
} from "@gearbox-protocol/integrations-v3/contracts/helpers/securitize/SecuritizeRedemptionGateway.sol";
import {
    SecuritizeRedemptionPhantomToken
} from "@gearbox-protocol/integrations-v3/contracts/helpers/securitize/SecuritizeRedemptionPhantomToken.sol";
import {
    ISecuritizeNAVProvider
} from "@gearbox-protocol/integrations-v3/contracts/integrations/securitize/ISecuritizeNAVProvider.sol";
import {
    ISecuritizeOnRamp
} from "@gearbox-protocol/integrations-v3/contracts/integrations/securitize/ISecuritizeOnRamp.sol";
import {ERC4626UnderlyingZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/ERC4626UnderlyingZapper.sol";

import {ISecuritizeDegenNFT} from "../../../interfaces/ISecuritizeDegenNFT.sol";
import {ISecuritizeRWAFactory} from "../../../interfaces/ISecuritizeRWAFactory.sol";
import {IDSRegistryService} from "../../../interfaces/external/securitize/IDSRegistryService.sol";
import {IDSServiceConsumer} from "../../../interfaces/external/securitize/IDSServiceConsumer.sol";
import {IDSTrustService} from "../../../interfaces/external/securitize/IDSTrustService.sol";
import {IVaultRegistrar} from "../../../interfaces/external/securitize/IVaultRegistrar.sol";

import {DefaultRWAUnderlying} from "../../../rwa/DefaultRWAUnderlying.sol";
import {MonopolizedOnDemandLP} from "../../../rwa/MonopolizedOnDemandLP.sol";
import {OnDemandRWAUnderlying} from "../../../rwa/OnDemandRWAUnderlying.sol";
import {SecuritizeDegenNFT} from "../../../rwa/SecuritizeDegenNFT.sol";
import {SecuritizeRWAFactory} from "../../../rwa/SecuritizeRWAFactory.sol";

import {MockDSToken} from "./mocks/MockDSToken.sol";
import {MockVaultRegistrar} from "./mocks/MockVaultRegistrar.sol";

contract SecuritizeAttachHelper is AttachBase {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDC_DONOR = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    function _setUpBytecode() internal {
        _addPublicDomain("RWA_FACTORY");
        _addPublicDomain("RWA_LIQUIDATOR");
        _addPublicDomain("RWA_UNDERLYING");
        _addPublicDomain("ON_DEMAND_LP");

        _uploadContract("DEGEN_NFT::SECURITIZE", 3_10, type(SecuritizeDegenNFT).creationCode);
        _uploadContract("RWA_FACTORY::SECURITIZE", 3_10, type(SecuritizeRWAFactory).creationCode);
        _uploadContract("RWA_UNDERLYING::DEFAULT", 3_10, type(DefaultRWAUnderlying).creationCode);
        _uploadContract("RWA_UNDERLYING::ON_DEMAND", 3_10, type(OnDemandRWAUnderlying).creationCode);
        _uploadContract("ON_DEMAND_LP::MONOPOLIZED", 3_10, type(MonopolizedOnDemandLP).creationCode);
        _uploadContract("ADAPTER::SECURITIZE_ONRAMP", 3_10, type(SecuritizeOnRampAdapter).creationCode);
        _uploadContract("ADAPTER::SECURITIZE_REDEMPTION", 3_10, type(SecuritizeRedemptionGatewayAdapter).creationCode);
        _uploadContract("RWA_LIQUIDATOR::SECURITIZE", 3_10, type(SecuritizeLiquidator).creationCode);
        _uploadContract("GATEWAY::SECURITIZE_REDEMPTION", 3_10, type(SecuritizeRedemptionGateway).creationCode);
        _uploadContract("PHANTOM_TOKEN::SECURITIZE_RD", 3_10, type(SecuritizeRedemptionPhantomToken).creationCode);
        _uploadContract("ZAPPER::ERC4626_UNDERLYING", 3_10, type(ERC4626UnderlyingZapper).creationCode);
    }

    // ---------- //
    // SECURITIZE //
    // ---------- //

    address public securitize;
    address public factory;
    address public degenNFT;
    address public liquidator;

    struct DSToken {
        address token;
        address registrar;
        address priceFeed;
        address navProvider;
        address onRamp;
        address redemptionWallet;
        address redemptionGateway;
        address redemptionPhantomToken;
    }

    DSToken[] public dsTokens;
    uint256 public idx;

    modifier repeatTestForEachDSToken() {
        for (idx; idx < dsTokens.length; ++idx) {
            uint256 snapshot = vm.snapshotState();
            string memory symbol = ERC20(dsTokens[idx].token).symbol();
            console.log("Running test for", symbol);
            _;
            console.log("Test for", symbol, "completed");
            vm.revertToStateAndDelete(snapshot);
        }
    }

    function _attachSecuritize() internal {
        factory = _deploy("RWA_FACTORY::SECURITIZE", 3_10, abi.encode(addressProvider, securitize));
        degenNFT = ISecuritizeRWAFactory(factory).getDegenNFT();
        liquidator = _deploy("RWA_LIQUIDATOR::SECURITIZE", 3_10, abi.encode(factory));

        _addPriceFeed(USDC_PRICE_FEED, 1 days, "Chainlink USDC price feed");
        _allowPriceFeed(USDC, USDC_PRICE_FEED);

        address[] memory registrars = vm.envOr("VAULT_REGISTRAR", ",", new address[](0));
        if (registrars.length != 0) {
            for (uint256 i; i < registrars.length; ++i) {
                dsTokens.push(_attachWithLiveContracts(registrars[i]));
            }
        } else {
            address[] memory tokens = vm.envOr("DS_TOKEN", ",", new address[](0));
            if (tokens.length != 0) {
                for (uint256 i; i < tokens.length; ++i) {
                    _omniPrank(deployer);
                    address registrar = address(new MockVaultRegistrar(securitize, tokens[i]));
                    dsTokens.push(_attachWithLiveContracts(registrar));
                }
            } else {
                dsTokens.push(_attachWithMockContracts());
            }
        }
    }

    function _attachWithMockContracts() internal returns (DSToken memory dsToken) {
        _startOmniPrank(deployer);
        dsToken.token = address(new MockDSToken(securitize));
        dsToken.registrar = address(new MockVaultRegistrar(securitize, dsToken.token));
        _stopOmniPrank();

        _startOmniPrank(securitize);
        MockDSToken(dsToken.token).setRegistrar(dsToken.registrar, true);
        IVaultRegistrar(dsToken.registrar).addOperator(degenNFT);
        _stopOmniPrank();

        dsToken.priceFeed = onePriceFeed;
        _allowPriceFeed(dsToken.token, onePriceFeed);
        _configureLocal(degenNFT, abi.encodeCall(ISecuritizeDegenNFT.addRegistrar, (dsToken.registrar)));
        _configureLocal(
            degenNFT,
            abi.encodeCall(ISecuritizeDegenNFT.setOperatorStatus, (dsToken.token, dsToken.redemptionGateway, true))
        );
    }

    function _attachWithLiveContracts(address registrar) internal returns (DSToken memory dsToken) {
        dsToken.token = IVaultRegistrar(registrar).token();
        dsToken.registrar = registrar;

        address registryService =
            IDSServiceConsumer(dsToken.token).getDSService(IDSServiceConsumer(dsToken.token).REGISTRY_SERVICE());
        address trustService =
            IDSServiceConsumer(dsToken.token).getDSService(IDSServiceConsumer(dsToken.token).TRUST_SERVICE());
        address master = address(uint160(uint256(vm.load(trustService, bytes32(0)))));
        _omniPrank(master);
        IDSTrustService(trustService).setServiceOwner(securitize);

        _startOmniPrank(securitize);
        IDSTrustService(trustService).setRole(registrar, IDSTrustService(trustService).TRANSFER_AGENT());
        IVaultRegistrar(registrar).addOperator(degenNFT);
        _stopOmniPrank();

        (dsToken.onRamp, dsToken.redemptionWallet, dsToken.navProvider, dsToken.priceFeed) =
            _getDSTokenInfo(dsToken.token);

        dsToken.redemptionGateway = _deploy(
            "GATEWAY::SECURITIZE_REDEMPTION",
            3_10,
            abi.encode(
                dsToken.token,
                USDC,
                dsToken.redemptionWallet,
                degenNFT,
                liquidator,
                dsToken.navProvider,
                registryService
            )
        );
        dsToken.redemptionPhantomToken =
            _deploy("PHANTOM_TOKEN::SECURITIZE_RD", 3_10, abi.encode(dsToken.redemptionGateway));

        _addPriceFeed(dsToken.priceFeed, 1 days, "Redstone DSToken / USD price feed");
        _allowPriceFeed(dsToken.token, dsToken.priceFeed);
        _allowPriceFeed(dsToken.redemptionPhantomToken, USDC_PRICE_FEED);
        _configureLocal(degenNFT, abi.encodeCall(ISecuritizeDegenNFT.addRegistrar, (registrar)));
        _configureLocal(
            degenNFT,
            abi.encodeCall(ISecuritizeDegenNFT.setOperatorStatus, (dsToken.token, dsToken.redemptionGateway, true))
        );
    }

    function _getDSTokenInfo(address token)
        internal
        returns (address onRamp, address redemptionWallet, address navProvider, address priceFeed)
    {
        string[] memory command = new string[](2);
        command[0] = "script/get-securitize-token-info.sh";
        command[1] = ERC20(token).symbol();
        string memory result = string(vm.ffi(command));
        onRamp = vm.parseJsonAddress(result, ".onRamp");
        redemptionWallet = vm.parseJsonAddress(result, ".redemptionWallet");
        navProvider = ISecuritizeOnRamp(onRamp).navProvider();
        priceFeed = ISecuritizeNAVProvider(navProvider).priceFeed();
    }

    function _registerInvestor(address investor, DSToken memory dsToken) internal {
        address registryService =
            IDSServiceConsumer(dsToken.token).getDSService(IDSServiceConsumer(dsToken.token).REGISTRY_SERVICE());

        _startOmniPrank(securitize);
        IDSRegistryService(registryService).registerInvestor("Fake investor", "Fake collision hash");
        IDSRegistryService(registryService).addWallet(investor, "Fake investor");
        IDSRegistryService(registryService).setCountry("Fake investor", "US");
        IDSRegistryService(registryService)
            .setAttribute(
                "Fake investor",
                IDSRegistryService(registryService).ACCREDITED(),
                IDSRegistryService(registryService).APPROVED(),
                type(uint256).max,
                "Fake proof"
            );
        _stopOmniPrank();
    }

    function _signRegisterVaultMessage(VmSafe.Wallet memory investor, DSToken memory dsToken)
        internal
        view
        returns (ISecuritizeDegenNFT.RegisterMessage memory message)
    {
        bytes32 domainSeparator = _buildDomainSeparator(dsToken.registrar);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "RegisterVault(address investor,address operator,address token,uint256 nonce,uint256 deadline)"
                ),
                investor.addr,
                degenNFT,
                dsToken.token,
                IVaultRegistrar(dsToken.registrar).operatorNonce(investor.addr, degenNFT),
                type(uint256).max
            )
        );
        return ISecuritizeDegenNFT.RegisterMessage({
            token: dsToken.token,
            signature: ISecuritizeDegenNFT.Signature({
                deadline: type(uint256).max, signature: _sign(investor, domainSeparator, structHash)
            })
        });
    }

    function _convertFromUSDC(uint256 usdcAmount, DSToken memory dsToken)
        internal
        view
        returns (uint256 dsTokenAmount)
    {
        uint256 dsTokenScale = 10 ** ERC20(dsToken.token).decimals();
        uint256 usdcScale = 10 ** ERC20(USDC).decimals();
        (, int256 dsTokenPrice,,,) = IPriceFeed(dsToken.priceFeed).latestRoundData();
        (, int256 usdcPrice,,,) = IPriceFeed(USDC_PRICE_FEED).latestRoundData();
        dsTokenAmount = usdcAmount * (uint256(dsTokenPrice) * dsTokenScale) / (uint256(usdcPrice) * usdcScale);
    }

    // ------- //
    // MARKETS //
    // ------- //

    function _createMarketWithDefaultRWAUnderlying()
        internal
        returns (address underlying, address pool, address[] memory creditManagers, address zapper)
    {
        underlying = _deploy(
            "RWA_UNDERLYING::DEFAULT", 3_10, abi.encode(addressProvider, factory, USDC, "Default compliant ", "dc")
        );
        _allowPriceFeed(underlying, USDC_PRICE_FEED);

        // NOTE: sending small amount of underlying to market configurator to mint dead pool shares
        _startOmniPrank(riskCurator);
        ERC20(USDC).approve(underlying, 1e5);
        ERC4626(underlying).deposit(1e5, address(marketConfigurator));
        _stopOmniPrank();

        MarketParams memory marketParams = _getDefaultMarketParams(underlying);
        marketParams.underlyingPriceFeed = USDC_PRICE_FEED;
        marketParams.interestRateModelParams.constructorParams = abi.encode(5000, 9000, 4_00, 0, 0, 0, false);
        marketParams.interestRateModelParams.salt = keccak256(abi.encode(underlying));
        pool = _createMockMarket(underlying, marketParams);
        _addToken(
            pool,
            TokenParams({
                token: USDC,
                priceFeed: USDC_PRICE_FEED,
                reservePriceFeed: USDC_PRICE_FEED,
                quotaLimit: 10_000_000e6,
                quotaRate: 1
            })
        );
        for (uint256 i; i < dsTokens.length; ++i) {
            _addToken(
                pool,
                TokenParams({
                    token: dsTokens[i].token,
                    priceFeed: dsTokens[i].priceFeed,
                    reservePriceFeed: dsTokens[i].priceFeed,
                    quotaLimit: 10_000_000e6,
                    quotaRate: 1
                })
            );
            if (dsTokens[i].redemptionPhantomToken == address(0)) continue;
            _addToken(
                pool,
                TokenParams({
                    token: dsTokens[i].redemptionPhantomToken,
                    priceFeed: USDC_PRICE_FEED,
                    reservePriceFeed: USDC_PRICE_FEED,
                    quotaLimit: 10_000_000e6,
                    quotaRate: 1
                })
            );
        }
        // NOTE: updating rates also adds new tokens to the quota keeper
        _updateQuotaRates(pool);

        zapper = _deploy("ZAPPER::ERC4626_UNDERLYING", 3_10, abi.encode(pool));
        _addPeripheryContract(zapper);

        creditManagers = new address[](dsTokens.length);
        for (uint256 i; i < dsTokens.length; ++i) {
            CreditSuiteParams memory creditSuiteParams = _getDefaultCreditSuiteParams();
            creditSuiteParams.debtLimit = 1_000_000e6;
            creditSuiteParams.minDebt = 50_000e6;
            creditSuiteParams.maxDebt = 1_000_000e6;
            creditSuiteParams.degenNFT = degenNFT;
            creditSuiteParams.accountFactoryParams.salt = keccak256(abi.encode(underlying, dsTokens[i].token));
            creditManagers[i] = _createMockCreditSuite(pool, creditSuiteParams);

            _addCollateralToken(creditManagers[i], USDC, 98_00);
            _addCollateralToken(creditManagers[i], dsTokens[i].token, 90_00);
            _allowAdapter(creditManagers[i], "ERC4626_VAULT", abi.encode(creditManagers[i], underlying, address(0)));

            if (dsTokens[i].redemptionPhantomToken == address(0)) continue;
            _addCollateralToken(creditManagers[i], dsTokens[i].redemptionPhantomToken, 90_00);
            _allowAdapter(creditManagers[i], "SECURITIZE_ONRAMP", abi.encode(creditManagers[i], dsTokens[i].onRamp));
            _allowAdapter(
                creditManagers[i],
                "SECURITIZE_REDEMPTION",
                abi.encode(creditManagers[i], dsTokens[i].redemptionGateway, dsTokens[i].redemptionPhantomToken)
            );
        }
    }

    function _createMarketWithOnDemandRWAUnderlying(address depositor)
        internal
        returns (address underlying, address pool, address[] memory creditManagers, address liquidityProvider)
    {
        liquidityProvider = _deploy(
            "ON_DEMAND_LP::MONOPOLIZED", 3_10, abi.encode(addressProvider, marketConfigurator, depositor)
        );
        underlying = _deploy(
            "RWA_UNDERLYING::ON_DEMAND",
            3_10,
            abi.encode(
                addressProvider, factory, liquidityProvider, marketConfigurator, USDC, "On-demand compliant ", "oc"
            )
        );
        _allowPriceFeed(underlying, USDC_PRICE_FEED);

        // NOTE: sending small amount of underlying to market configurator to mint dead pool shares
        _startOmniPrank(riskCurator);
        ERC20(USDC).approve(underlying, 1e5);
        ERC4626(underlying).deposit(1e5, address(marketConfigurator));
        _stopOmniPrank();

        MarketParams memory marketParams = _getDefaultMarketParams(underlying);
        marketParams.underlyingPriceFeed = USDC_PRICE_FEED;
        marketParams.interestRateModelParams.constructorParams = abi.encode(5000, 9000, 4_00, 0, 0, 0, false);
        marketParams.interestRateModelParams.salt = keccak256(abi.encode(underlying));
        pool = _createMockMarket(underlying, marketParams);
        _addToken(
            pool,
            TokenParams({
                token: USDC,
                priceFeed: USDC_PRICE_FEED,
                reservePriceFeed: USDC_PRICE_FEED,
                quotaLimit: 10_000_000e6,
                quotaRate: 1
            })
        );
        for (uint256 i; i < dsTokens.length; ++i) {
            _addToken(
                pool,
                TokenParams({
                    token: dsTokens[i].token,
                    priceFeed: dsTokens[i].priceFeed,
                    reservePriceFeed: dsTokens[i].priceFeed,
                    quotaLimit: 10_000_000e6,
                    quotaRate: 1
                })
            );
            if (dsTokens[i].redemptionPhantomToken == address(0)) continue;
            _addToken(
                pool,
                TokenParams({
                    token: dsTokens[i].redemptionPhantomToken,
                    priceFeed: USDC_PRICE_FEED,
                    reservePriceFeed: USDC_PRICE_FEED,
                    quotaLimit: 10_000_000e6,
                    quotaRate: 1
                })
            );
        }
        // NOTE: updating rates also adds new tokens to the quota keeper
        _updateQuotaRates(pool);

        _startOmniPrank(riskCurator);
        OnDemandRWAUnderlying(underlying).setPool(pool);
        MonopolizedOnDemandLP(liquidityProvider).addPool(pool);
        OnDemandRWAUnderlying(underlying).setDepositorStatus(treasury, true);
        _stopOmniPrank();

        creditManagers = new address[](dsTokens.length);
        for (uint256 i; i < dsTokens.length; ++i) {
            CreditSuiteParams memory creditSuiteParams = _getDefaultCreditSuiteParams();
            creditSuiteParams.debtLimit = 1_000_000e6;
            creditSuiteParams.minDebt = 50_000e6;
            creditSuiteParams.maxDebt = 1_000_000e6;
            creditSuiteParams.degenNFT = degenNFT;
            creditSuiteParams.accountFactoryParams.salt = keccak256(abi.encode(underlying, dsTokens[i].token));
            creditManagers[i] = _createMockCreditSuite(pool, creditSuiteParams);

            _addCollateralToken(creditManagers[i], USDC, 98_00);
            _addCollateralToken(creditManagers[i], dsTokens[i].token, 90_00);
            _allowAdapter(creditManagers[i], "ERC4626_VAULT", abi.encode(creditManagers[i], underlying, address(0)));

            if (dsTokens[i].redemptionPhantomToken == address(0)) continue;
            _addCollateralToken(creditManagers[i], dsTokens[i].redemptionPhantomToken, 90_00);
            _allowAdapter(creditManagers[i], "SECURITIZE_ONRAMP", abi.encode(creditManagers[i], dsTokens[i].onRamp));
            _allowAdapter(
                creditManagers[i],
                "SECURITIZE_REDEMPTION",
                abi.encode(creditManagers[i], dsTokens[i].redemptionGateway, dsTokens[i].redemptionPhantomToken)
            );
        }
    }
}

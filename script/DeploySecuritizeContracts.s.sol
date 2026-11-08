// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {
    IUniswapV3Adapter,
    UniswapV3PoolStatus
} from "@gearbox-protocol/integrations-v3/contracts/interfaces/uniswap/IUniswapV3Adapter.sol";

import {RWACompressor} from "../contracts/compressors/RWACompressor.sol";
import {
    OnDemandRWAUnderlyingSubcompressor
} from "../contracts/compressors/subcompressors/rwa/OnDemandRWAUnderlyingSubcompressor.sol";
import {
    SecuritizeRWAFactorySubcompressor
} from "../contracts/compressors/subcompressors/rwa/SecuritizeRWAFactorySubcompressor.sol";

import {ISecuritizeDegenNFT} from "../contracts/interfaces/ISecuritizeDegenNFT.sol";
import {IDSToken} from "../contracts/interfaces/external/securitize/IDSToken.sol";

import {TYPE_RWA_COMPRESSOR} from "../contracts/libraries/AddressValidation.sol";

import {SecuritizeAttachHelper} from "../contracts/test/attach/securitize/SecuritizeAttachHelper.sol";

contract DeploySecuritizeContracts is Script, SecuritizeAttachHelper {
    address public investor;
    address public depositor;

    function run() external {
        vm.skip(ADDRESS_PROVIDER.code.length == 0, "Not in an attach mode");
        vm.skip(block.chainid != 1, "Not Ethereum mainnet");
        // NOTE: even though we compile our contracts under Shanghai EVM version,
        // more recent one is usually needed to interact with third-party contracts
        vm.setEvmVersion("osaka");

        uint256 authorPrivateKey = vm.envOr("AUTHOR_PRIVATE_KEY", uint256(0));
        require(authorPrivateKey != 0, "AUTHOR_PRIVATE_KEY is not set");
        deployer = author = auditor = riskCurator = vm.createWallet(authorPrivateKey);

        _omniPrank(USDC_DONOR);
        ERC20(USDC).transfer(riskCurator.addr, 100_000e6);
        _omniPrank(RLUSD_DONOR);
        ERC20(RLUSD).transfer(riskCurator.addr, 100_000e6);

        investor = depositor = securitize = deployer.addr;

        _setUp();
        _setUpBytecode();
        _attachSecuritize();

        for (uint256 i; i < dsTokens.length; ++i) {
            _registerInvestor(investor, dsTokens[i]);
            uint256 amount = _convertFromUSDC(100_000e6, dsTokens[i]);
            _omniPrank(securitize);
            IDSToken(dsTokens[i].token).issueTokens(investor, amount);
        }

        // NOTE: adding degen NFT as periphery contract is required to use it in the credit suite
        _addPeripheryContract(degenNFT);

        _createMarketWithDefaultRWAUnderlying();
        _createMarketWithOnDemandRWAUnderlying(depositor);
        _createMarketWithDefaultRWAUnderlyingRLUSD();

        _startOmniPrank(deployer);
        address compressor = address(new RWACompressor(addressProvider));
        address onDemandUnderlyingSubcompressor = address(new OnDemandRWAUnderlyingSubcompressor());
        address securitizeFactorySubcompressor = address(new SecuritizeRWAFactorySubcompressor());
        _stopOmniPrank();

        _setGlobalAddress(TYPE_RWA_COMPRESSOR, compressor, true);
        _configureLocal(compressor, abi.encodeCall(RWACompressor.setSubcompressor, (onDemandUnderlyingSubcompressor)));
        _configureLocal(compressor, abi.encodeCall(RWACompressor.setSubcompressor, (securitizeFactorySubcompressor)));

        string memory json;
        json = vm.serializeAddress("Addresses", "marketConfigurator", address(marketConfigurator));
        json = vm.serializeAddress("Addresses", "factory", factory);
        json = vm.serializeAddress("Addresses", "liquidator", liquidator);
        vm.writeJson(json, string.concat(vm.envOr("OUTPUT_DIR", string(".")), "/rwa-addresses.json"));
    }

    address public constant RLUSD = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address public constant RLUSD_PRICE_FEED = 0x26C46B7aD0012cA71F2298ada567dC9Af14E7f2A;
    address public constant RLUSD_DONOR = 0x7D98e5FD009Eb13fdD6baE736484CcD1a5A0ab9F;
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function _createMarketWithDefaultRWAUnderlyingRLUSD() internal {
        _addPriceFeed(RLUSD_PRICE_FEED, 1 days, "Chainlink RLUSD price feed");
        _allowPriceFeed(RLUSD, RLUSD_PRICE_FEED);

        address underlying = _deploy(
            "RWA_UNDERLYING::DEFAULT", 3_10, abi.encode(addressProvider, factory, RLUSD, "Default compliant ", "dc")
        );
        _allowPriceFeed(underlying, RLUSD_PRICE_FEED);

        // NOTE: sending small amount of underlying to market configurator to mint dead pool shares
        _startOmniPrank(riskCurator);
        ERC20(RLUSD).approve(underlying, 1e5);
        ERC4626(underlying).deposit(1e5, address(marketConfigurator));
        _stopOmniPrank();

        MarketParams memory marketParams = _getDefaultMarketParams(underlying);
        marketParams.underlyingPriceFeed = RLUSD_PRICE_FEED;
        marketParams.interestRateModelParams.constructorParams = abi.encode(5000, 9000, 4_00, 0, 0, 0, false);
        marketParams.interestRateModelParams.salt = keccak256(abi.encode(underlying));
        address pool = _createMockMarket(underlying, marketParams);

        _addToken(
            pool,
            TokenParams({
                token: RLUSD,
                priceFeed: RLUSD_PRICE_FEED,
                reservePriceFeed: RLUSD_PRICE_FEED,
                quotaLimit: 10_000_000e18,
                quotaRate: 1
            })
        );
        _addToken(
            pool,
            TokenParams({
                token: USDC,
                priceFeed: USDC_PRICE_FEED,
                reservePriceFeed: USDC_PRICE_FEED,
                quotaLimit: 10_000_000e18,
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
                    quotaLimit: 10_000_000e18,
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
                    quotaLimit: 10_000_000e18,
                    quotaRate: 1
                })
            );
        }
        // NOTE: updating rates also adds new tokens to the quota keeper
        _updateQuotaRates(pool);

        address zapper = _deploy("ZAPPER::ERC4626_UNDERLYING", 3_10, abi.encode(pool));
        _addPeripheryContract(zapper);

        address[] memory creditManagers = new address[](dsTokens.length);
        for (uint256 i; i < dsTokens.length; ++i) {
            CreditSuiteParams memory creditSuiteParams = _getDefaultCreditSuiteParams();
            creditSuiteParams.debtLimit = 1_000_000e18;
            creditSuiteParams.minDebt = 50_000e18;
            creditSuiteParams.maxDebt = 1_000_000e18;
            creditSuiteParams.degenNFT = degenNFT;
            creditSuiteParams.accountFactoryParams.salt = keccak256(abi.encode(underlying, dsTokens[i].token));
            creditManagers[i] = _createMockCreditSuite(pool, creditSuiteParams);

            _addCollateralToken(creditManagers[i], RLUSD, 98_00);
            _addCollateralToken(creditManagers[i], USDC, 98_00);
            _addCollateralToken(creditManagers[i], dsTokens[i].token, 90_00);
            _allowAdapter(creditManagers[i], "ERC4626_VAULT", abi.encode(creditManagers[i], underlying, address(0)));
            _allowAdapter(creditManagers[i], "UNISWAP_V3_ROUTER", abi.encode(creditManagers[i], UNISWAP_V3_ROUTER));

            UniswapV3PoolStatus[] memory pools = new UniswapV3PoolStatus[](1);
            pools[0] = UniswapV3PoolStatus({token0: RLUSD, token1: USDC, fee: 100, allowed: true});
            _configureAdapter(
                creditManagers[i], UNISWAP_V3_ROUTER, abi.encodeCall(IUniswapV3Adapter.setPoolStatusBatch, (pools))
            );

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

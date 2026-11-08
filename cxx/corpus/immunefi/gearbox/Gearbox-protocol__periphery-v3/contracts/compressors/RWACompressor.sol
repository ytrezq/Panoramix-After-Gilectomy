// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {
    IMarketConfiguratorFactory
} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {Domain} from "@gearbox-protocol/permissionless/contracts/libraries/Domain.sol";

import {IRWACompressor} from "../interfaces/IRWACompressor.sol";
import {ITokenCompressor} from "../interfaces/ITokenCompressor.sol";
import {IRWAFactory} from "../interfaces/base/IRWAFactory.sol";
import {IRWAFactorySubcompressor} from "../interfaces/base/IRWAFactorySubcompressor.sol";
import {IRWAUnderlying} from "../interfaces/base/IRWAUnderlying.sol";
import {IRWAUnderlyingSubcompressor} from "../interfaces/base/IRWAUnderlyingSubcompressor.sol";
import {ISubcompressor} from "../interfaces/base/ISubcompressor.sol";
import {
    AddressValidation,
    DOMAIN_RWA_FACTORY,
    DOMAIN_RWA_UNDERLYING,
    TYPE_INSTANCE_MANAGER_PROXY,
    TYPE_MARKET_CONFIGURATOR_FACTORY,
    TYPE_RWA_COMPRESSOR,
    TYPE_TOKEN_COMPRESSOR
} from "../libraries/AddressValidation.sol";
import {BaseLib, BaseParams} from "../libraries/BaseLib.sol";

contract RWACompressor is IRWACompressor {
    using AddressValidation for IAddressProvider;
    using BaseLib for address;
    using Domain for bytes32;

    bytes32 public constant override contractType = TYPE_RWA_COMPRESSOR;
    uint256 public constant override version = 3_10;

    IAddressProvider internal immutable _ADDRESS_PROVIDER;
    mapping(bytes32 domain => mapping(bytes32 postfix => address)) public override subcompressors;

    modifier onlyInstanceOwner() {
        _ensureCallerIsInstanceOwner();
        _;
    }

    constructor(IAddressProvider addressProvider) {
        _ADDRESS_PROVIDER = addressProvider;
    }

    // ------- //
    // GETTERS //
    // ------- //

    function getRWAMarketsData(address[] calldata configurators, address[] calldata factories)
        external
        view
        override
        returns (RWAUnderlyingData[] memory underlyingsData, RWAFactoryData[] memory factoriesData)
    {
        // underlyings data
        address marketConfiguratorFactory = _ADDRESS_PROVIDER.getGlobalAddress(TYPE_MARKET_CONFIGURATOR_FACTORY);
        uint256 numConfigurators = configurators.length;
        uint256 maxUnderlyings;
        for (uint256 i; i < numConfigurators; ++i) {
            if (!IMarketConfiguratorFactory(marketConfiguratorFactory).isMarketConfigurator(configurators[i])) {
                revert InvalidMarketConfiguratorException(configurators[i]);
            }
            address contractsRegister = IMarketConfigurator(configurators[i]).contractsRegister();
            maxUnderlyings += IContractsRegister(contractsRegister).getPools().length;
        }

        underlyingsData = new RWAUnderlyingData[](maxUnderlyings);
        uint256 numUnderlyings;
        for (uint256 i; i < numConfigurators; ++i) {
            address contractsRegister = IMarketConfigurator(configurators[i]).contractsRegister();
            address[] memory pools = IContractsRegister(contractsRegister).getPools();
            uint256 numPools = pools.length;
            for (uint256 j; j < numPools; ++j) {
                address underlying = _getAsset(pools[j]);
                if (!_ADDRESS_PROVIDER.hasDomain(underlying, DOMAIN_RWA_UNDERLYING)) continue;
                RWAUnderlyingData memory data = _getRWAUnderlyingData(underlying);
                if (_contains(factories, data.factory)) underlyingsData[numUnderlyings++] = data;
            }
        }
        // might contain duplicates if multiple pools share the same underlying
        assembly {
            mstore(underlyingsData, numUnderlyings)
        }

        // factories data
        uint256 numFactories = factories.length;
        factoriesData = new RWAFactoryData[](numFactories);
        for (uint256 i; i < numFactories; ++i) {
            if (!_ADDRESS_PROVIDER.hasDomain(factories[i], DOMAIN_RWA_FACTORY)) {
                revert InvalidRWAFactoryException(factories[i]);
            }
            factoriesData[i] = _getRWAFactoryData(factories[i]);
        }
    }

    function getRWAInvestorData(address investor, address[] calldata factories)
        external
        view
        override
        returns (RWAInvestorData[] memory investorData)
    {
        uint256 numFactories = factories.length;
        investorData = new RWAInvestorData[](numFactories);
        for (uint256 i; i < numFactories; ++i) {
            if (!_ADDRESS_PROVIDER.hasDomain(factories[i], DOMAIN_RWA_FACTORY)) {
                revert InvalidRWAFactoryException(factories[i]);
            }
            investorData[i] = _getRWAInvestorData(investor, factories[i].getBaseParams());
        }
    }

    // ---------------------- //
    // INSTANCE OWNER ACTIONS //
    // ---------------------- //

    function setSubcompressor(address subcompressor) external onlyInstanceOwner {
        (bytes32 domain, bytes32 postfix) = ISubcompressor(subcompressor).getCompressedType();
        if (domain != DOMAIN_RWA_UNDERLYING && domain != DOMAIN_RWA_FACTORY) {
            revert InvalidDomainException(domain);
        }
        subcompressors[domain][postfix] = subcompressor;
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _ensureCallerIsInstanceOwner() internal view {
        if (msg.sender != _ADDRESS_PROVIDER.getGlobalAddress(TYPE_INSTANCE_MANAGER_PROXY)) {
            revert CallerIsNotInstanceOwnerException(msg.sender);
        }
    }

    function _getAsset(address vault) internal view returns (address) {
        return IERC4626(vault).asset();
    }

    function _contains(address[] memory array, address element) internal pure returns (bool) {
        uint256 len = array.length;
        for (uint256 i; i < len; ++i) {
            if (array[i] == element) return true;
        }
        return false;
    }

    function _getRWAUnderlyingData(address underlying) internal view returns (RWAUnderlyingData memory data) {
        data.baseParams = underlying.getBaseParams();

        data.asset = _getAsset(underlying);
        data.factory = IRWAUnderlying(underlying).getFactory();

        address subcompressor = subcompressors[DOMAIN_RWA_UNDERLYING][data.baseParams.contractType.extractPostfix()];
        if (subcompressor != address(0)) {
            data.extraDetails = IRWAUnderlyingSubcompressor(subcompressor).getUnderlyingData(underlying);
        }
    }

    function _getRWAFactoryData(address factory) internal view returns (RWAFactoryData memory data) {
        data.baseParams = factory.getBaseParams();

        address tokenCompressor = _ADDRESS_PROVIDER.getLatestPatchAddress(TYPE_TOKEN_COMPRESSOR, 3_10);
        data.tokens = ITokenCompressor(tokenCompressor).getTokens(IRWAFactory(factory).getTokens());

        address subcompressor = subcompressors[DOMAIN_RWA_FACTORY][data.baseParams.contractType.extractPostfix()];
        if (subcompressor != address(0)) {
            data.extraDetails = IRWAFactorySubcompressor(subcompressor).getFactoryData(factory);
        }
    }

    function _getRWAInvestorData(address investor, BaseParams memory factory)
        internal
        view
        returns (RWAInvestorData memory data)
    {
        address[] memory creditAccounts = IRWAFactory(factory.addr).getCreditAccounts(investor);
        uint256 numCreditAccounts = creditAccounts.length;
        data.creditAccounts = new RWACreditAccountData[](numCreditAccounts);
        for (uint256 i; i < numCreditAccounts; ++i) {
            data.creditAccounts[i] = _getRWACreditAccountData(creditAccounts[i], factory);
        }

        address subcompressor = subcompressors[DOMAIN_RWA_FACTORY][factory.contractType.extractPostfix()];
        if (subcompressor != address(0)) {
            data.extraDetails = IRWAFactorySubcompressor(subcompressor).getInvestorData(investor, factory.addr);
        }
    }

    function _getRWACreditAccountData(address creditAccount, BaseParams memory factory)
        internal
        view
        returns (RWACreditAccountData memory data)
    {
        data.creditAccount = creditAccount;
        data.wallet = IRWAFactory(factory.addr).getWallet(creditAccount);
        data.frozen = IRWAFactory(factory.addr).isFrozen(creditAccount);

        address subcompressor = subcompressors[DOMAIN_RWA_FACTORY][factory.contractType.extractPostfix()];
        if (subcompressor != address(0)) {
            data.extraDetails =
                IRWAFactorySubcompressor(subcompressor).getCreditAccountData(creditAccount, factory.addr);
        }
    }
}

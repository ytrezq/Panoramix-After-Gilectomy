// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IACLTrait} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IACLTrait.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

import {IACL} from "@gearbox-protocol/permissionless/contracts/interfaces/IACL.sol";
import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {
    IMarketConfiguratorFactory
} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {IPriceFeedStore} from "@gearbox-protocol/permissionless/contracts/interfaces/IPriceFeedStore.sol";
import {
    AP_BYTECODE_REPOSITORY as TYPE_BYTECODE_REPOSITORY,
    AP_CREDIT_FACADE as TYPE_CREDIT_FACADE,
    AP_INSTANCE_MANAGER_PROXY as TYPE_INSTANCE_MANAGER_PROXY,
    AP_MARKET_CONFIGURATOR_FACTORY as TYPE_MARKET_CONFIGURATOR_FACTORY,
    AP_PRICE_FEED_STORE as TYPE_PRICE_FEED_STORE,
    DOMAIN_CREDIT_MANAGER,
    DOMAIN_POOL,
    NO_VERSION_CONTROL
} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";
import {Domain} from "@gearbox-protocol/permissionless/contracts/libraries/Domain.sol";

bytes32 constant DOMAIN_ON_DEMAND_LP = "ON_DEMAND_LP";
bytes32 constant DOMAIN_RWA_FACTORY = "RWA_FACTORY";
bytes32 constant DOMAIN_RWA_UNDERLYING = "RWA_UNDERLYING";

bytes32 constant TYPE_SECURITIZE_DEGEN_NFT = "DEGEN_NFT::SECURITIZE";
bytes32 constant TYPE_SECURITIZE_RWA_FACTORY = "RWA_FACTORY::SECURITIZE";
bytes32 constant TYPE_DEFAULT_RWA_UNDERLYING = "RWA_UNDERLYING::DEFAULT";
bytes32 constant TYPE_ON_DEMAND_RWA_UNDERLYING = "RWA_UNDERLYING::ON_DEMAND";
bytes32 constant TYPE_MONOPOLIZED_ON_DEMAND_LP = "ON_DEMAND_LP::MONOPOLIZED";

bytes32 constant TYPE_RWA_COMPRESSOR = "GLOBAL::RWA_COMPRESSOR";
bytes32 constant TYPE_TOKEN_COMPRESSOR = "GLOBAL::TOKEN_COMPRESSOR";

library AddressValidation {
    using Domain for bytes32;

    function hasType(IAddressProvider addressProvider, address deployedContract, bytes32 contractType)
        internal
        view
        returns (bool)
    {
        return isDeployedFromBytecodeRepository(addressProvider, deployedContract)
            && _getContractType(deployedContract) == contractType;
    }

    function hasDomain(IAddressProvider addressProvider, address deployedContract, bytes32 domain)
        internal
        view
        returns (bool)
    {
        return isDeployedFromBytecodeRepository(addressProvider, deployedContract)
            && _getContractType(deployedContract).extractDomain() == domain;
    }

    function isDeployedFromBytecodeRepository(IAddressProvider addressProvider, address deployedContract)
        internal
        view
        returns (bool)
    {
        address bytecodeRepository = getGlobalAddress(addressProvider, TYPE_BYTECODE_REPOSITORY);
        return IBytecodeRepository(bytecodeRepository).getDeployedContractBytecodeHash(deployedContract) != 0;
    }

    function isMarketConfigurator(IAddressProvider addressProvider, address marketConfigurator)
        internal
        view
        returns (bool)
    {
        address marketConfiguratorFactory = getGlobalAddress(addressProvider, TYPE_MARKET_CONFIGURATOR_FACTORY);
        return IMarketConfiguratorFactory(marketConfiguratorFactory).isMarketConfigurator(marketConfigurator);
    }

    function isKnownToken(IAddressProvider addressProvider, address token) internal view returns (bool) {
        address priceFeedStore = getGlobalAddress(addressProvider, TYPE_PRICE_FEED_STORE);
        return IPriceFeedStore(priceFeedStore).isKnownToken(token);
    }

    function isPool(IAddressProvider addressProvider, address pool) internal view returns (bool) {
        if (!hasDomain(addressProvider, pool, DOMAIN_POOL)) return false;
        address marketConfigurator = getMarketConfigurator(pool);
        return isMarketConfigurator(addressProvider, marketConfigurator) && isRegisteredPool(marketConfigurator, pool);
    }

    function isCreditManager(IAddressProvider addressProvider, address creditManager) internal view returns (bool) {
        if (!hasDomain(addressProvider, creditManager, DOMAIN_CREDIT_MANAGER)) return false;
        address creditConfigurator = ICreditManagerV3(creditManager).creditConfigurator();
        address marketConfigurator = getMarketConfigurator(creditConfigurator);
        return isMarketConfigurator(addressProvider, marketConfigurator)
            && isRegisteredCreditManager(marketConfigurator, creditManager);
    }

    function isCreditFacade(IAddressProvider addressProvider, address creditFacade) internal view returns (bool) {
        if (!hasType(addressProvider, creditFacade, TYPE_CREDIT_FACADE)) return false;
        address creditManager = ICreditFacadeV3(creditFacade).creditManager();
        return isCreditManager(addressProvider, creditManager)
            && ICreditManagerV3(creditManager).creditFacade() == creditFacade;
    }

    function getMarketConfigurator(address aclTrait) internal view returns (address) {
        return IACL(IACLTrait(aclTrait).acl()).getConfigurator();
    }

    function getContractsRegister(address marketConfigurator) internal view returns (address) {
        return IMarketConfigurator(marketConfigurator).contractsRegister();
    }

    function isRegisteredPool(address marketConfigurator, address pool) internal view returns (bool) {
        address contractsRegister = getContractsRegister(marketConfigurator);
        return IContractsRegister(contractsRegister).isPool(pool);
    }

    function isRegisteredCreditManager(address marketConfigurator, address creditManager) internal view returns (bool) {
        address contractsRegister = getContractsRegister(marketConfigurator);
        return IContractsRegister(contractsRegister).isCreditManager(creditManager);
    }

    function getGlobalAddress(IAddressProvider addressProvider, bytes32 key) internal view returns (address) {
        return addressProvider.getAddressOrRevert(key, NO_VERSION_CONTROL);
    }

    function getLatestPatchAddress(IAddressProvider addressProvider, bytes32 key, uint256 minorVersion)
        internal
        view
        returns (address)
    {
        uint256 latestPatch = addressProvider.getLatestPatchVersion(key, minorVersion);
        return addressProvider.getAddressOrRevert(key, latestPatch);
    }

    function _getContractType(address deployedContract) private view returns (bytes32) {
        return IVersion(deployedContract).contractType();
    }
}

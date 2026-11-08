// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

import {BaseParams} from "../types/BaseState.sol";
import {TokenData} from "./ITokenCompressor.sol";

interface IRWACompressor is IVersion {
    // ----- //
    // TYPES //
    // ----- //

    struct RWAUnderlyingData {
        BaseParams baseParams;
        address asset;
        address factory;
        bytes extraDetails;
    }

    struct RWAFactoryData {
        BaseParams baseParams;
        TokenData[] tokens;
        bytes extraDetails;
    }

    struct RWACreditAccountData {
        address creditAccount;
        address wallet;
        bool frozen;
        bytes extraDetails;
    }

    struct RWAInvestorData {
        RWACreditAccountData[] creditAccounts;
        bytes extraDetails;
    }

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotInstanceOwnerException(address caller);
    error InvalidDomainException(bytes32 domain);
    error InvalidRWAFactoryException(address factory);
    error InvalidMarketConfiguratorException(address marketConfigurator);

    // ------- //
    // GETTERS //
    // ------- //

    function subcompressors(bytes32 domain, bytes32 postfix) external view returns (address);
    function getRWAMarketsData(address[] calldata configurators, address[] calldata factories)
        external
        view
        returns (RWAUnderlyingData[] memory, RWAFactoryData[] memory);
    function getRWAInvestorData(address investor, address[] calldata factories)
        external
        view
        returns (RWAInvestorData[] memory);

    // ---------------------- //
    // INSTANCE OWNER ACTIONS //
    // ---------------------- //

    function setSubcompressor(address subcompressor) external;
}

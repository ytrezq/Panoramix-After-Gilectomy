// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOnDemandRWAUnderlying} from "../../../interfaces/IOnDemandRWAUnderlying.sol";
import {IRWAUnderlyingSubcompressor} from "../../../interfaces/base/IRWAUnderlyingSubcompressor.sol";

import {DOMAIN_RWA_UNDERLYING} from "../../../libraries/AddressValidation.sol";
import {BaseLib, BaseParams} from "../../../libraries/BaseLib.sol";

contract OnDemandRWAUnderlyingSubcompressor is IRWAUnderlyingSubcompressor {
    using BaseLib for address;

    bytes32 public constant override contractType = "GLOBAL::ON_DEMAND_RWA_U_SC";
    uint256 public constant override version = 3_10;

    function getCompressedType() external pure override returns (bytes32, bytes32) {
        return (DOMAIN_RWA_UNDERLYING, "ON_DEMAND");
    }

    function getUnderlyingData(address underlying) external view override returns (bytes memory) {
        address liquidityProvider = IOnDemandRWAUnderlying(underlying).getLiquidityProvider();
        // let's just hope that on-demand LPs don't have more nested contracts and serialized state is sufficient
        return abi.encode(liquidityProvider.getBaseParams());
    }
}

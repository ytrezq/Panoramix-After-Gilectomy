// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {ScriptBase} from "forge-std/Base.sol";

import {Chains} from "../Chains.sol";
import {IAddressCollection} from "./IAddressCollection.sol";
import {Utils} from "../../lib/Utils.sol";
import {AddrLib} from "../../lib/AddrLib.sol";

abstract contract AddressesCollectionStorage is ScriptBase, Chains {
    string public constant SILO_TOKEN = "SILO";
    string public constant SILO80_WETH20_TOKEN = "80Silo-20WETH";

    /// @notice Allocates an address for the current chain id
    /// @param _key The key to allocating/resolving an address
    /// @param _value An address that should be allocated
    function setAddress(string memory _key, address _value) public {
        AddrLib.setAddress(getChainId(), _key, _value);
    }

    /// @notice Allocates an address
    /// @param _chainId A chain identifier that a `_value` is related to
    /// @param _key The key to allocating/resolving an address
    /// @param _value An address that should be allocated
    function setAddress(uint256 _chainId, string memory _key, address _value) public {
        AddrLib.setAddress(_chainId, _key, _value);
    }
}

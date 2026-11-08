// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {EthereumAddresses} from "./EthereumAddresses.sol";
import {IAddressCollection} from "./IAddressCollection.sol";
import {AddrLib} from "../../lib/AddrLib.sol";

contract AddressesCollection is EthereumAddresses {
    constructor() {
        AddrLib.init();
        vm.label(AddrLib._ADDRESS_COLLECTION, "AddressesCollection");
        initializeEthereumAddresses();
    }

    /// @notice Resolves an address by specified `_key` for the current chain id
    /// @param _key The key to resolving an address
    function getAddress(string memory _key) public returns (address result) {
        string memory chainAlias = getChainAlias();
        result = AddrLib.getAddress(chainAlias, _key);
    }

    /// @notice Resolves an address by specified `_key` and `_chainId`
    /// @param _chainId A chain identifier for which we want to resolve an address
    /// @param _key The key to resolving an address
    function getAddress(uint256 _chainId, string memory _key) public returns (address) {
        string memory chainAlias = getChain(_chainId).chainAlias;

        return AddrLib.getAddress(chainAlias, _chainId, _key);
    }
}

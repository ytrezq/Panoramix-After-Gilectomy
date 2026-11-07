// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {AddressesCollectionStorage} from "./AddressesCollectionStorage.sol";

abstract contract EthereumAddresses is AddressesCollectionStorage {
    function initializeEthereumAddresses() public {
        _setEthAddress(SILO_TOKEN, 0x6f80310CA7F2C654691D1383149Fa1A57d8AB1f8);
        _setEthAddress(SILO80_WETH20_TOKEN, 0x9CC64EE4CB672Bc04C54B00a37E1Ed75b2Cc19Dd);
    }

    function _setEthAddress(string memory _key, address _value) private {
        setAddress(getChain(MAINNET_ALIAS).chainId, _key, _value);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;

import {IAddressCollection} from "../networks/addresses/IAddressCollection.sol";
import {AddressesCollectionImpl} from "../networks/addresses/AddressesCollectionImpl.sol";
import {AddressesCollectionImplWrapper} from "../networks/addresses/AddressesCollectionImplWrapper.sol";
import {KeyValueStorage} from "../key-value/KeyValueStorage.sol";
import {Utils} from "./Utils.sol";
import {VmLib} from "./VmLib.sol";
import {ChainsLib} from "./ChainsLib.sol";

library AddrLib {
    address internal constant _ADDRESS_COLLECTION =
        address(uint160(uint256(keccak256("silo foundry utils: address collection"))));

    string internal constant _DEFAULE_ADDR_PATH = "common/addresses";

    /// @notice Allocates an address for the current chain id
    /// @param _key The key to allocating/resolving an address
    /// @param _value An address that should be allocated
    function setAddress(string memory _key, address _value) internal {
        setAddress(ChainsLib.getChainId(), _key, _value);
    }

    /// @notice Allocates an address
    /// @param _chainId A chain identifier that a `_value` is related to
    /// @param _key The key to allocating/resolving an address
    /// @param _value An address that should be allocated
    function setAddress(uint256 _chainId, string memory _key, address _value) internal {
        VmLib.vm()
            .mockCall(
                _ADDRESS_COLLECTION,
                Utils.encodeGetAddressCall(IAddressCollection.getAddress.selector, _chainId, _key),
                abi.encode(_value)
            );

        VmLib.vm().label(_value, _key);
    }

    /// @notice Resolves an address by specified `_key` for the current chain id
    /// @param _key The key to resolving an address
    function getAddress(string memory _key) internal returns (address resut) {
        uint256 chainId = ChainsLib.getChainId();
        string memory chainAlias = ChainsLib.chainAlias();

        resut = getAddress(chainAlias, chainId, _key);
    }

    /// @notice Resolves an address by specified `_key` for the current chain id
    /// @param _chainAlias Chain alias
    /// @param _key The key to resolving an address
    function getAddress(string memory _chainAlias, string memory _key) internal returns (address resut) {
        uint256 chainId = ChainsLib.getChainId();

        resut = getAddress(_chainAlias, chainId, _key);
    }

    /// @notice Resolves an address by specified `_key` and `_chainId`
    /// @param _chainAlias Chain alias
    /// @param _chainId A chain identifier for which we want to resolve an address
    /// @param _key The key to resolving an address
    function getAddress(string memory _chainAlias, uint256 _chainId, string memory _key)
        internal
        returns (address result)
    {
        result = IAddressCollection(_ADDRESS_COLLECTION).getAddress(_chainId, _key);

        if (result == address(0)) {
            result = KeyValueStorage.getAddress(
                string(abi.encodePacked(_DEFAULE_ADDR_PATH, "/", _chainAlias, ".json")), "", _key
            );
        }
    }

    function getAddressSafe(string memory _chainAlias, string memory _key) internal returns (address result) {
        uint256 chainId = ChainsLib.getChainId();
        result = getAddress(_chainAlias, chainId, _key);
        requireNotEmptyAddress(result, _chainAlias, _key);
    }

    function getAddressSafe(string memory _chainAlias, uint256 _chainId, string memory _key)
        internal
        returns (address result)
    {
        result = getAddress(_chainAlias, _chainId, _key);
        requireNotEmptyAddress(result, _chainAlias, _key);
    }

    function init() internal {
        AddressesCollectionImpl collection = new AddressesCollectionImpl();
        AddressesCollectionImplWrapper wrapper = new AddressesCollectionImplWrapper();

        bytes memory code = Utils.getCodeAt(address(wrapper));

        VmLib.vm().etch(_ADDRESS_COLLECTION, code);

        AddressesCollectionImplWrapper(_ADDRESS_COLLECTION).setCollection(address(collection));
    }

    function requireNotEmptyAddress(address _addr, string memory _chainAlias, string memory _key) internal pure {
        require(
            _addr != address(0),
            string(abi.encodePacked("AddrLib: Can't find address for _chainAlias: ", _chainAlias, ", _key: ", _key))
        );
    }
}

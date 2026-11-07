// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {Governed} from "./moc-governance/Governance/Governed.sol";
import {IGovernor} from "./moc-governance/Governance/IGovernor.sol";
import {Initializable} from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import {AddressSetLib} from "./lib/AddressSetLib.sol";
import {IRegistry} from "./IRegistry.sol";

contract GovernedRegistry is Initializable, Governed, IRegistry {
    using AddressSetLib for AddressSetLib.AddressSet;

    struct UIntVal {
        bool b;
        uint248 v;
    }

    struct BoolVal {
        bool b;
        bool v;
    }

    struct IntVal {
        bool b;
        int248 v;
    }

    struct DecimalVal {
        bool b;
        int232 base;
        int16 exp;
    }

    mapping(bytes32 => DecimalVal) internal decimalStorage;
    mapping(bytes32 => UIntVal) internal uIntStorage;
    mapping(bytes32 => string) internal stringStorage;
    mapping(bytes32 => address) internal addressStorage;
    mapping(bytes32 => bytes) internal bytesStorage;
    mapping(bytes32 => BoolVal) internal boolStorage;
    mapping(bytes32 => IntVal) internal intStorage;
    mapping(bytes32 => AddressSetLib.AddressSet) internal addressArrayStorage;

    constructor() public initializer {
        // Avoid leaving the implementation contract uninitialized.
    }

    function initialize(IGovernor _governor) external initializer {
        Governed._initialize(_governor);
    }

    function getDecimal(bytes32 _key) external view override returns (int232 base, int16 exp) {
        require(decimalStorage[_key].b, "Invalid key");
        return (decimalStorage[_key].base, decimalStorage[_key].exp);
    }

    function getUint(bytes32 _key) external view override returns (uint248) {
        require(uIntStorage[_key].b, "Invalid key");
        return uIntStorage[_key].v;
    }

    function getString(bytes32 _key) external view override returns (string memory) {
        require(bytes(stringStorage[_key]).length != 0, "Invalid key");
        return stringStorage[_key];
    }

    function getAddress(bytes32 _key) external view override returns (address) {
        require(addressStorage[_key] != address(0), "Invalid key");
        return addressStorage[_key];
    }

    function getBytes(bytes32 _key) external view override returns (bytes memory) {
        require(bytesStorage[_key].length != 0, "Invalid key");
        return bytesStorage[_key];
    }

    function getBool(bytes32 _key) external view override returns (bool) {
        require(boolStorage[_key].b, "Invalid key");
        return boolStorage[_key].v;
    }

    function getInt(bytes32 _key) external view override returns (int248) {
        require(intStorage[_key].b, "Invalid key");
        return intStorage[_key].v;
    }

    function setDecimal(bytes32 _key, int232 _base, int16 _exp) external override onlyAuthorizedChanger {
        decimalStorage[_key] = DecimalVal(true, _base, _exp);
    }

    function setUint(bytes32 _key, uint248 _value) external override onlyAuthorizedChanger {
        uIntStorage[_key] = UIntVal(true, _value);
    }

    function setString(bytes32 _key, string calldata _value) external override onlyAuthorizedChanger {
        require(bytes(_value).length != 0, "Invalid value");
        stringStorage[_key] = _value;
    }

    function setAddress(bytes32 _key, address _value) external override onlyAuthorizedChanger {
        require(_value != address(0), "Invalid value");
        addressStorage[_key] = _value;
    }

    function setBytes(bytes32 _key, bytes calldata _value) external override onlyAuthorizedChanger {
        require(_value.length != 0, "Invalid value");
        bytesStorage[_key] = _value;
    }

    function setBool(bytes32 _key, bool _value) external override onlyAuthorizedChanger {
        boolStorage[_key] = BoolVal(true, _value);
    }

    function setInt(bytes32 _key, int248 _value) external override onlyAuthorizedChanger {
        intStorage[_key] = IntVal(true, _value);
    }

    function deleteDecimal(bytes32 _key) external override onlyAuthorizedChanger {
        delete decimalStorage[_key];
    }

    function deleteUint(bytes32 _key) external override onlyAuthorizedChanger {
        delete uIntStorage[_key];
    }

    function deleteString(bytes32 _key) external override onlyAuthorizedChanger {
        delete stringStorage[_key];
    }

    function deleteAddress(bytes32 _key) external override onlyAuthorizedChanger {
        delete addressStorage[_key];
    }

    function deleteBytes(bytes32 _key) external override onlyAuthorizedChanger {
        delete bytesStorage[_key];
    }

    function deleteBool(bytes32 _key) external override onlyAuthorizedChanger {
        delete boolStorage[_key];
    }

    function deleteInt(bytes32 _key) external override onlyAuthorizedChanger {
        delete intStorage[_key];
    }

    function getAddressArray(bytes32 _key) external view override returns (address[] memory) {
        require(addressArrayStorage[_key].length() != 0, "Invalid key");
        return addressArrayStorage[_key].asArray();
    }

    function getAddressArrayLength(bytes32 _key) external view override returns (uint256) {
        return addressArrayStorage[_key].length();
    }

    function getAddressArrayElementAt(bytes32 _key, uint256 idx) external view override returns (address) {
        require(addressArrayStorage[_key].length() != 0, "Invalid key");
        return addressArrayStorage[_key].at(idx);
    }

    function addressArrayContains(bytes32 _key, address value) external view override returns (bool) {
        return addressArrayStorage[_key].contains(value);
    }

    function pushAddressArrayElement(bytes32 _key, address _addr) external override onlyAuthorizedChanger {
        addressArrayStorage[_key].add(_addr);
    }

    function pushAddressArray(bytes32 _key, address[] memory data) external override onlyAuthorizedChanger {
        for (uint256 i = 0; i < data.length; i++) {
            addressArrayStorage[_key].add(data[i]);
        }
    }

    function clearAddressArray(bytes32 _key) external override onlyAuthorizedChanger {
        addressArrayStorage[_key].clear();
    }

    function removeAddressArrayElement(bytes32 _key, address value) external override onlyAuthorizedChanger {
        addressArrayStorage[_key].remove(value);
    }
}

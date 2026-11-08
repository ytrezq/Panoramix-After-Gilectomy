// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

interface IRegistry {
    // *** Getter Methods ***
    function getDecimal(bytes32 _key) external view returns (int232 base, int16 exp);

    function getUint(bytes32 _key) external view returns (uint248);

    function getString(bytes32 _key) external view returns (string memory);

    function getAddress(bytes32 _key) external view returns (address);

    function getBytes(bytes32 _key) external view returns (bytes memory);

    function getBool(bytes32 _key) external view returns (bool);

    function getInt(bytes32 _key) external view returns (int248);

    // *** Setter Methods ***
    function setDecimal(bytes32 _key, int232 _base, int16 _exp) external;

    function setUint(bytes32 _key, uint248 _value) external;

    function setString(bytes32 _key, string calldata _value) external;

    function setAddress(bytes32 _key, address _value) external;

    function setBytes(bytes32 _key, bytes calldata _value) external;

    function setBool(bytes32 _key, bool _value) external;

    function setInt(bytes32 _key, int248 _value) external;

    // *** Delete Methods ***
    function deleteDecimal(bytes32 _key) external;

    function deleteUint(bytes32 _key) external;

    function deleteString(bytes32 _key) external;

    function deleteAddress(bytes32 _key) external;

    function deleteBytes(bytes32 _key) external;

    function deleteBool(bytes32 _key) external;

    function deleteInt(bytes32 _key) external;

    // Nov 2020 Upgrade
    // *** Getter Methods ***
    function getAddressArrayLength(bytes32 _key) external view returns (uint256);

    function getAddressArrayElementAt(bytes32 _key, uint256 idx) external view returns (address);

    function pushAddressArrayElement(bytes32 _key, address _addr) external;

    function getAddressArray(bytes32 _key) external view returns (address[] memory);

    function addressArrayContains(bytes32 _key, address value) external view returns (bool);

    // *** Setters ***
    function pushAddressArray(bytes32 _key, address[] memory data) external;

    function clearAddressArray(bytes32 _key) external;

    function removeAddressArrayElement(bytes32 _key, address value) external;
}

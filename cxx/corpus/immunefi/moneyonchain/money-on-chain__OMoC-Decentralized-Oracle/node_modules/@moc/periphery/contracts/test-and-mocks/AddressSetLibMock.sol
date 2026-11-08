// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {AddressSetLib} from "../lib/AddressSetLib.sol";

contract AddressSetLibMock {
    using AddressSetLib for AddressSetLib.AddressSet;
    AddressSetLib.AddressSet internal data;

    event Result(bool result);

    constructor() public {
        data = AddressSetLib.init();
    }

    function clear() external {
        data.clear();
    }

    function add(address value) external {
        bool ret = data.add(value);
        emit Result(ret);
    }

    function remove(address value) external {
        bool ret = data.remove(value);
        emit Result(ret);
    }

    function contains(address value) external view returns (bool) {
        return data.contains(value);
    }

    function length() external view returns (uint256) {
        return data.length();
    }

    function at(uint256 index) external view returns (address) {
        return data.at(index);
    }

    function asArray() external view returns (address[] memory selectedOracles) {
        return data.asArray();
    }
}

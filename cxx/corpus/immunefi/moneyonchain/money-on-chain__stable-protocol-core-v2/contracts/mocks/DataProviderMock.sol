// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IDataProvider } from "../interfaces/IDataProvider.sol";

contract DataProviderMock is IDataProvider {
    bytes32 public data;
    bool public has;

    /**
     * @notice constructor
     * @param data_ default data
     */
    constructor(uint256 data_) {
        data = bytes32(data_);
        has = true;
    }

    function peek() external view returns (bytes32, bool) {
        return (data, has);
    }

    function poke(uint256 data_) external {
        data = bytes32(data_);
    }

    function deprecateDataProvider() external {
        has = false;
    }
}

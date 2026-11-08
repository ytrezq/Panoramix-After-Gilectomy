// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDataProvider } from "moc-main-latest/contracts/interfaces/IDataProvider.sol";

/**
 * @title Flux Capacitor Operation Difference Maximum DataProvider
 * @notice Allows the Owner, to set the value so that the protocol cold peek it.
 */
contract FCMaxOpDifferenceProvider is Ownable, IDataProvider {
    bytes32 public data;

    constructor(address owner_, uint256 initialData_) Ownable() {
        _transferOwnership(owner_);
        data = bytes32(initialData_);
    }

    function peek() external view returns (bytes32, bool) {
        return (data, true);
    }

    function setMaxOperationalDifference(uint256 data_) external onlyOwner {
        data = bytes32(data_);
    }
}

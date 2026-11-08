// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

contract MockIRM {
    uint256 public constant version = 3_10;
    bytes32 public constant contractType = "IRM::MOCK";

    bool public flag = false;

    constructor(address pool_, address) {}

    function availableToBorrow(uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function calcBorrowRate(uint256, uint256, bool) external pure returns (uint256) {
        return 0;
    }

    function setFlag(bool flag_) external {
        flag = flag_;
    }
}

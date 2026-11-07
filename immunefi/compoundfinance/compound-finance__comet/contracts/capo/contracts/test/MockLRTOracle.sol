// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract MockLRTOracle {
    uint256 private _price;
    uint8 public constant decimals = 18;

    constructor(uint256 initialPrice) {
        _price = initialPrice;
    }

    function rsETHPrice() external view returns (uint256) {
        return _price;
    }

    function setRsETHPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}

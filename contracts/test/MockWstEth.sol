// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IWstETHMock {
    function setRate(uint256) external;
}

contract MockWstETH is IWstETHMock {
    uint256 private _rate;
    uint8 public immutable decimals;

    constructor(uint256 initialRate) {
        decimals = 18;
        _rate = initialRate;
    }

    function stEthPerToken() external view returns (uint256) {
        return _rate;
    }

    function setRate(uint256 r) external override {
        _rate = r;
    }
}

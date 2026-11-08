pragma solidity 0.8.15;

import "../interfaces/IRateProvider.sol";

contract MockRateProvider is IRateProvider {
    uint256 private _rate;

    constructor(uint256 r) {
        _rate = r;
    }

    function setRate(uint256 r) external {
        _rate = r;
    }

    function getRate() external view returns (uint256) {
        return _rate;
    }
}

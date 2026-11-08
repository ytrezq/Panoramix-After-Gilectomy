//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IDex {
    function setFee(address token0, address token1, uint24 fee) external;
    function setPool(address token0, address token1, address pool) external;
    function setPool(address token0, address token1, bytes32 pool) external;
    function pairSetup(address token0, address token1, address pool, uint256[5] calldata params) external;
}
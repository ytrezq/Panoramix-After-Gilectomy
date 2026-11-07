// SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

interface ILinearPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        address mainToken,
        address wrappedToken,
        uint256 upperTarget,
        uint256 swapFeePercentage,
        address owner,
        uint256 protocolId
    ) external returns (address);
}
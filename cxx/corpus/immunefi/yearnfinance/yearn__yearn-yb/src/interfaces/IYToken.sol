// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYToken is IERC20 {
    event Swept(address indexed token, address indexed to, uint256 amount);

    function locker() external view returns (address);

    function token() external view returns (address);

    function mint(uint256 amount, address to) external;

    function sweep(address _token, address to, uint256 amount) external;

    function operator() external view returns (address);

    function owner() external view returns (address);
}

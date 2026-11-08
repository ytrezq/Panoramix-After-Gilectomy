// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IPermit2 } from "contracts/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Permit2Mock is IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        IERC20(token).approve(spender, amount);
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        IERC20(token).transferFrom(from, to, amount);
    }
}

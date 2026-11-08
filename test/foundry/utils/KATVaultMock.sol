// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IKATVault} from "../../../contracts/KATCustomOFTAdapterUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract KATVaultMock is IKATVault {
    IERC20 public token;

    function setToken(address _token) external {
        token = IERC20(_token);
    }

    function transferKat(address to, uint256 amount) external {
        if (address(token) != address(0)) {
            token.transfer(to, amount);
        }
    }
}

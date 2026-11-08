// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Savings } from "contracts/savings/Savings.sol";
import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";

import "./Helper.sol";

abstract contract SavingsUtils is Helper {
  string public name = "Staked USDp";
  string public symbol = "sUSDp";

  SavingsNameable public saving;

  function deploySavings(address governor, address tokenP, address accessManager) public returns (address) {
    vm.startPrank(governor);

    deal({ token: tokenP, to: governor, give: 1e18 });

    SavingsNameable savingsImpl = new SavingsNameable();

    // Calculate the future proxy address
    address futureProxyAddress = vm.computeCreateAddress(governor, vm.getNonce(governor));
    // Pre-approve the future proxy address
    IERC20(tokenP).approve(futureProxyAddress, 1e18);

    address savingAddress = address(
      new ERC1967Proxy(
        address(savingsImpl),
        abi.encodeWithSelector(savingsImpl.initialize.selector, accessManager, IERC20Metadata(tokenP), name, symbol, 1)
      )
    );
    vm.stopPrank();
    return savingAddress;
  }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {CrossChainCanonicalBase} from "lib/v2-foundry/src/CrossChainCanonicalBase.sol";
import {AlchemicTokenV2Base} from "lib/v2-foundry/src/AlchemicTokenV2Base.sol";
import {IXERC20} from "lib/v2-foundry/src/interfaces/external/connext/IXERC20.sol";

contract CrossChainCanonicalAlchemicTokenV3 is CrossChainCanonicalBase, AlchemicTokenV2Base {

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
      string memory name,
      string memory symbol
  ) external initializer {
    __CrossChainCanonicalBase_init(
      name,
      symbol,
      msg.sender
    );
    __AlchemicTokenV2Base_init();
  }

  function burn(uint256 amount) external returns (bool) {
    // If bridge is registered check limits and update accordingly.
    if (xBridges[msg.sender].burnerParams.maxLimit > 0) {
      uint256 currentLimit = burningCurrentLimitOf(msg.sender);
      if (amount > currentLimit) revert IXERC20.IXERC20_NotHighEnoughLimits();
      _useBurnerLimits(msg.sender, amount);
    }

    _burn(msg.sender, amount);
    return true;
  }

  /// @dev Destroys `amount` tokens from `account`, deducting from the caller's allowance.
  ///
  /// @param account The address the burn tokens from.
  /// @param amount  The amount of tokens to burn.
  function burnFrom(address account, uint256 amount) external returns (bool) {
    if (msg.sender != account) {
      uint256 newAllowance = allowance(account, msg.sender) - amount;
      _approve(account, msg.sender, newAllowance);
    }

    // If bridge is registered check limits and update accordingly.
    if (xBridges[msg.sender].burnerParams.maxLimit > 0) {
      uint256 currentLimit = burningCurrentLimitOf(msg.sender);
      if (amount > currentLimit) revert IXERC20.IXERC20_NotHighEnoughLimits();
      _useBurnerLimits(msg.sender, amount);
    }

    _burn(account, amount);
    return true;
  }


}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../Savings.sol";

/// @title SavingsNameable
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This contract is an authorized fork of Angle's SavingsNameable contract:
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/savings/nameable/SavingsNameable.sol
contract SavingsNameable is Savings {
  string internal __name;

  string internal __symbol;

  uint256[48] private __gapNameable;

  /// @inheritdoc ERC20Upgradeable
  function name() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
    return __name;
  }

  /// @inheritdoc ERC20Upgradeable
  function symbol() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
    return __symbol;
  }

  /// @notice Updates the name and symbol of the token
  function setNameAndSymbol(string memory newName, string memory newSymbol) external restricted {
    _setNameAndSymbol(newName, newSymbol);
  }

  function _setNameAndSymbol(string memory newName, string memory newSymbol) internal override {
    __name = newName;
    __symbol = newSymbol;
  }
}

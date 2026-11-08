// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { LibHelpers } from "../../contracts/parallelizer/libraries/LibHelpers.sol";
import { LibManager } from "../../contracts/parallelizer/libraries/LibManager.sol";
import { LibStorage } from "../../contracts/parallelizer/libraries/LibStorage.sol";
import { ImplementationStorage } from "../../contracts/parallelizer/Storage.sol";

contract MockLib {
  function convertDecimalTo(
    uint256 amount,
    uint8 fromDecimals,
    uint8 toDecimals,
    Math.Rounding rounding
  )
    external
    pure
    returns (uint256)
  {
    return LibHelpers.convertDecimalTo(amount, fromDecimals, toDecimals, rounding);
  }

  function checkList(address token, address[] memory tokens) external pure returns (int256) {
    return LibHelpers.checkList(token, tokens);
  }

  function findLowerBound(
    bool increasingArray,
    uint64[] memory array,
    uint64 normalizerArray,
    uint64 element
  )
    external
    pure
    returns (uint256)
  {
    return LibHelpers.findLowerBound(increasingArray, array, normalizerArray, element);
  }

  function piecewiseLinear(uint64 x, uint64[] memory xArray, int64[] memory yArray) external pure returns (int64) {
    return LibHelpers.piecewiseLinear(x, xArray, yArray);
  }

  function implementationStorage() external pure returns (ImplementationStorage memory) {
    return LibStorage.implementationStorage();
  }

  function transferRecipient(bytes memory config) external view returns (address) {
    return LibManager.transferRecipient(config);
  }

  function totalAssets(bytes memory config) external view returns (uint256[] memory balances, uint256 totalValue) {
    return LibManager.totalAssets(config);
  }

  function invest(uint256 amount, bytes memory config) external {
    LibManager.invest(amount, config);
  }

  function maxAvailable(bytes memory config) external view returns (uint256 available) {
    return LibManager.maxAvailable(config);
  }
}

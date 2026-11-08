// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IDiamondEtherscan } from "contracts/interfaces/IDiamondEtherscan.sol";

import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import { AccessManagedModifiers } from "./AccessManagedModifiers.sol";

/// @title DiamondEtherscan
/// @author Forked from:
/// https://github.com/zdenham/diamond-etherscan/blob/main/contracts/libraries/LibDiamondEtherscan.sol
contract DiamondEtherscan is IDiamondEtherscan, AccessManagedModifiers {
  /// @inheritdoc IDiamondEtherscan
  function setDummyImplementation(address _implementation) external restricted {
    LibDiamondEtherscan.setDummyImplementation(_implementation);
  }

  /// @inheritdoc IDiamondEtherscan
  function implementation() external view returns (address) {
    return LibDiamondEtherscan.dummyImplementation();
  }
}

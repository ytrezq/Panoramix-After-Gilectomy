// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import { LibOracle } from "../libraries/LibOracle.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../Storage.sol";

struct CollateralSetup {
  address token;
  bool targetMax;
  bytes oracleConfig;
  uint64[] xMintFee;
  int64[] yMintFee;
  uint64[] xBurnFee;
  int64[] yBurnFee;
}

struct RedemptionSetup {
  uint64[] xRedeemFee;
  int64[] yRedeemFee;
}

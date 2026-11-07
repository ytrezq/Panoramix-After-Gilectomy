// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../utils/Constants.sol";
import { DiamondStorage, ParallelizerStorage, Collateral, FacetInfo, WhitelistType } from "./Storage.sol";

/// @notice Contract mimicking the overall storage layout of the parallelizer system.
/// @dev Not meant to be deployed or used. The goals are:
///  - To ensure the storage layout is well understood by everyone
///  - To force test failures if the layout is changed
/// @dev
///  - uint256(TRANSMUTER_STORAGE_POSITION)
///         = 34004428136983271448470628240738343798407004761490164663157697638250996796533
///  - uint256(DIAMOND_STORAGE_POSITION)
///         = 90909012999857140622417080374671856515688564136957639390032885430481714942747
///  - uint256(IMPLEMENTATION_STORAGE_POSITION)
///         = 24440054405305269366569402256811496959409073762505157381672968839269610695612
contract Layout {
  // uint256(IMPLEMENTATION_STORAGE_POSITION)
  uint256[24_440_054_405_305_269_366_569_402_256_811_496_959_409_073_762_505_157_381_672_968_839_269_610_695_612]
    private __gap1;
  address public implementation;
  // uint256(TRANSMUTER_STORAGE_POSITION) - 1 - uint256(IMPLEMENTATION_STORAGE_POSITION)
  uint256[9_564_373_731_678_002_081_901_225_983_926_846_838_997_930_998_985_007_281_484_728_798_981_386_100_920]
    private __gap2;
  address public tokenP; // slot 1
  uint8 public isRedemptionLive; // slot 1
  uint8 public nonReentrant; // slot 1
  bool public consumingSchedule; // slot 1
  uint128 public normalizedStables; // slot 2
  uint128 public normalizer; // slot 2
  address[] public collateralList; // slot 3
  uint64[] public xRedemptionCurve; // slot 4
  int64[] public yRedemptionCurve; // slot 5
  mapping(address => Collateral) public collaterals; // slot 6
  mapping(address => uint256) public isTrusted; // slot 7
  mapping(address => uint256) public isSellerTrusted; // slot 8
  mapping(WhitelistType => mapping(address => uint256)) public isWhitelistedForType; // slot 9
  mapping(address => uint256) public slippageTolerance; // slot 10
  uint64 public surplusBufferRatio; // slot 11
  uint256 public lastReleasedAt; // slot 12
  uint256 public totalShares; // slot 13
  address[] public payees; // slot 14
  mapping(address => uint256) public shares; // slot 15
  address public swapRouter; // slot 16
  // uint256(DIAMOND_STORAGE_POSITION) - ParallelizerStorage offset (16) - uint256(TRANSMUTER_STORAGE_POSITION)
  uint256[56_904_584_862_873_869_173_946_452_133_933_512_717_281_559_375_467_474_726_875_187_792_230_718_146_198]
    private __gap3;
  bytes4[] public selectors; // slot 1
  mapping(bytes4 => FacetInfo) public selectorInfo; // slot 2
  address public accessManager; // slot 3
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "./neutrl/sNUSD.sol";

contract MockStakedNUSD is sNUSD {
  constructor(address _NUSD, address _owner) sNUSD(_NUSD, _owner) {}
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { FlashParallelToken } from "contracts/flashloan/FlashParallelToken.sol";

contract FlashParallelTokenMockV2 is FlashParallelToken {

    function version() external pure returns (uint256) {
        return 2;
    }
}

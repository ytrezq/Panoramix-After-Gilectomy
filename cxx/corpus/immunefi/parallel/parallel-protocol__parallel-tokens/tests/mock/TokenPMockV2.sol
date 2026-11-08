// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { TokenP } from "contracts/tokens/TokenP/TokenP.sol";

contract TokenPMockV2 is TokenP {

    function version() external pure returns (uint256) {
        return 2;
    }
}

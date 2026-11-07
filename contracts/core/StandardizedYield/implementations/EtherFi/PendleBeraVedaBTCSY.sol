// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./PendleVedaBaseSY.sol";

contract PendleBeraVedaBTCSY is PendleVedaBaseSY {
    using PMath for uint256;

    // solhint-disable immutable-vars-naming
    // solhint-disable const-name-snakecase
    // solhint-disable ordering

    address public constant liquidBeraBTC = 0xC673ef7791724f0dcca38adB47Fbb3AEF3DB6C80;
    address public constant teller = 0x07951756b68427e7554AB4c9091344cB8De1Ad5a;

    address public constant EBTC = 0x657e8C867D8B37dCC18fA4Caead9C45EB088C642;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant LBTC = 0x8236a87084f8B84306f72007F36F2618A5634494;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    constructor() PendleVedaBaseSY(liquidBeraBTC, teller, 10 ** 8) {}

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == liquidBeraBTC || token == EBTC || token == WBTC || token == LBTC || token == CBBTC;
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(liquidBeraBTC, EBTC, WBTC, LBTC, CBBTC);
    }

    function approveAllForTeller() external {
        _safeApproveInf(EBTC, liquidBeraBTC);
        _safeApproveInf(WBTC, liquidBeraBTC);
        _safeApproveInf(LBTC, liquidBeraBTC);
        _safeApproveInf(CBBTC, liquidBeraBTC);
    }
}

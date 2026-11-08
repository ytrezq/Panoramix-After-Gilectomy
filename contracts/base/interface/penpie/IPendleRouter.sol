// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import "./IPAllActionTypeV3.sol";

interface IPendleRouter {
    function addLiquiditySingleSy(
        address receiver,
        address market,
        uint256 netSyIn,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy,
        LimitOrderData calldata limit
    ) external returns (uint256 netLpOut, uint256 netSyFee);
}
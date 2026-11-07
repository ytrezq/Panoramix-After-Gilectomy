// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./PendleAaveV3WithRewardsSYUpg.sol";
import "./PendleAaveMerit.sol";

contract PendleAaveV3OffchainRewardsSYUpg is PendleAaveV3WithRewardsSYUpg, PendleAaveMerit {
    constructor(
        address _aavePool,
        address _aToken,
        address _initialIncentiveController,
        address _defaultRewardToken,
        address _offchainReceiver
    )
        PendleAaveV3WithRewardsSYUpg(_aavePool, _aToken, _initialIncentiveController, _defaultRewardToken)
        PendleAaveMerit(_offchainReceiver)
    {}
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "../../../libraries/TokenHelper.sol";
import "../../../../interfaces/Angle/IAngleDistributor.sol";

abstract contract PendleAaveMerit is TokenHelper {
    // solhint-disable immutable-vars-naming
    address public immutable offchainReceiver;
    address public constant ANGLE_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae; // same on every chain

    constructor(address _offchainReceiver) {
        offchainReceiver = _offchainReceiver;
    }

    function claimOffchainRewards(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        require(msg.sender == offchainReceiver, "PendleAaveMerit: unauthorized");
        require(users.length == 1 && users[0] == address(this), "PendleAaveMerit: invalid users");

        uint256[] memory preBalance = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            preBalance[i] = _selfBalance(tokens[i]);
        }

        IAngleDistributor(ANGLE_DISTRIBUTOR).claim(users, tokens, amounts, proofs);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountClaimed = _selfBalance(tokens[i]) - preBalance[i];
            if (amountClaimed > 0) {
                _transferOut(tokens[i], offchainReceiver, amountClaimed);
            }
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IYBGaugeController } from "src/interfaces/yb/IYBGaugeController.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";

/**
 * @title NFTHelper
 * @notice UI helper functions for veYB NFT transfers and token ID lookups
 */
contract NFTHelper {
    IYBGaugeController public immutable gaugeController;
    IYBVotingEscrow public immutable veYB;
    uint256 public constant WEIGHT_VOTE_DELAY = 10 days;

    constructor(address _gaugeController, address _veYB) {
        require(_gaugeController != address(0), "!gaugeController");
        require(_veYB != address(0), "!veYB");
        gaugeController = IYBGaugeController(_gaugeController);
        veYB = IYBVotingEscrow(_veYB);
    }

    /**
     * @notice Convert user address to veYB NFT token ID
     * @param user User address
     * @return tokenId The NFT token ID (address as uint256)
     */
    function getTokenId(address user) external pure returns (uint256 tokenId) {
        return uint256(uint160(user));
    }

    /**
     * @notice Check if an NFT can be transferred and return list of gauges with active votes
     * @param user Address to check transfer eligibility
     * @return tokenId The NFT token ID (address as uint256)
     * @return lockedAmount The amount of tokens locked
     * @return isVotePowerCleared Whether the user's vote power is cleared
     * @return isPermanentLock Whether the lock is permanent (infinite lock)
     * @return voteClearTime Timestamp when all active votes can be cleared (0 if no cooldown)
     * @return votedGauges List of gauges where user has active vote weight
     */
    function getNftTransferInfo(address user)
        external
        view
        returns (
            uint256 tokenId,
            uint256 lockedAmount,
            bool isVotePowerCleared,
            bool isPermanentLock,
            uint256 voteClearTime,
            address[] memory votedGauges
        )
    {
        tokenId = uint256(uint160(user));
        isVotePowerCleared = gaugeController.ve_transfer_allowed(user);
        (int256 amount, uint256 lockEnd) = veYB.locked(user);
        lockedAmount = amount > 0 ? uint256(amount) : 0;
        isPermanentLock = lockEnd == type(uint256).max;

        votedGauges = _getVotedGauges(user, isVotePowerCleared);
        voteClearTime = _calculateVoteClearTime(user, votedGauges);
    }

    function _getVotedGauges(address user, bool isCleared) internal view returns (address[] memory votedGauges) {
        if (isCleared) {
            return new address[](0);
        }

        uint256 gaugesLength = gaugeController.n_gauges();
        address[] memory tempGauges = new address[](gaugesLength);
        uint256 count;

        for (uint256 i = 0; i < gaugesLength; i++) {
            address gauge = gaugeController.gauges(i);
            (, , uint256 power,) = gaugeController.vote_user_slopes(user, gauge);

            if (power > 0) {
                tempGauges[count++] = gauge;
            }
        }

        votedGauges = tempGauges;
        assembly {
            mstore(votedGauges, count)
        }
    }

    function _calculateVoteClearTime(address user, address[] memory votedGauges) internal view returns (uint256 clearTime) {
        if (votedGauges.length == 0) {
            return 0;
        }

        for (uint256 i = 0; i < votedGauges.length; i++) {
            uint256 gaugeVoteClearTime = gaugeController.last_user_vote(user, votedGauges[i]) + WEIGHT_VOTE_DELAY;
            if (gaugeVoteClearTime > block.timestamp && gaugeVoteClearTime > clearTime) {
                clearTime = gaugeVoteClearTime;
            }
        }
    }
}

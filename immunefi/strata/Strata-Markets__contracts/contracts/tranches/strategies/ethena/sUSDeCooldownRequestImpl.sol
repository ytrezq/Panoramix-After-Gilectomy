// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IsUSDe } from "./IsUSDe.sol";
import { IUnstakeHandler } from "../../interfaces/cooldown/IUnstakeHandler.sol";

/**
 * @title sUSDeCooldownRequestImpl
 * @dev Implementation of the unstake process for sUSDe tokens with cooldown period.
 * This contract is designed to be used within the UnstakeCooldown contract.
 * It handles the cooldown request, finalization, and asset transfer for unstaking sUSDe tokens.
 */
contract sUSDeCooldownRequestImpl is IUnstakeHandler, Initializable {

    IsUSDe public immutable sUSDe;

    address public handler;
    address public user;
    address public receiver;
    uint256 public requestedAt;
    bool    public pending;

    error HasActiveRequest();

    constructor(IsUSDe sUSDe_) {
        _disableInitializers();
        sUSDe = sUSDe_;
    }

    function initialize(address handler_, address user_) public virtual initializer {
        user = user_;
        handler = handler_;
    }

    function request() external returns (uint256 unlockAt) {
        return request(user);
    }
    function request(address receiver_) public returns (uint256 unlockAt) {
        require(msg.sender == handler, "NotAuthorized");

        uint256 shares = sUSDe.balanceOf(address(this));

        if (isCooldownActive() == false) {
            // Ethena won't disable the cooldown period, but just in case redeem shares directly
            sUSDe.redeem(shares, receiver_, address(this));
            return block.timestamp;
        }
        sUSDe.cooldownShares(shares);
        requestedAt = block.timestamp;
        receiver = receiver_;
        pending = true;
        return sUSDe.cooldowns(address(this)).cooldownEnd;
    }

    /**
     * @dev Completes the unstake request and transfers assets to the receiver.
     * Can be called by the UnstakeHandler, which can be triggered permissionlessly.
     */
    function finalize() external returns (uint256 amount)  {
        require(msg.sender == handler, "NotAuthorized");
        amount = sUSDe.cooldowns(address(this)).underlyingAmount;
        sUSDe.unstake(receiver);
        pending = false;
        return amount;
    }

    function getPendingAmount () external view returns (uint256 amount) {
        amount = sUSDe.cooldowns(address(this)).underlyingAmount;
        return amount;
    }

    function isCooldownActive() public view returns (bool) {
        return sUSDe.cooldownDuration() > 0;
    }
}

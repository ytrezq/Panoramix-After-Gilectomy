// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUnstakeHandler} from "../../interfaces/cooldown/IUnstakeHandler.sol";
import {IsNUSD} from "./IsNUSD.sol";

contract sNUSDCooldownRequestImpl is IUnstakeHandler, Initializable {
    IsNUSD public immutable sNUSD;

    address public handler;
    address public user;
    address public receiver;
    uint256 public requestedAt;
    bool public pending;

    error HasActiveRequest();

    constructor(IsNUSD sNUSD_) {
        _disableInitializers();
        sNUSD = sNUSD_;
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

        uint256 shares = sNUSD.balanceOf(address(this));

        if (isCooldownActive() == false) {
            sNUSD.redeem(shares, receiver_, address(this));
            return block.timestamp;
        }
        sNUSD.cooldownShares(shares);
        requestedAt = block.timestamp;
        receiver = receiver_;
        pending = true;
        return sNUSD.cooldowns(address(this)).cooldownEnd;
    }

    function finalize() external returns (uint256 amount) {
        require(msg.sender == handler, "NotAuthorized");
        amount = sNUSD.cooldowns(address(this)).underlyingAmount;
        sNUSD.unstake(receiver);
        pending = false;
        return amount;
    }

    function getPendingAmount() external view returns (uint256 amount) {
        amount = sNUSD.cooldowns(address(this)).underlyingAmount;
        return amount;
    }

    function isCooldownActive() public view returns (bool) {
        return sNUSD.cooldownDuration() > 0;
    }
}

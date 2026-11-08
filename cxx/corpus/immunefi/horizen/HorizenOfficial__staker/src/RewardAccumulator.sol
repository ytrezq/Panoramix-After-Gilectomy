// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Staker} from "./Staker.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RewardAccumulator is Ownable {

    uint256 public constant MAX_TIME_WINDOW = 90 days;

    Staker public immutable staker;
    ERC20 public immutable rewardToken;

    uint256 public lastRewardTime;
    uint256 public timeWindow;
    bool public whitelistEnabled;
    mapping(address => bool) public whitelist;
    uint256 public accumulatedRewards;

    event TimeWindowSet(uint256 timeWindow);
    event WhitelistEnabledSet(bool enabled);
    event WhitelistSet(address indexed user, bool enabled);
    event RewardsTransferred(address indexed from, uint256 amount);
    event RewardsAlreadyTransferredNotified(address indexed from, uint256 amount);
    event RewardsSentToStaker(uint256 amount, uint256 lastRewardTime);

    error NotWhitelisted();
    error WaitForNextRewardTime(uint256 nextRewardTime);
    error TransferNotFound();
    error TimeWindowTooLarge();
    error TimeWindowCannotBeZero();

    modifier onlyWhitelisted() {
        if (whitelistEnabled && !whitelist[msg.sender]) {
            revert NotWhitelisted();
        }
        _;
    }
    
    constructor(Staker _staker, ERC20 _rewardToken, uint256 _timeWindow, bool _whitelistEnabled) Ownable(msg.sender) {
        if (_timeWindow > MAX_TIME_WINDOW) {
            revert TimeWindowTooLarge();
        }
        if(_timeWindow == 0) {
            revert TimeWindowCannotBeZero();
        }
        
        staker = _staker;
        rewardToken = _rewardToken;
        timeWindow = _timeWindow;
        whitelistEnabled = _whitelistEnabled;
        lastRewardTime = block.timestamp;
    }

    // Admin functions
    function setTimeWindow(uint256 _timeWindow) external onlyOwner {
        if (_timeWindow > MAX_TIME_WINDOW) {
            revert TimeWindowTooLarge();
        }
        if(_timeWindow == 0) {
            revert TimeWindowCannotBeZero();
        }
        timeWindow = _timeWindow;
        emit TimeWindowSet(_timeWindow);
    }

    function setWhitelistEnabled(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistEnabledSet(enabled);
    }

    function setWhitelist(address user, bool enabled) external onlyOwner {
        whitelist[user] = enabled;
        emit WhitelistSet(user, enabled);
    }

    function nextRewardTime() public view returns (uint256) {
        return lastRewardTime + timeWindow;
    }

    //RewardAccumulator functions

    function transferAndNotifyRewards(uint256 amount) external onlyWhitelisted {
        // transfer tokens in this contract
        SafeERC20.safeTransferFrom(rewardToken, msg.sender, address(this), amount);
        // update accumulated rewards
        accumulatedRewards += amount;
        emit RewardsTransferred(msg.sender, amount);
    }

    //invoke this method after safeTransferFrom if you prefer to transfer them manually and then notify the contract - use the same exact amount as the one you transferred to the contract
    function notifyAlreadyTransferredRewards(uint256 amount) external onlyWhitelisted {
        // check that the amount transferred in is equal to the amount specified
        if (rewardToken.balanceOf(address(this)) - accumulatedRewards < amount) {
            revert TransferNotFound();
        }
        // update accumulated rewards
        accumulatedRewards += amount;
        emit RewardsAlreadyTransferredNotified(msg.sender, amount);
    }

    function sendRewardsToStaker() public {
        if (block.timestamp < nextRewardTime()) {
            revert WaitForNextRewardTime(nextRewardTime());
        }

        uint256 rewardAmount = accumulatedRewards;

        if (rewardAmount > 0) {
            // transfer accumulated rewards to staker
            SafeERC20.safeTransfer(rewardToken, address(staker), rewardAmount);
            // notify the staker that rewards were transferred in
            staker.notifyRewardAmount(rewardAmount);
            // reset accumulated rewards
            accumulatedRewards = 0;
        }
        // snap to the latest grid point <= block.timestamp, preserving the original schedule
        uint256 elapsedWindows = (block.timestamp - lastRewardTime) / timeWindow;
        lastRewardTime += elapsedWindows * timeWindow;
        emit RewardsSentToStaker(rewardAmount, lastRewardTime);
    }
        
}
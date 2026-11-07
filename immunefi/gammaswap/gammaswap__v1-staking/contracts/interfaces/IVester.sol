// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Interface for Vester contract
/// @author Simon Mall
/// @notice Normal ERC20 token operations are not allowed
/// @dev Need to implement `supportsInterface` function
interface IVester is IERC20, IERC165 {
    /// @dev Initialize Vester contract
    /// @param _name ERC20 name implementation
    /// @param _symbol ERC20 symbol implementation
    /// @param _vestingDuration how many seconds to vest the escrow token
    /// @param _esToken address of escrow token to vest
    /// @param _pairToken address of token that must be staked to determine how many tokens can be vested (optional)
    /// @param _claimableToken address of token that is given as reward for vesting escrow token
    /// @param _rewardTracker address of contract to track staked pairTokens to determine max vesting amount
    function initialize(string memory _name, string memory _symbol, uint256 _vestingDuration, address _esToken,
        address _pairToken, address _claimableToken, address _rewardTracker) external;

    /// @dev Get last vesting time of user
    /// @param _account User address for query
    function lastVestingTimes(address _account) external view returns(uint256);

    /// @dev Only used in Vester for rewards from staked LP tokens
    /// @return Address of LP token accepted as staked to be allowed to vest
    function pairToken() external view returns (address);

    /// @dev Only used in Vester for rewards from staked LP tokens
    /// @return Total GS LP tokens staked in RewardTracker
    function pairSupply() external view returns (uint256);

    /// @dev Returns total vested esGS amounts
    /// @param _account Vesting account
    function getTotalVested(address _account) external view returns (uint256);

    /// @dev Returns required pair token amount for vesting
    /// @param _account Vesting account
    /// @param _esAmount Vesting amount
    function getPairAmount(address _account, uint256 _esAmount) external view returns (uint256);

    /// @dev Updated with every vesting update
    /// @return Total amounts of claimableToken that has already vested
    function totalClaimable() external view returns(uint256);

    /// @dev Used to require user to commit a staked amount to be able to vest an escrow token
    /// @return True if there's a limit to how many esTokens a user can vest
    function hasMaxVestableAmount() external view returns(bool);

    /// @dev Set in constructor
    /// @return Time in seconds it will take to vest the esToken into the claimableToken
    function vestingDuration() external view returns(uint256);

    /// @dev Update vesting duration
    /// @param _vestingDuration Time in seconds it will take to vest the esToken into the claimableToken
    function setVestingDuration(uint256 _vestingDuration) external;

    /// @dev Set in constructor
    /// @return Address of token that will be claimed when esToken is vested.
    function claimableToken() external view returns(address);

    /// @dev Set in constructor
    /// @return Address of escrow token to vest in this Vester contract
    function esToken() external view returns(address);

    /// @dev Set handler for this contract
    /// @param _handler Address for query
    /// @param _isActive True - Enable, False - Disable
    function setHandler(address _handler, bool _isActive) external;

    /// @dev Withdraw tokens from this contract
    /// @param _token ERC20 token address, address(0) refers to native token(i.e. ETH)
    /// @param _recipient Recipient for the withdrawal
    /// @param _amount Amount of tokens to withdraw
    function withdrawToken(address _token, address _recipient, uint256 _amount) external;

    /// @dev Returns max withdrawable amount of reward tokens in this contract
    function maxWithdrawableAmount() external returns (uint256);

    /// @dev Returns reward tracker contract address
    function rewardTracker() external view returns (address);

    /// @dev Vest escrow tokens into GS
    /// @param _amount Amount of escrow tokens to vest
    function deposit(uint256 _amount) external;

    /// @dev Vest escrow tokens into GS on behalf of user
    /// @param _account User address for query
    /// @param _amount Amount of escrow tokens to vest
    function depositForAccount(address _account, uint256 _amount) external;

    /// @dev Claim GS rewards
    /// @return Amount of GS rewards
    function claim() external returns(uint256);

    /// @dev Claim GS rewards on behalf of user
    /// @param _account User address for query
    /// @param _receiver Receiver of rewards
    /// @return Amount of GS rewards
    function claimForAccount(address _account, address _receiver) external returns (uint256);

    /// @dev Withdraw escrow tokens and cancel vesting
    /// @dev Refund pair tokens to user
    function withdraw() external;

    /// @dev Withdraw escrow tokens and cancel vesting on behalf of user
    /// @dev Refund pair tokens to user
    /// @param _account User address for query
    function withdrawForAccount(address _account) external;

    /// @param _account User address for query
    /// @return Claimable GS amounts
    function claimable(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Cumulative amounts of GS rewards
    function cumulativeClaimAmounts(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Total claimed GS amounts
    function claimedAmounts(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Pair token amounts for account
    function pairAmounts(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Total vested escrow token amounts
    function getVestedAmount(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Cumulative reward deduction amounts
    function cumulativeRewardDeductions(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Bonus reward amounts
    function bonusRewards(address _account) external view returns (uint256);

    /// @dev Penalty user GS rewards
    /// @param _account User address for query
    /// @param _amount Deduction GS amounts to apply
    function setCumulativeRewardDeductions(address _account, uint256 _amount) external;

    /// @dev Add bonus GS rewards
    /// @param _account User address for query
    /// @param _amount Bonus GS amounts to apply
    function setBonusRewards(address _account, uint256 _amount) external;

    /// @param _account User address for query
    /// @return Max vestable escrow token amounts based on reward tracker, bonus and deductions
    function getMaxVestableAmount(address _account) external view returns (uint256);

    /// @param _account User address for query
    /// @return Average staked amount of pair tokens required for vesting
    function getAverageStakedAmount(address _account) external view returns (uint256);
}

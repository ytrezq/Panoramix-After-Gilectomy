// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IPOLErrors } from "./IPOLErrors.sol";

interface IBGT is IPOLErrors, IERC20, IERC20Metadata, IVotes {
    /**
     * @notice Emitted when the minter address is changed.
     * @param previous The address of the previous minter.
     * @param current The address of the current minter.
     */
    event MinterChanged(address indexed previous, address indexed current);

    /**
     * @notice Emitted when the Staker address is changed.
     * @param previous The address of the previous Staker.
     * @param current The address of the current Staker.
     */
    event StakerChanged(address indexed previous, address indexed current);

    /**
     * @notice Emitted when an address is approved to send BGT.
     * @param sender The address of the sender.
     * @param approved Whether the sender is approved or not.
     */
    event SenderWhitelisted(address indexed sender, bool approved);

    /**
     * @notice Emitted when sender queues a new boost for a validator with an amount of BGT
     * @param user The address of the user.
     * @param pubkey The pubkey of the validator to be queued for boost.
     * @param amount The amount of BGT enqueued for boosting during function call.
     */
    event QueueBoost(address indexed user, bytes indexed pubkey, uint128 amount);

    /**
     * @notice Emitted when sender cancels a queued boost for a validator with an amount of BGT
     * @param user The address of the user.
     * @param pubkey The pubkey of the validator to be canceled from queued boosts.
     * @param amount The amount of BGT to cancel from queued boosts.
     */
    event CancelBoost(address indexed user, bytes indexed pubkey, uint128 amount);

    /**
     * @notice Emitted when sender activates a new boost for a validator
     * @param sender The address of the sender.
     * @param user The address of the user boosting.
     * @param pubkey The pubkey of the validator to be activated for the queued boosts.
     * @param amount The amount of BGT to boost with.
     */
    event ActivateBoost(address indexed sender, address indexed user, bytes indexed pubkey, uint128 amount);

    /**
     * @notice Emitted when an user queues a drop boost for a validator.
     * @param user The address of the user.
     * @param pubkey The pubkey of the validator to remove boost from.
     * @param amount The amount of BGT boost enqueued for dropping boost during function call.
     */
    event QueueDropBoost(address indexed user, bytes indexed pubkey, uint128 amount);

    /**
     * @notice Emitted when an user cancels a queued drop boost for a validator.
     * @param user The address of the user.
     * @param pubkey The pubkey of the validator to cancel drop boost for.
     * @param amount The amount of BGT boost to cancel.
     */
    event CancelDropBoost(address indexed user, bytes indexed pubkey, uint128 amount);

    /**
     * @notice Emitted when sender removes an amount of BGT boost from a validator
     * @param sender The address of the sender.
     * @param user The address of the user dropping boost.
     * @param pubkey The pubkey of the validator to remove boost from.
     * @param amount The amount of BGT boost to remove.
     */
    event DropBoost(address indexed sender, address indexed user, bytes indexed pubkey, uint128 amount);

    /**
     * @notice Emitted when the BGT token is redeemed for the native token.
     * @param from The address of the redeemer.
     * @param receiver The address of the receiver.
     * @param amount The amount of redeemed  BGT (and thus, of received BERA).
     */
    event Redeem(address indexed from, address indexed receiver, uint256 amount);

    /**
     * @notice Emitted when the activate boost delay is changed.
     * @param newDelay The new delay for activating boosts.
     */
    event ActivateBoostDelayChanged(uint32 newDelay);

    /**
     * @notice Emitted when the drop boost delay is changed.
     * @param newDelay The new delay for dropping boosts.
     */
    event DropBoostDelayChanged(uint32 newDelay);

    /**
     * @notice Emitted when the BGT terms and conditions are changed.
     * @param newTermsAndConditions The new terms and conditions.
     */
    event BgtTermsAndConditionsChanged(string newTermsAndConditions);

    /**
     * @notice Returns the BGT staker contract address.
     * @return The address of the staker.
     */
    function staker() external view returns (address);

    /**
     * @notice Returns the activate boost delay.
     * @return The activate boost delay.
     */
    function activateBoostDelay() external view returns (uint32);

    /**
     * @notice Returns the drop boost delay.
     * @return The drop boost delay.
     */
    function dropBoostDelay() external view returns (uint32);

    /**
     * @notice Emitted when the native token exceeding reserves are burnt.
     * @param caller The address of the caller.
     * @param amount The amount of BERA burnt.
     */
    event ExceedingReservesBurnt(address caller, uint256 amount);

    /**
     * @notice Approve an address to send BGT or approve another address to transfer BGT from it.
     * @dev This can only be called by the governance module.
     * @dev BGT should be soul bound to EOAs and only transferable by approved senders.
     * @param sender The address of the sender.
     * @param approved Whether the sender is approved or not.
     */
    function whitelistSender(address sender, bool approved) external;

    /**
     * @notice Mint BGT to the distributor.
     * @dev This can only be called by the minter address, which is set by governance.
     * @param distributor The address of the distributor.
     * @param amount The amount of BGT to mint.
     */
    function mint(address distributor, uint256 amount) external;

    /**
     * @notice Queues a new boost of the validator with an amount of BGT from `msg.sender`.
     * @dev Reverts if `msg.sender` does not have enough unboosted balance to cover amount.
     * @param pubkey The pubkey of the validator to be boosted.
     * @param amount The amount of BGT to use for the queued boost.
     */
    function queueBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Cancels a queued boost of the validator removing an amount of BGT for `msg.sender`.
     * @dev Reverts if `msg.sender` does not have enough queued balance to cover amount.
     * @param pubkey The pubkey of the validator to cancel boost for.
     * @param amount The amount of BGT to remove from the queued boost.
     */
    function cancelBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Boost the validator with an amount of BGT from `user`.
     * @param user The address of the user boosting.
     * @param pubkey The pubkey of the validator to be boosted.
     * @return bool False if amount is zero or if enough time has not passed, otherwise true.
     */
    function activateBoost(address user, bytes calldata pubkey) external returns (bool);

    /**
     * @notice Queues a drop boost of the validator removing an amount of BGT for sender.
     * @dev Reverts if `user` does not have enough boosted balance to cover amount.
     * @param pubkey The pubkey of the validator to remove boost from.
     * @param amount The amount of BGT to remove from the boost.
     */
    function queueDropBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Cancels a queued drop boost of the validator removing an amount of BGT for sender.
     * @param pubkey The pubkey of the validator to cancel drop boost for.
     * @param amount The amount of BGT to remove from the queued drop boost.
     */
    function cancelDropBoost(bytes calldata pubkey, uint128 amount) external;
    /**
     * @notice Drops an amount of BGT from an existing boost of validator by user.
     * @param user The address of the user to drop boost from.
     * @param pubkey The pubkey of the validator to remove boost from.
     * @return bool False if amount is zero or if enough time has not passed, otherwise true.
     */
    function dropBoost(address user, bytes calldata pubkey) external returns (bool);

    /**
     * @notice Returns the amount of BGT queued up to be used by an account to boost a validator.
     * @param account The address of the account boosting.
     * @param pubkey The pubkey of the validator being boosted.
     */
    function boostedQueue(
        address account,
        bytes calldata pubkey
    )
        external
        view
        returns (uint32 blockNumberLast, uint128 balance);

    /**
     * @notice Returns the amount of BGT queued up by an account to drop boost from a validator.
     * @param account The address of the account dropping boost.
     * @param pubkey The pubkey of the validator to drop boost for.
     */
    function dropBoostQueue(
        address account,
        bytes calldata pubkey
    )
        external
        view
        returns (uint32 blockNumberLast, uint128 balance);

    /**
     * @notice Returns the amount of BGT queued up to be used by an account for boosts.
     * @param account The address of the account boosting.
     */
    function queuedBoost(address account) external view returns (uint128);

    /**
     * @notice Returns the amount of BGT used by an account to boost a validator.
     * @param account The address of the account boosting.
     * @param pubkey The pubkey of the validator being boosted.
     */
    function boosted(address account, bytes calldata pubkey) external view returns (uint128);

    /**
     * @notice Returns the amount of BGT used by an account for boosts.
     * @param account The address of the account boosting.
     */
    function boosts(address account) external view returns (uint128);

    /**
     * @notice Returns the amount of BGT attributed to the validator for boosts.
     * @param pubkey The pubkey of the validator being boosted.
     */
    function boostees(bytes calldata pubkey) external view returns (uint128);

    /**
     * @notice Returns the total boosts for all validators.
     */
    function totalBoosts() external view returns (uint128);

    /**
     * @notice Returns the normalized boost power for the validator given outstanding boosts.
     * @dev Used by distributor get validator boost power.
     * @param pubkey The pubkey of the boosted validator.
     */
    function normalizedBoost(bytes calldata pubkey) external view returns (uint256);

    /**
     * @notice Public variable that represents the caller of the mint method.
     * @dev This is going to be the BlockRewardController contract at first.
     */
    function minter() external view returns (address);

    /**
     * @notice Set the minter address.
     * @dev This can only be called by the governance module.
     * @param _minter The address of the minter.
     */
    function setMinter(address _minter) external;

    /**
     * @notice Set the BGT staker contract address.
     * @param _staker The address of the staker.
     */
    function setStaker(address _staker) external;

    /**
     * @notice Set the activate boost delay.
     * @param _activateBoostDelay The new delay for activating boosts.
     */
    function setActivateBoostDelay(uint32 _activateBoostDelay) external;

    /**
     * @notice Set the drop boost delay.
     * @param _dropBoostDelay The new delay for dropping boosts.
     */
    function setDropBoostDelay(uint32 _dropBoostDelay) external;

    /**
     * @notice Redeem the BGT token for the native token at a 1:1 rate.
     * @param receiver The receiver's address who will receive the native token.
     * @param amount The amount of BGT to redeem.
     */
    function redeem(address receiver, uint256 amount) external;

    /**
     * @notice Returns the unboosted balance of an account.
     * @param account The address of the account.
     */
    function unboostedBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Burns the excess BERA held by this contract to redeem BGTs.
     * @dev Since CL at deployment is minting to this contract a quantity of native token sufficient to redeem
     * the upper bound of BGT production range, this contract may hold excess BERA. Can burn BERA exceeding
     * BGT.totalSupply() + outstanding rewards.
     */
    function burnExceedingReserves() external;
}

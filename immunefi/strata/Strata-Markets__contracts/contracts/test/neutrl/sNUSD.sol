// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Silo} from "./utils/Silo.sol";
import {SingleAdminAccessControl} from "./utils/SingleAdminAccessControl.sol";

struct UserCooldown {
    /// @notice The timestamp of the cooldown end
    uint104 cooldownEnd;
    /// @notice The amount of underlying tokens that are cooldown
    uint152 underlyingAmount;
}

/// @title sNUSD
/// @notice Staked NUSD token with cooldown, vesting, and blacklisting features
contract sNUSD is ERC4626, ERC20Permit, SingleAdminAccessControl, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidToken();
    error ZeroInput();
    error MinSharesViolation();
    error StillVesting();
    error OperationNotAllowed();
    error CooldownOff();
    error CooldownOn();
    error ExcessiveWithdrawAmount();
    error ExcessiveRedeemAmount();
    error InvalidCooldown();

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event VestingPeriodSet(uint256 vestingPeriod);
    event RewardsReceived(uint256 amount);
    event CooldownDurationSet(uint24 cooldownDuration);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    event Unstaked(address indexed staker, address indexed receiver, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 shares, uint256 assets, uint104 cooldownEnd);

    /*//////////////////////////////////////////////////////////////
                             STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The role that is allowed to distribute rewards to this contract
    bytes32 public constant REWARDER_ROLE = keccak256("REWARDER_ROLE");

    /// @notice The role that is allowed to blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice The role which prevents an address to stake
    bytes32 public constant SOFT_RESTRICTED_STAKER_ROLE = keccak256("SOFT_RESTRICTED_STAKER_ROLE");

    /// @notice The role which prevents an address to transfer, stake, or unstake. The owner of the contract can redirect address staking balance if an address is in full restricting mode.
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    /// @notice The role that is allowed to pause and unpause the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Minimum non-zero shares amount to prevent donation attack
    uint256 public constant MIN_SHARES = 1 ether;

    /// @notice NUSD address
    IERC20 public immutable nusd;

    /// @notice The silo contract
    Silo public immutable silo;

    /// @notice The vesting period of lastDistributionAmount over which it increasingly becomes available to stakers
    uint256 public vestingPeriod;

    /// @notice The amount of the last asset distribution from the controller contract into this
    /// contract + any unvested remainder at that time
    uint256 public vestingAmount;

    /// @notice The timestamp of the last asset distribution from the controller contract into this contract
    uint256 public lastDistributionTimestamp;

    /// @notice The cooldown duration
    uint24 public cooldownDuration;

    /// @notice The mapping of user cooldowns
    mapping(address => UserCooldown) public cooldowns;

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    constructor(address _NUSD, address _owner)
        ERC20("Staked NUSD", "sNUSD")
        ERC4626(IERC20(_NUSD))
        ERC20Permit("Staked NUSD")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        silo = new Silo(address(this), _NUSD);
        _setVestingPeriod(8 hours);
        _setCooldownDuration(30 days);
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency function to recover tokens accidentally sent to the contract
    /// @param token Address of the token to recover
    /// @param to Address to send the recovered tokens to
    /// @param amount Amount of tokens to recover
    function recoverToken(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(asset())) revert InvalidToken();
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Set vesting period.
    /// @param _vestingPeriod Duration of the vesting period
    function setVestingPeriod(uint256 _vestingPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 unvestedAmount = getUnvestedAmount();
        if (unvestedAmount > 0) revert StillVesting();
        vestingAmount = 0;

        _setVestingPeriod(_vestingPeriod);
    }

    /// @notice Set cooldown duration. If cooldown duration is set to zero, the behavior changes
    /// to follow ERC4626 standard and disables cooldownShares and cooldownAssets methods.
    /// If cooldown duration is greater than zero, the ERC4626 withdrawal and redeem functions are disabled,
    /// breaking the ERC4626 standard, and enabling the cooldownShares and the cooldownAssets functions.
    /// @param _cooldownDuration Duration of the cooldown
    function setCooldownDuration(uint24 _cooldownDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setCooldownDuration(_cooldownDuration);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Redistributes the locked amount from one address to another
    /// @param from The address to burn the entire balance, with the FULL_RESTRICTED_STAKER_ROLE
    /// @param to The address to mint the entire balance of "from" parameter.
    /// @param amountToDistribute The amount of tokens to redistribute.
    function redistributeLockedAmount(address from, address to, uint256 amountToDistribute)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from) && !hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
            if (amountToDistribute == 0) revert ZeroInput();
            uint256 nusdToVest = previewRedeem(amountToDistribute);
            _burn(from, amountToDistribute);
            // to address of address(0) enables burning
            if (to == address(0)) {
                _updateVestingAmount(nusdToVest);
            } else {
                _mint(to, amountToDistribute);
            }
            emit LockedAmountRedistributed(from, to, amountToDistribute);
        } else {
            revert OperationNotAllowed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    ///@notice Allows the owner to transfer rewards from the controller contract into this contract.
    ///@param _amount The amount of rewards to transfer.
    ///@dev This function is called by the YieldDistributor contract
    function transferInRewards(uint256 _amount) external onlyRole(REWARDER_ROLE) {
        if (_amount == 0) revert ZeroInput();
        _updateVestingAmount(_amount);

        // Transfer assets from rewarder to this contract
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardsReceived(_amount);
    }

    /// @notice Allows  blacklist managers to blacklist addresses.
    /// @param target The address to blacklist.
    /// @param isFullBlacklisting Soft or full blacklisting level.
    function addToBlacklist(address target, bool isFullBlacklisting) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        bytes32 role = isFullBlacklisting ? FULL_RESTRICTED_STAKER_ROLE : SOFT_RESTRICTED_STAKER_ROLE;
        _grantRole(role, target);
    }

    /// @notice Allows blacklist managers to un-blacklist addresses.
    /// @param target The address to un-blacklist.
    /// @param isFullBlacklisting Soft or full blacklisting level.
    function removeFromBlacklist(address target, bool isFullBlacklisting) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        bytes32 role = isFullBlacklisting ? FULL_RESTRICTED_STAKER_ROLE : SOFT_RESTRICTED_STAKER_ROLE;
        _revokeRole(role, target);
    }

    /*//////////////////////////////////////////////////////////////
                             ERC4626
    //////////////////////////////////////////////////////////////*/

    /// @dev See {IERC4626-deposit}.
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @dev See {IERC4626-mint}.
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @dev See {IERC4626-withdraw}.
    function withdraw(uint256 assets, address receiver, address _owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        if (cooldownDuration != 0) revert CooldownOn();
        return super.withdraw(assets, receiver, _owner);
    }

    /// @dev See {IERC4626-redeem}.
    function redeem(uint256 shares, address receiver, address _owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        if (cooldownDuration != 0) revert CooldownOn();
        return super.redeem(shares, receiver, _owner);
    }

    /// @notice Claim the staking amount after the cooldown has finished. The address can only retire the full amount of assets.
    /// @dev unstake can be called after cooldown have been set to 0, to let accounts to be able to claim remaining assets locked at Silo
    /// @param receiver Address to send the assets by the staker
    function unstake(address receiver) external whenNotPaused {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, msg.sender) || hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver)) {
            revert OperationNotAllowed();
        }

        UserCooldown storage userCooldown = cooldowns[msg.sender];
        uint256 assets = userCooldown.underlyingAmount;
        if (assets == 0) revert ZeroInput();

        if (block.timestamp >= userCooldown.cooldownEnd || cooldownDuration == 0) {
            userCooldown.cooldownEnd = 0;
            userCooldown.underlyingAmount = 0;

            silo.withdraw(receiver, assets);
        } else {
            revert InvalidCooldown();
        }

        emit Unstaked(msg.sender, receiver, assets);
    }

    /// @notice Redeem assets and starts a cooldown to claim the converted underlying asset
    /// @param assets assets to redeem
    function cooldownAssets(uint256 assets) external whenNotPaused returns (uint256 shares) {
        if (cooldownDuration == 0) revert CooldownOff();
        if (assets > maxWithdraw(msg.sender)) revert ExcessiveWithdrawAmount();

        shares = previewWithdraw(assets);

        uint104 newCooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[msg.sender].cooldownEnd =
            cooldowns[msg.sender].cooldownEnd > newCooldownEnd ? cooldowns[msg.sender].cooldownEnd : newCooldownEnd;
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
        emit UnstakeRequested(msg.sender, shares, assets, cooldowns[msg.sender].cooldownEnd);
    }

    /// @notice Redeem shares into assets and starts a cooldown to claim the converted underlying asset
    /// @param shares shares to redeem
    function cooldownShares(uint256 shares) external whenNotPaused returns (uint256 assets) {
        if (cooldownDuration == 0) revert CooldownOff();
        if (shares > maxRedeem(msg.sender)) revert ExcessiveRedeemAmount();

        assets = previewRedeem(shares);

        uint104 newCooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[msg.sender].cooldownEnd =
            cooldowns[msg.sender].cooldownEnd > newCooldownEnd ? cooldowns[msg.sender].cooldownEnd : newCooldownEnd;
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
        emit UnstakeRequested(msg.sender, shares, assets, cooldowns[msg.sender].cooldownEnd);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the amount of NUSD tokens that are vested in the contract.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - getUnvestedAmount();
    }

    /// @notice Returns the amount of NUSD tokens that are unvested in the contract.
    function getUnvestedAmount() public view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - lastDistributionTimestamp;

        if (timeSinceLastDistribution >= vestingPeriod) {
            return 0;
        }

        uint256 deltaT = (vestingPeriod - timeSinceLastDistribution);
        return (deltaT * vestingAmount) / vestingPeriod;
    }

    /// @notice Returns the number of decimals of the token
    function decimals() public pure override(ERC4626, ERC20) returns (uint8) {
        return 18;
    }

    /// @notice Prevents users from renouncing roles
    function renounceRole(bytes32, address) public virtual override {
        revert OperationNotAllowed();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Deposit/mint common workflow.
    /// @param caller sender of assets
    /// @param receiver where to send shares
    /// @param assets assets to deposit
    /// @param shares shares to mint
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (
            hasRole(SOFT_RESTRICTED_STAKER_ROLE, caller) || hasRole(SOFT_RESTRICTED_STAKER_ROLE, receiver)
                || hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) || hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver)
        ) {
            revert OperationNotAllowed();
        }
        if (assets == 0 || shares == 0) revert ZeroInput();
        super._deposit(caller, receiver, assets, shares);
        _checkMinShares();
    }

    /// @dev Withdraw/redeem common workflow.
    /// @param caller tx sender
    /// @param receiver where to send assets
    /// @param _owner where to burn shares from
    /// @param assets asset amount to transfer out
    /// @param shares shares to burn
    function _withdraw(address caller, address receiver, address _owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (
            hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) || hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver)
                || hasRole(FULL_RESTRICTED_STAKER_ROLE, _owner)
        ) {
            revert OperationNotAllowed();
        }
        if (assets == 0 || shares == 0) revert ZeroInput();

        super._withdraw(caller, receiver, _owner, assets, shares);
        _checkMinShares();
    }

    /// @notice Prevents blacklisted addresses from transferring tokens
    function _update(address from, address to, uint256 value) internal override {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from) && to != address(0)) {
            revert OperationNotAllowed();
        }
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
            revert OperationNotAllowed();
        }
        super._update(from, to, value);
    }

    /// @notice Ensures a small non-zero amount of shares does not remain, exposing to donation attack
    function _checkMinShares() internal view {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0 && _totalSupply < MIN_SHARES) {
            revert MinSharesViolation();
        }
    }

    /// @notice Updates the vesting amount and last distribution timestamp
    /// @param _newVestingAmount The new vesting amount
    function _updateVestingAmount(uint256 _newVestingAmount) internal {
        if (getUnvestedAmount() > 0) revert StillVesting();

        vestingAmount = _newVestingAmount;
        lastDistributionTimestamp = block.timestamp;
    }

    function _setVestingPeriod(uint256 _vestingPeriod) internal {
        vestingPeriod = _vestingPeriod;
        emit VestingPeriodSet(_vestingPeriod);
    }

    function _setCooldownDuration(uint24 _cooldownDuration) internal {
        cooldownDuration = _cooldownDuration;
        emit CooldownDurationSet(_cooldownDuration);
    }
}

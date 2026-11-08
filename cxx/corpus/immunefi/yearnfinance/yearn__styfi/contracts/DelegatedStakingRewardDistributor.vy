# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Delegated Staking Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice Tracks staking balances through the hook. Rewards are claimed from the StakingRewardDistributor 
        directly before a state change. They are passed through to the user in proportion to their share
        of deposits.
"""

from ethereum.ercs import IERC20

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

interface IStakingDistributor:
    def genesis() -> uint256: view
    def claim(_account: address) -> uint256: nonpayable

implements: IHooks

struct Accrued:
    count: uint256
    claimed: uint256

struct AccruedEntry:
    epoch: uint256
    accrued: uint256

struct IntegralSnapshot:
    epoch: uint256
    integral: uint256

genesis: public(immutable(uint256))
token: public(immutable(IERC20))
management: public(address)
pending_management: public(address)

depositor: public(address)
staking: public(IERC20)
distributor: public(IStakingDistributor)
distributor_claim: public(address)
claimers: public(HashMap[address, bool])
reward_expiration: public(uint256)
reclaim_bounty: public(uint256)
reclaim_recipient: public(address)

reward_integral: public(uint256)
account_reward_integral: public(HashMap[address, uint256])
accrued_rewards: public(HashMap[address, Accrued])
accrued_reward_entries: public(HashMap[address, HashMap[uint256, AccruedEntry]]) # account => idx => entry

reward_integral_snapshot_max_index: public(uint256)
reward_integral_snapshot: public(HashMap[uint256, IntegralSnapshot])

event Claim:
    account: indexed(address)
    rewards: uint256

event Reclaim:
    caller: indexed(address)
    account: indexed(address)
    rewards: uint256
    bounty: uint256

event SetDepositor:
    depositor: indexed(address)

event SetStaking:
    staking: indexed(address)

event SetDistributor:
    distributor: indexed(address)

event SetDistributorClaim:
    claim: indexed(address)

event SetClaimer:
    account: indexed(address)
    claimer: bool

event SetRewardExpiration:
    expiration: uint256
    bounty: uint256
    recipient: address

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
PRECISION: constant(uint256) = 10**30
BOUNTY_PRECISION: constant(uint256) = 10_000

@deploy
def __init__(_distributor: address, _token: address):
    """
    @notice Constructor
    @param _distributor The distributor address
    @param _token The address of the reward token
    """
    genesis = staticcall IStakingDistributor(_distributor).genesis()
    token = IERC20(_token)

    self.management = msg.sender
    self.distributor = IStakingDistributor(_distributor)
    self.reward_expiration = 26
    self.reclaim_recipient = msg.sender

@external
def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon transfer of tokens
    @param _caller Originator of the transfer
    @param _from Sender of the token
    @param _to Recipient of the tokens
    @param _supply Total token supply
    @param _prev_staked_from Staked balance of sender before transfer
    @param _prev_staked_to Staked balance of recipient before transfer
    @param _amount Amount of tokens to transfer
    """
    assert msg.sender == self.depositor
    self._sync_integral(_supply)
    self._sync_account_integral(_from, _prev_staked_from)
    self._sync_account_integral(_to, _prev_staked_to)

@external
def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon staking of tokens
    @param _caller Originator of the tokens
    @param _account Recipient of the staked tokens
    @param _prev_supply Total token supply before stake
    @param _prev_staked Staked balance of recipient before stake
    @param _amount Amount of tokens to stake
    """
    assert msg.sender == self.depositor
    self._sync_integral(_prev_supply)
    self._sync_account_integral(_account, _prev_staked)

@external
def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon unstaking of tokens
    @param _account Originator of the staked tokens
    @param _prev_supply Total token supply before unstake
    @param _prev_staked Staked balance of originator before unstake
    @param _amount Amount of tokens to unstake
    """
    assert msg.sender == self.depositor
    self._sync_integral(_prev_supply)
    self._sync_account_integral(_account, _prev_staked)

@external
def sync_rewards(_account: address = empty(address)):
    """
    @notice Synchronize global rewards up until now
    @param _account Also update rewards for this specific account (optional)
    """
    supply: uint256 = staticcall self.staking.totalSupply()
    self._sync_integral(supply)
    if _account != empty(address):
        staked: uint256 = staticcall self.staking.balanceOf(_account)
        self._sync_account_integral(_account, staked)

@external
def claim(_account: address) -> uint256:
    """
    @notice Claim rewards on behalf of an account
    @param _account Account to claim rewards for
    @return Amount of rewards tokens claimed
    """
    if self.accrued_rewards[_account].count == 0:
        # shortcut accounts that are guaranteed to have no rewards
        return 0

    assert self.claimers[msg.sender]
    supply: uint256 = staticcall self.staking.totalSupply()
    self._sync_integral(supply)
    staked: uint256 = staticcall self.staking.balanceOf(_account)
    accrued: uint256 = self._sync_account_integral(_account, staked)
    pending: uint256 = accrued - self.accrued_rewards[_account].claimed

    if pending > 0:
        self.accrued_rewards[_account].claimed = accrued
        assert extcall token.transfer(msg.sender, pending, default_return_value=True)
        log Claim(account=_account, rewards=pending)

    return pending

@external
@view
def pending_rewards(_account: address) -> uint256:
    """
    @notice Query pending rewards
    @param _account Account to query pending rewards for
    @return Amount of pending rewards tokens
    @dev Does not include earned rewards since last account state change
    """
    idx: uint256 = self.accrued_rewards[_account].count
    if idx == 0:
        return 0
    idx -= 1
    accrued: uint256 = self.accrued_reward_entries[_account][idx].accrued
    return accrued - self.accrued_rewards[_account].claimed

@external
def reclaim(_account: address, _snapshot_idx: uint256, _accrued_idx: uint256 = max_value(uint256)) -> (uint256, uint256):
    """
    @notice Reclaim expired rewards
    @param _account Account to reclaim rewards for
    @param _snapshot_idx The index of the snapshot
    @param _accrued_idx Index of accrued rewards to reclaim from (optional)
    @return Tuple with amount of rewards reclaimed and bounty amount received
    """
    supply: uint256 = staticcall self.staking.totalSupply()
    self._sync_integral(supply)
    assert _snapshot_idx <= self.reward_integral_snapshot_max_index

    count: uint256 = self.accrued_rewards[_account].count
    assert count > 0
    assert _accrued_idx == max_value(uint256) or _accrued_idx < count

    expiration: uint256 = self.reward_expiration
    epoch: uint256 = self._epoch()
    if epoch < expiration:
        return 0, 0
    epoch -= expiration

    # reclaim based on snapshotted accrued rewards
    rewards: uint256 = 0
    if _accrued_idx < max_value(uint256):
        assert self.accrued_reward_entries[_account][_accrued_idx].epoch <= epoch
        accrued: uint256 = self.accrued_reward_entries[_account][_accrued_idx].accrued
        claimed: uint256 = self.accrued_rewards[_account].claimed
        if claimed < accrued:
            rewards = accrued - claimed
            self.accrued_rewards[_account].claimed = accrued

    # reclaim based on snapshotted integral
    snapshot_epoch: uint256 = self.reward_integral_snapshot[_snapshot_idx].epoch
    assert snapshot_epoch <= epoch

    integral: uint256 = self.reward_integral_snapshot[_snapshot_idx].integral
    account_integral: uint256 = self.account_reward_integral[_account]
    if account_integral < integral:
        staked: uint256 = staticcall self.staking.balanceOf(_account)
        rewards += (integral - account_integral) * staked // PRECISION
        self.account_reward_integral[_account] = integral

    if rewards == 0:
        return 0, 0

    bounty: uint256 = rewards * self.reclaim_bounty // BOUNTY_PRECISION
    log Reclaim(caller=msg.sender, account=_account, rewards=rewards, bounty=bounty)

    if bounty > 0:
        rewards -= bounty
        assert extcall token.transfer(msg.sender, bounty, default_return_value=True)

    if rewards > 0:
        assert extcall token.transfer(self.reclaim_recipient, rewards, default_return_value=True)

    return rewards, bounty

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    """
    @notice Transfer out a token
    @param _token The token address
    @param _amount The amount of tokens. Defaults to all
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC20(_token).balanceOf(self)

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_depositor(_depositor: address):
    """
    @notice Set the depositor
    @param _depositor Depositor address
    @dev Can only be called by management
    @dev Caller is responsible for ensuring consistency between the old and new depositor
    """
    assert msg.sender == self.management

    self.depositor = _depositor
    log SetDepositor(depositor=_depositor)

@external
def set_staking(_staking: address):
    """
    @notice Set the staking address
    @param _staking Staking address
    @dev Can only be called by management
    @dev Caller is responsible for ensuring consistency between the depositor and staking contract
    """
    assert msg.sender == self.management

    self.staking = IERC20(_staking)
    log SetStaking(staking=_staking)

@external
def set_distributor(_distributor: address):
    """
    @notice Set upstream staking reward distributor
    @param _distributor Distributor address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.distributor = IStakingDistributor(_distributor)
    log SetDistributor(distributor=_distributor)

@external
def set_distributor_claim(_claim: address):
    """
    @notice Set address to claim rewards for. Should normally be set to the depositor,
            unless middleware has been injected
    @param _claim The address to claim rewards on behalf of
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.distributor_claim = _claim
    log SetDistributorClaim(claim=_claim)

@external
def set_claimer(_account: address, _claimer: bool):
    """
    @notice Whitelist account as reward claimer
    @param _account Account
    @param _claimer True: add to whitelist, False: remove from whitelist
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.claimers[_account] = _claimer
    log SetClaimer(account=_account, claimer=_claimer)

@external
def set_reward_expiration(_expiration: uint256, _bounty: uint256, _recipient: address):
    """
    @notice Set reward expiration parameters
    @param _expiration Number of epochs after which rewards can be reclaimed
    @param _bounty Bounty (in bps) to give to the caller
    @param _recipient Recipient of the reclaimed rewards
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _expiration > 1
    assert _bounty <= BOUNTY_PRECISION
    assert _recipient != empty(address) or _bounty == BOUNTY_PRECISION

    self.reward_expiration = _expiration
    self.reclaim_bounty = _bounty
    self.reclaim_recipient = _recipient
    log SetRewardExpiration(expiration=_expiration, bounty=_bounty, recipient=_recipient)

@external
def set_management(_management: address):
    """
    @notice Set the pending management address.
            Needs to be accepted by that account separately to transfer management over
    @param _management New pending management address
    """
    assert msg.sender == self.management

    self.pending_management = _management
    log PendingManagement(management=_management)

@external
def accept_management():
    """
    @notice Accept management role.
            Can only be called by account previously marked as pending by current management
    """
    assert msg.sender == self.pending_management

    self.pending_management = empty(address)
    self.management = msg.sender
    log SetManagement(management=msg.sender)

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

@internal
def _sync_integral(_supply: uint256):
    """
    @notice Claim rewards and update integral
    """
    if _supply < 10**12:
        # rewards only accrue when there are depositors
        return

    rewards: uint256 = extcall self.distributor.claim(self.distributor_claim)
    if rewards == 0:
        return

    integral: uint256 = self.reward_integral + rewards * PRECISION // _supply
    self.reward_integral = integral

    idx: uint256 = self.reward_integral_snapshot_max_index
    epoch: uint256 = self._epoch()
    if epoch > self.reward_integral_snapshot[idx].epoch:
        idx += 1
        self.reward_integral_snapshot_max_index = idx
        self.reward_integral_snapshot[idx].epoch = epoch
    self.reward_integral_snapshot[idx].integral = integral

@internal
def _sync_account_integral(_account: address, _staked: uint256) -> uint256:
    """
    @notice Sync integral for a specific account
            Global integral should be synced prior to calling this
    """
    epoch: uint256 = self._epoch()
    integral: uint256 = self.reward_integral

    idx: uint256 = self.accrued_rewards[_account].count
    if idx == 0:
        # no entries yet
        idx = 1
        self.accrued_rewards[_account].count = 1
        self.accrued_reward_entries[_account][0].epoch = epoch
    idx -= 1

    accrued: uint256 = self.accrued_reward_entries[_account][idx].accrued
    if _staked > 0:
        if epoch > self.accrued_reward_entries[_account][idx].epoch:
            # new epoch, new entry
            idx += 1
            self.accrued_rewards[_account].count = idx + 1
            self.accrued_reward_entries[_account][idx].epoch = epoch

        accrued += (integral - self.account_reward_integral[_account]) * _staked // PRECISION
        self.accrued_reward_entries[_account][idx].accrued = accrued

    self.account_reward_integral[_account] = integral
    return accrued

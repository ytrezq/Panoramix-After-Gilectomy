# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Staking Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice A component to the RewardDistributor. It tracks staking balances through the stYFI hook
        and snapshots the total staked balance each epoch to report as its reward weight.
        Rewards are claimed from the distributor as they become available and streamed over the
        following epoch to all stakers, proportional to their current balance.
"""

from ethereum.ercs import IERC20

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def instant_withdrawal(_account: address) -> bool: view

interface IComponent:
    def sync_total_weight(_epoch: uint256) -> uint256: nonpayable

interface IDistributor:
    def genesis() -> uint256: view
    def claim() -> (uint256, uint256, uint256): nonpayable

implements: IHooks
implements: IComponent

struct Weight:
    epoch: uint256
    time: uint256
    weight: uint256

struct TotalWeight:
    epoch: uint256
    weight: uint256

struct Cursor:
    count: uint256
    last: uint256

struct Rewards:
    timestamp: uint256
    rewards: uint256

struct Accrued:
    count: uint256
    claimed: uint256

struct AccruedEntry:
    epoch: uint256
    accrued: uint256

genesis: public(immutable(uint256))
token: public(immutable(IERC20))
management: public(address)
pending_management: public(address)

depositor: public(address)
staking: public(IERC20)
distributor: public(IDistributor)
claimers: public(HashMap[address, bool])
reward_expiration: public(uint256)
reclaim_bounty: public(uint256)
reclaim_recipient: public(address)
reclaim_disabled: public(HashMap[address, bool])

total_weight_cursor: public(Cursor)
total_weight_entries: public(HashMap[uint256, TotalWeight])

epoch_rewards: public(Rewards)
reward_integral: public(uint256)
reward_integral_snapshot: public(HashMap[uint256, uint256])
account_reward_integral: public(HashMap[address, uint256])
accrued_rewards: public(HashMap[address, Accrued])
accrued_reward_entries: public(HashMap[address, HashMap[uint256, AccruedEntry]]) # account => idx => entry

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

event SetClaimer:
    account: indexed(address)
    claimer: bool

event SetRewardExpiration:
    expiration: uint256
    bounty: uint256
    recipient: address

event SetReclaimDisabled:
    account: indexed(address)
    disabled: bool

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
RAMP_LENGTH: constant(uint256) = 4 * EPOCH_LENGTH
INCREMENT: constant(bool) = True
DECREMENT: constant(bool) = False
PRECISION: constant(uint256) = 10**30
BOUNTY_PRECISION: constant(uint256) = 10_000

@deploy
def __init__(_distributor: address, _token: address):
    """
    @notice Constructor
    @param _distributor The distributor address
    @param _token The address of the reward token
    """
    genesis = staticcall IDistributor(_distributor).genesis()
    token = IERC20(_token)

    self.management = msg.sender
    self.distributor = IDistributor(_distributor)
    self.total_weight_cursor = Cursor(count=1, last=0)
    self.total_weight_entries[0] = TotalWeight(epoch=0, weight=10**12)
    self.reward_expiration = 26
    self.reclaim_recipient = msg.sender

@external
@view
def epoch() -> uint256:
    """
    @notice Query the current epoch number
    @return The current epoch number
    """
    return self._epoch()

@external
def sync_total_weight(_epoch: uint256) -> uint256:
    """
    @notice Compute and finalize the total weight for reward distribution purposes
    @param _epoch The epoch to compute the total weight for
    @return The total weight for this epoch
    @dev Can only be called by the distributor
    """
    assert msg.sender == self.distributor.address
    cursor: Cursor = self.total_weight_cursor
    
    weight: uint256 = 0
    next_idx: uint256 = cursor.last + 1
    if next_idx == cursor.count:
        # already at last entry
        weight = self.total_weight_entries[cursor.last].weight
    else:
        # peek into next entry
        next: TotalWeight = self.total_weight_entries[next_idx]
        if _epoch < next.epoch:
            # next entry is for a future epoch, keep using current entry
            weight = self.total_weight_entries[cursor.last].weight
        else:
            # update cursor
            self.total_weight_cursor.last = next_idx

            weight = next.weight
    return weight

@external
def sync_rewards(_account: address = empty(address)) -> bool:
    """
    @notice Synchronize global rewards up until now
    @param _account Also update rewards for this specific account (optional)
    @return True: rewards are fully synced, False: not fully synced
    """
    synced: bool = self._sync_integral()
    if _account != empty(address):
        staked: uint256 = staticcall self.staking.balanceOf(_account)
        self._sync_account_integral(_account, staked)
    return synced

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
    assert self._sync_integral()
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
    assert self._sync_integral()
    self._update_total_weight(_amount, INCREMENT)
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
    assert self._sync_integral()
    self._update_total_weight(_amount, DECREMENT)
    self._sync_account_integral(_account, _prev_staked)

@external
@view
def instant_withdrawal(_account: address) -> bool:
    """
    @notice Query instant withdrawal status of an account
    @param _account Account to query withdrawal status for
    @return Always False
    """
    return False

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
    assert self._sync_integral()
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
def reclaim(_account: address, _idx: uint256 = max_value(uint256)) -> (uint256, uint256):
    """
    @notice Reclaim expired rewards
    @param _account Account to reclaim rewards for
    @param _idx Index of accrued rewards to reclaim from (optional)
    @return Tuple with amount of rewards reclaimed and bounty amount received
    """
    assert not self.reclaim_disabled[_account]
    assert self._sync_integral()
    count: uint256 = self.accrued_rewards[_account].count
    assert count > 0
    assert _idx == max_value(uint256) or _idx < count

    expiration: uint256 = self.reward_expiration
    epoch: uint256 = self._epoch()
    if epoch < expiration:
        return 0, 0
    epoch -= expiration

    # reclaim based on snapshotted accrued rewards
    rewards: uint256 = 0
    if _idx < max_value(uint256):
        assert self.accrued_reward_entries[_account][_idx].epoch <= epoch
        accrued: uint256 = self.accrued_reward_entries[_account][_idx].accrued
        claimed: uint256 = self.accrued_rewards[_account].claimed
        if claimed < accrued:
            rewards = accrued - claimed
            self.accrued_rewards[_account].claimed = accrued

    # reclaim from rewards since last state change
    integral: uint256 = self.reward_integral_snapshot[epoch]
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
    @notice Set upstream reward distributor
    @param _distributor Distributor address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.distributor = IDistributor(_distributor)
    log SetDistributor(distributor=_distributor)

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
def set_reclaim_disabled(_account: address, _disabled: bool):
    """
    @notice Set reclaim disable flag
    @param _account Address to set the flag for
    @param _disabled True: disable reclaims for account, False: enable reclaims
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    self.reclaim_disabled[_account] = _disabled
    log SetReclaimDisabled(account=_account, disabled=_disabled)

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
def _update_total_weight(_amount: uint256, _increment: bool):
    """
    @notice Increase or decrease the total weight.
            Global integral must be synced before calling
    """
    current_epoch: uint256 = self._epoch()

    # load latest total weight
    count: uint256 = self.total_weight_cursor.count
    idx: uint256 = count - 1
    weight: TotalWeight = self.total_weight_entries[idx]

    if current_epoch > weight.epoch:
        # new epoch, add entry to list
        idx = count
        weight.epoch = current_epoch
        self.total_weight_cursor.count = count + 1

    if _increment == INCREMENT:
        weight.weight += _amount
    else:
        weight.weight -= _amount

    self.total_weight_entries[idx] = weight

@internal
def _sync_integral() -> bool:
    """
    @notice Sync global integral to the latest value
    """
    current_epoch: uint256 = self._epoch()

    unlocked: uint256 = 0
    ew: Rewards = self.epoch_rewards
    epoch: uint256 = unsafe_div(ew.timestamp, EPOCH_LENGTH)
    synced: bool = epoch == current_epoch
    last_streamed: uint256 = (ew.timestamp % EPOCH_LENGTH) * ew.rewards // EPOCH_LENGTH
    ew.timestamp = block.timestamp - genesis
    total_weight: uint256 = self.total_weight_entries[self.total_weight_cursor.count - 1].weight
    integral: uint256 = self.reward_integral

    if not synced:
        # rollover to new epoch. first finalize the last one
        unlocked = ew.rewards - last_streamed
        last_streamed = 0

        # save integral snapshot
        self.reward_integral_snapshot[epoch] = integral + unlocked * PRECISION // total_weight

        # fast forward through any other completed epochs
        distributor: IDistributor = self.distributor
        epoch_rewards: uint256 = 0
        for i: uint256 in range(32):
            epoch += 1
            epoch_rewards = (extcall distributor.claim())[2]
            synced = epoch == current_epoch
            if synced:
                break
            else:
                unlocked += epoch_rewards
                self.reward_integral_snapshot[epoch] = integral + unlocked * PRECISION // total_weight

        if synced:
            # fully caught up
            ew.rewards = epoch_rewards
        else:
            # not fully caught up. we already added the full amount to `unlocked`, so we 
            # zero out the epoch rewards to not double count it in the next call
            ew.timestamp = epoch * EPOCH_LENGTH
            ew.rewards = 0

    self.epoch_rewards = ew

    streamed: uint256 = (ew.timestamp % EPOCH_LENGTH) * ew.rewards // EPOCH_LENGTH
    unlocked += streamed - last_streamed
    if unlocked == 0:
        return synced

    # update integral
    self.reward_integral = integral + unlocked * PRECISION // total_weight

    return synced

@internal
def _sync_account_integral(_account: address, _staked: uint256) -> uint256:
    """
    @notice Sync integral of a specific account to the latest value
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

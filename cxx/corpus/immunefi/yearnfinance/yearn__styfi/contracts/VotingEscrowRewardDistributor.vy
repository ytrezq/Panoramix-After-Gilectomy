# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Voting Escrow Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice A component to the RewardDistributor. It tracks migrated veYFI positions and reports
        the total weight (with decaying boost) as its reward weight.
        Rewards are claimed from the distributor as they become available and streamed over the
        following epoch to all positions proportional to their weight, determined by the 
        duration of their lock at time of snapshot.
"""

from ethereum.ercs import IERC20

interface IComponent:
    def sync_total_weight(_epoch: uint256) -> uint256: nonpayable

interface IDistributor:
    def genesis() -> uint256: view
    def claim() -> (uint256, uint256, uint256): nonpayable

interface IVotingEscrow:
    def locked(_account: address) -> (uint256, uint256): view

implements: IComponent

struct Lock:
    amount: uint256
    boost_epochs: uint256
    unlock_time: uint256

struct Unlock:
    amount: uint256
    slope_change: uint256

struct Weight:
    weight: uint256
    slope: uint256

genesis: public(immutable(uint256))
token: public(immutable(IERC20))
veyfi: public(immutable(IVotingEscrow))
management: public(address)
pending_management: public(address)

distributor: public(IDistributor)
claimers: public(HashMap[address, bool])
reward_expiration: public(uint256)
reclaim_bounty: public(uint256)
reclaim_recipient: public(address)
report_bounty: public(uint256)
report_recipient: public(address)

last_epoch: public(uint256)
reward_epoch: public(uint256)
total_weights: public(HashMap[uint256, Weight]) # epoch => total weight
unlocks: public(HashMap[uint256, Unlock]) # epoch => unlock
rewards: public(HashMap[uint256, uint256]) # epoch => rewards

locks: public(HashMap[address, Lock]) # account => lock
last_claimed: public(HashMap[address, uint256]) # account => last claim time

event Migrate:
    account: indexed(address)
    unlock_epoch: uint256
    amount: uint256

event Claim:
    account: indexed(address)
    rewards: uint256

event Reclaim:
    caller: indexed(address)
    account: indexed(address)
    rewards: uint256
    bounty: uint256

event Report:
    caller: indexed(address)
    account: indexed(address)
    rewards: uint256
    bounty: uint256

event SetSnapshot:
    account: indexed(address)
    amount: uint256
    boost: uint256
    unlock: uint256

event SetDistributor:
    distributor: indexed(address)

event SetClaimer:
    account: indexed(address)
    claimer: bool

event SetRewardExpiration:
    expiration: uint256
    bounty: uint256
    recipient: address

event SetReportBounty:
    bounty: uint256
    recipient: address

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
MAX_NUM_EPOCHS: constant(uint256) = 104
BOUNTY_PRECISION: constant(uint256) = 10_000

@deploy
def __init__(_distributor: address, _token: address, _veyfi: address):
    """
    @notice Constructor
    @param _distributor The distributor address
    @param _token The address of the reward token
    @param _veyfi veYFI address
    """
    genesis = staticcall IDistributor(_distributor).genesis()
    token = IERC20(_token)
    veyfi = IVotingEscrow(_veyfi)
    self.management = msg.sender
    self.distributor = IDistributor(_distributor)

    self.total_weights[0] = Weight(weight=10**12, slope=0)
    self.reward_expiration = 26
    self.reclaim_recipient = msg.sender
    self.report_recipient = msg.sender

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
    """
    current: uint256 = self._epoch()
    assert _epoch <= current

    self._sync_total_weights(current)
    assert self.last_epoch >= _epoch

    return self.total_weights[_epoch].weight

@external
def migrate():
    """
    @notice Migrate a veYFI position
    """
    assert self.last_claimed[msg.sender] == 0
    current: uint256 = self._epoch()
    assert self._sync_total_weights(current)

    amount: uint256 = 0
    unlock_time: uint256 = 0
    amount, unlock_time = self._check_lock(msg.sender)
    assert amount > 0

    boost_epochs: uint256 = self.locks[msg.sender].boost_epochs
    unlock_epoch: uint256 = (unlock_time - genesis) // EPOCH_LENGTH
    assert unlock_epoch > current

    # add lock to total
    slope: uint256 = amount // MAX_NUM_EPOCHS
    self.total_weights[current].weight += amount + (boost_epochs - current) * slope
    self.total_weights[current].slope += slope

    # schedule unlock
    self.unlocks[unlock_epoch].amount += amount + (boost_epochs - unlock_epoch) * slope
    self.unlocks[unlock_epoch].slope_change += slope

    # set claim time to beginning of next epoch
    self.last_claimed[msg.sender] = genesis + (current + 1) * EPOCH_LENGTH

    log Migrate(account=msg.sender, unlock_epoch=unlock_epoch, amount=amount)

@external
def claim(_account: address) -> uint256:
    """
    @notice Claim rewards on behalf of an account
    @param _account Account to claim rewards for
    @return Amount of rewards tokens claimed
    """
    assert self.claimers[msg.sender]
    assert self._sync_rewards(self._epoch())

    rewards: uint256 = self._claim(_account, block.timestamp)
    if rewards > 0:
        assert extcall token.transfer(msg.sender, rewards, default_return_value=True)
        log Claim(account=_account, rewards=rewards)

    return rewards

@external
def reclaim(_account: address) -> (uint256, uint256):
    """
    @notice Reclaim expired rewards
    @param _account Account to reclaim rewards for
    @return Tuple with amount of rewards reclaimed and bounty amount received
    """
    assert self._sync_rewards(self._epoch())

    rewards: uint256 = self._claim(_account, block.timestamp - self.reward_expiration * EPOCH_LENGTH)
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
def report(_account: address) -> (uint256, uint256):
    """
    @notice Report an early exit of a veYFI position
    @param _account Account to report
    @return Tuple with amount of rewards reclaimed and bounty amount received
    """
    assert self.last_claimed[_account] > 0

    epoch: uint256 = self._epoch()
    assert self._sync_rewards(epoch)

    # must be an active migrated account
    lock: Lock = self.locks[_account]
    assert lock.amount > 0
    unlock_epoch: uint256 = (lock.unlock_time - genesis) // EPOCH_LENGTH

    # must have early exited
    assert epoch < unlock_epoch
    assert self._check_lock(_account)[0] == 0

    # claim all rewards up until end of this epoch
    rewards: uint256 = self._claim(_account, genesis + (epoch + 1) * EPOCH_LENGTH)

    # zero out lock
    slope: uint256 = lock.amount // MAX_NUM_EPOCHS
    self.locks[_account].amount = 0
    self.total_weights[epoch].weight -= lock.amount + (lock.boost_epochs - epoch) * slope
    self.total_weights[epoch].slope -= slope
    self.unlocks[unlock_epoch].amount -= lock.amount + (lock.boost_epochs - unlock_epoch) * slope
    self.unlocks[unlock_epoch].slope_change -= slope

    bounty: uint256 = rewards * self.report_bounty // BOUNTY_PRECISION
    log Report(caller=msg.sender, account=_account, rewards=rewards, bounty=bounty)

    if bounty > 0:
        rewards -= bounty
        assert extcall token.transfer(msg.sender, bounty, default_return_value=True)

    if rewards > 0:
        assert extcall token.transfer(self.report_recipient, rewards, default_return_value=True)

    return rewards, bounty

@external
def sync_rewards() -> bool:
    """
    @notice Synchronize global rewards up until now
    @return True: rewards are fully synced, False: not fully synced
    """
    return self._sync_rewards(self._epoch())

@external
@view
def check_lock(_account: address) -> (uint256, uint256):
    """
    @notice Check whether a snapshotted veYFI lock is still active

    @return Tuple with snapshotted amount and unlock time, if lock is still active.
            If lock is no longer active, returns a tuple of zeroes
    """
    return self._check_lock(_account)

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
def set_snapshot(_account: address, _amount: uint256, _boost: uint256, _unlock: uint256):
    """
    @notice Set a veYFI position snapshot
    @param _account Account to set snapshot for
    @param _amount Amount of YFI in the lock
    @param _boost Boost at time of snapshot, in epochs
    @param _unlock Timestamp of unlock
    @dev Can only called by management
    @dev Can only be set if position has not been migrated yet
    """
    assert msg.sender == self.management
    assert self.last_claimed[_account] == 0

    unlock_epoch: uint256 = (_unlock - genesis) // EPOCH_LENGTH
    assert unlock_epoch < MAX_NUM_EPOCHS
    assert _boost >= unlock_epoch

    self.locks[_account] = Lock(amount=_amount, boost_epochs=_boost, unlock_time=_unlock)
    log SetSnapshot(account=_account, amount=_amount, boost=_boost, unlock=_unlock)

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
    assert _expiration > 1 and _expiration < 32
    assert _bounty <= BOUNTY_PRECISION
    assert _recipient != empty(address) or _bounty == BOUNTY_PRECISION

    self.reward_expiration = _expiration
    self.reclaim_bounty = _bounty
    self.reclaim_recipient = _recipient
    log SetRewardExpiration(expiration=_expiration, bounty=_bounty, recipient=_recipient)

@external
def set_report_bounty(_bounty: uint256, _recipient: address):
    """
    @notice Set report bounty parameters
    @param _bounty Bounty (in bps) to give to the caller
    @param _recipient Recipient of the reclaimed rewards
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _bounty <= BOUNTY_PRECISION
    assert _recipient != empty(address) or _bounty == BOUNTY_PRECISION

    self.report_bounty = _bounty
    self.report_recipient = _recipient
    log SetReportBounty(bounty=_bounty, recipient=_recipient)

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
@view
def _check_lock(_account: address) -> (uint256, uint256):
    """
    @notice Checks whether a snapshotted lock is still active
    """
    snapshot_amount: uint256 = self.locks[_account].amount
    snapshot_unlock_time: uint256 = self.locks[_account].unlock_time

    amount: uint256 = 0
    end: uint256 = 0
    amount, end = staticcall veyfi.locked(_account)
    if amount < snapshot_amount or end < snapshot_unlock_time:
        return 0, 0

    return snapshot_amount, snapshot_unlock_time

@internal
def _sync_total_weights(_current: uint256) -> bool:
    """
    @notice Compute total weights by consecutively applying the slope to the weight, 
            followed by applying the unlock to the weight and slope
    """
    last: uint256 = self.last_epoch
    if last == _current:
        return True

    weight: Weight = self.total_weights[last]
    for i: uint256 in range(32):
        last += 1

        # apply slope and unlocks
        unlock: Unlock = self.unlocks[last]
        weight.weight -= weight.slope + unlock.amount
        weight.slope -= unlock.slope_change

        self.total_weights[last] = weight

        if last == _current:
            break

    self.last_epoch = last
    return last == _current

@internal
def _sync_rewards(_current: uint256) -> bool:
    """
    @notice Sync epoch by epoch rewards by claiming from the distributor
    """
    epoch: uint256 = self.reward_epoch
    if epoch == _current:
        return True

    for i: uint256 in range(32):
        if epoch == _current:
            break
        self.rewards[epoch] = (extcall self.distributor.claim())[2]
        epoch += 1

    self.reward_epoch = epoch

    return epoch == _current

@internal
def _claim(_account: address, _time: uint256) -> uint256:
    """
    @notice Claim rewards for single account up until a specific timestamp.
            Rewards must be synced prior to calling
    """
    last_claimed: uint256 = self.last_claimed[_account]
    if last_claimed == 0 or last_claimed >= _time:
        return 0

    epoch: uint256 = (last_claimed - genesis) // EPOCH_LENGTH - 1
    completed_epoch: uint256 = (_time - genesis) // EPOCH_LENGTH - 1
    lock: Lock = self.locks[_account]
    if lock.amount == 0:
        self.last_claimed[_account] = _time
        return 0

    unlock_epoch: uint256 = (lock.unlock_time - genesis) // EPOCH_LENGTH
    if epoch >= unlock_epoch:
        self.last_claimed[_account] = _time
        self.locks[_account].amount = 0
        return 0

    weight: uint256 = lock.amount + lock.amount // MAX_NUM_EPOCHS * (lock.boost_epochs - epoch)
    epoch_rewards: uint256 = self.rewards[epoch] * weight // self.total_weights[epoch].weight

    rewards: uint256 = 0
    synced: bool = epoch == completed_epoch
    if not synced:
        # rollover to new epoch. first finalize the last one
        rewards += epoch_rewards - epoch_rewards * ((last_claimed - genesis) % EPOCH_LENGTH) // EPOCH_LENGTH

        for i: uint256 in range(32):
            epoch += 1

            if epoch == unlock_epoch:
                synced = True
                epoch_rewards = 0
                break

            weight = lock.amount + lock.amount // MAX_NUM_EPOCHS * (lock.boost_epochs - epoch)
            epoch_rewards = self.rewards[epoch] * weight // self.total_weights[epoch].weight
            synced = epoch == completed_epoch
            if synced:
                break
            else:
                rewards += epoch_rewards

        # partial sync is only allowed if we are reclaiming
        assert synced or _time < block.timestamp

        # set time to beginning of the epoch. only needs to be correct mod `EPOCH_LENGTH`
        last_claimed = genesis

    if synced:
        rewards += epoch_rewards * ((_time - genesis) % EPOCH_LENGTH) // EPOCH_LENGTH
        rewards -= epoch_rewards * ((last_claimed - genesis) % EPOCH_LENGTH) // EPOCH_LENGTH
        self.last_claimed[_account] = _time

        # zero out expired lock
        if epoch == unlock_epoch:
            self.locks[_account].amount = 0
    else:
        # not fully synced, but the last epoch is already added to the rewards,
        # so the claim time is one `EPOCH_LENGTH` bigger than you'd expect otherwise
        self.last_claimed[_account] = genesis + (epoch + 2) * EPOCH_LENGTH

    return rewards

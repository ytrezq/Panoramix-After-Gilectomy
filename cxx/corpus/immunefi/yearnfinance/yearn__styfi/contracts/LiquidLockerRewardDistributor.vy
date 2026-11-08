# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Liquid Locker Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice A component to the RewardDistributor. It tracks staking balances of LL tokens through their 
        hooks. It reports a total weight that is preconfigured and decays over time.
        Rewards are claimed from the distributor as they become available and streamed over the
        following epoch, proportional to each LL relative weight and each stakers current share.
"""

from ethereum.ercs import IERC20

interface IHooks:
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

interface IComponent:
    def sync_total_weight(_epoch: uint256) -> uint256: nonpayable

interface IDistributor:
    def genesis() -> uint256: view
    def claim() -> (uint256, uint256, uint256): nonpayable

implements: IHooks
implements: IComponent

struct Staked:
    epoch: uint256
    time: uint256
    amount: uint256

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
lock_duration: public(immutable(uint256))
management: public(address)
pending_management: public(address)

depositors: public(HashMap[address, uint256])
distributor: public(IDistributor)
claimers: public(HashMap[address, bool])
reward_expiration: public(uint256)
reclaim_bounty: public(uint256)
reclaim_recipient: public(address)

reward_epoch: public(uint256)
epoch_total_rewards: public(HashMap[uint256, uint256])
total_unboosted_weight: public(uint256)

staking: public(IERC20[3])
normalized_weights: public(uint256[3])
current_rewards: public(Rewards[3])
reward_integral: public(uint256[3])
reward_integral_snapshot: public(HashMap[uint256, HashMap[uint256, uint256]]) # ll idx => epoch => snapshot
account_reward_integral: public(HashMap[uint256, HashMap[address, uint256]]) # ll idx => account => integral
accrued_rewards: public(HashMap[address, Accrued])
accrued_reward_entries: public(HashMap[address, HashMap[uint256, AccruedEntry]]) # account => accrued idx => entry

event Claim:
    account: indexed(address)
    rewards: uint256

event Reclaim:
    caller: indexed(address)
    account: indexed(address)
    idx: uint256
    rewards: uint256
    bounty: uint256

event SetDepositor:
    idx: indexed(uint256)
    depositor: address

event SetStaking:
    idx: indexed(uint256)
    staking: address

event SetDistributor:
    distributor: indexed(address)

event SetUnboostedWeights:
    weights: uint256[3]

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
RAMP_LENGTH: constant(uint256) = 4 * EPOCH_LENGTH
BOOST_DURATION: constant(uint256) = 104

PRECISION: constant(uint256) = 10**30
NORM_WEIGHT_PRECISION: constant(uint256) = 10**18
BOUNTY_PRECISION: constant(uint256) = 10_000

@deploy
def __init__(_distributor: address, _token: address, _lock: uint256, _depositors: address[3]):
    """
    @notice Constructor
    @param _distributor The distributor address
    @param _token The address of the reward token
    @param _lock The duration of the veYFI lock, in epochs
    @param _depositors Array with the address of each of the depositors
    """
    assert _lock <= BOOST_DURATION

    genesis = staticcall IDistributor(_distributor).genesis()
    token = IERC20(_token)
    lock_duration = _lock

    self.management = msg.sender
    self.distributor = IDistributor(_distributor)

    for i: uint256 in range(3):
        d: address = _depositors[i]
        assert d != empty(address)
        assert self.depositors[d] == 0
        self.depositors[d] = i + 1
        self.staking[i] = IERC20(d)

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
    @notice Compute the total weight for reward distribution purposes
    @param _epoch The epoch to compute the total weight for
    @return The total weight for this epoch
    @dev Can only be called by the distributor
    """
    assert msg.sender == self.distributor.address

    if _epoch >= lock_duration:
        return 0

    weight: uint256 = self.total_unboosted_weight
    # changing the total weight requires all historical weights to be synced, 
    # so it is safe to just take the latest value here

    # apply boost
    weight += weight * (BOOST_DURATION - _epoch) // BOOST_DURATION

    return weight

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
    idx: uint256 = self.depositors[msg.sender] - 1
    assert self._sync_rewards()
    assert self._sync_integral(idx, _prev_supply)
    self._sync_account_integral(idx, _account, _prev_staked)

@external
def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon unstaking of tokens
    @param _account Originator of the staked tokens
    @param _prev_supply Total token supply before unstake
    @param _prev_staked Staked balance of originator before unstake
    @param _amount Amount of tokens to unstake
    """
    idx: uint256 = self.depositors[msg.sender] - 1
    assert self._sync_rewards()
    assert self._sync_integral(idx, _prev_supply)
    self._sync_account_integral(idx, _account, _prev_staked)

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
    assert self._sync_rewards()
    for i: uint256 in range(3):
        staked: uint256 = staticcall self.staking[i].balanceOf(_account)
        if staked > 0:
            supply: uint256 = staticcall self.staking[i].totalSupply()
            self._sync_integral(i, supply)
            self._sync_account_integral(i, _account, staked)

    accrued_idx: uint256 = self.accrued_rewards[_account].count - 1
    accrued: uint256 = self.accrued_reward_entries[_account][accrued_idx].accrued
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
def reclaim(_idx: uint256, _account: address, _accrued_idx: uint256 = max_value(uint256)) -> (uint256, uint256):
    """
    @notice Reclaim expired rewards
    @param _idx Liquid locker index
    @param _account Account to reclaim rewards for
    @param _accrued_idx Index of accrued rewards to reclaim from (optional)
    @return Tuple with amount of rewards reclaimed and bounty amount received
    """
    assert self._sync_rewards()
    supply: uint256 = staticcall self.staking[_idx].totalSupply()
    assert self._sync_integral(_idx, supply)
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

    # reclaim from rewards since last state change
    integral: uint256 = self.reward_integral_snapshot[_idx][epoch]
    account_integral: uint256 = self.account_reward_integral[_idx][_account]
    if account_integral < integral:
        staked: uint256 = staticcall self.staking[_idx].balanceOf(_account)
        rewards += (integral - account_integral) * staked // PRECISION
        self.account_reward_integral[_idx][_account] = integral

    if rewards == 0:
        return 0, 0

    bounty: uint256 = rewards * self.reclaim_bounty // BOUNTY_PRECISION
    log Reclaim(caller=msg.sender, account=_account, idx=_idx, rewards=rewards, bounty=bounty)

    if bounty > 0:
        rewards -= bounty
        assert extcall token.transfer(msg.sender, bounty, default_return_value=True)

    if rewards > 0:
        assert extcall token.transfer(self.reclaim_recipient, rewards, default_return_value=True)

    return rewards, bounty

@external
def sync_total_rewards() -> bool:
    """
    @notice Synchronize total rewards up until now
    @return True: rewards are fully synced, False: not fully synced
    """
    return self._sync_rewards()

@external
def sync_rewards(_idx: uint256, _account: address = empty(address)) -> bool:
    """
    @notice Synchronize rewards for a specific LL up until now
    @param _idx Liquid locker index
    @param _account Also update rewards for this specific account (optional)
    @return True: rewards are fully synced, False: not fully synced
    """
    assert _idx < 3
    assert self._sync_rewards()

    supply: uint256 = staticcall self.staking[_idx].totalSupply()
    synced: bool = self._sync_integral(_idx, supply)
    if _account != empty(address):
        staked: uint256 = staticcall self.staking[_idx].balanceOf(_account)
        self._sync_account_integral(_idx, _account, staked)
    return synced

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
def set_depositor(_previous: address, _depositor: address):
    """
    @notice Replace a liquid locker depositor
    @param _previous Old depositor address
    @param _depositor New depositor address
    @dev Can only be called by management
    @dev Caller is responsible for ensuring consistency between the old and new depositor
    """
    assert msg.sender == self.management
    number: uint256 = self.depositors[_previous]
    assert number > 0
    assert self.depositors[_depositor] == 0

    self.depositors[_previous] = 0
    self.depositors[_depositor] = number
    log SetDepositor(idx=number - 1, depositor=_depositor)

@external
def set_staking(_idx: uint256, _staking: address):
    """
    @notice Set a liquid locker staking address
    @param _idx Liquid locker index
    @param _staking New depositor address
    @dev Can only be called by management
    @dev Caller is responsible for ensuring consistency between the depositor and staking contract
    """
    assert msg.sender == self.management

    self.staking[_idx] = IERC20(_staking)
    log SetStaking(idx=_idx, staking=_staking)

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
def set_unboosted_weights(_weights: uint256[3]):
    """
    @notice Set unboosted weight of each liquid locker
    @param _weights Unboosted weights
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    epoch: uint256 = 0
    if block.timestamp >= genesis:
        epoch = self._epoch()

    total: uint256 = _weights[0] + _weights[1] + _weights[2]
    self.total_unboosted_weight = total

    for i: uint256 in range(3):
        assert self.current_rewards[i].timestamp // EPOCH_LENGTH == epoch
        if total == 0:
            self.normalized_weights[i] = 0
        else:    
            self.normalized_weights[i] = NORM_WEIGHT_PRECISION * _weights[i] // total
    log SetUnboostedWeights(weights=_weights)

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
def _sync_rewards() -> bool:
    """
    @notice Synchronize rewards by repeatedly claiming from the distributor
    """
    current_epoch: uint256 = self._epoch()
    reward_epoch: uint256 = self.reward_epoch

    distributor: IDistributor = self.distributor
    for i: uint256 in range(32):
        if reward_epoch == current_epoch:
            break
        reward_epoch += 1
        self.epoch_total_rewards[reward_epoch] = (extcall distributor.claim())[2]

    self.reward_epoch = reward_epoch
    return reward_epoch == current_epoch

@internal
def _sync_integral(_idx: uint256, _supply: uint256) -> bool:
    """
    @notice Synchronize integral for a specific liquid locker
            Rewards must be synced before calling
    """
    supply: uint256 = _supply + 10**12

    current_epoch: uint256 = self._epoch()
    unlocked: uint256 = 0
    ew: Rewards = self.current_rewards[_idx]
    epoch: uint256 = unsafe_div(ew.timestamp, EPOCH_LENGTH)
    synced: bool = epoch == current_epoch
    last_streamed: uint256 = (ew.timestamp % EPOCH_LENGTH) * ew.rewards // EPOCH_LENGTH
    ew.timestamp = block.timestamp - genesis
    integral: uint256 = self.reward_integral[_idx]
    
    if not synced:
        # rollover to new epoch. first finalize the last one
        unlocked = ew.rewards - last_streamed
        last_streamed = 0

        # save integral snapshot
        self.reward_integral_snapshot[_idx][epoch] = integral + unlocked * PRECISION // supply

        # fast forward through any other completed epochs
        weight: uint256 = self.normalized_weights[_idx]

        epoch_rewards: uint256 = 0
        for i: uint256 in range(32):
            epoch += 1
            epoch_rewards = self.epoch_total_rewards[epoch] * weight // NORM_WEIGHT_PRECISION
            synced = epoch == current_epoch
            if synced:
                break
            else:
                unlocked += epoch_rewards
                self.reward_integral_snapshot[_idx][epoch] = integral + unlocked * PRECISION // supply

        if synced:
            # fully caught up
            ew.rewards = epoch_rewards
        else:
            # not fully caught up. we already added the epoch's full amount to `unlocked`, so we 
            # zero out the epoch rewards to not double count it in the next call
            ew.timestamp = epoch * EPOCH_LENGTH
            ew.rewards = 0

    self.current_rewards[_idx] = ew

    # accrue rewards from this epoch
    streamed: uint256 = (ew.timestamp % EPOCH_LENGTH) * ew.rewards // EPOCH_LENGTH
    unlocked += streamed - last_streamed
    if unlocked == 0:
        return synced

    # update integral
    self.reward_integral[_idx] = integral + unlocked * PRECISION // supply

    return synced

@internal
def _sync_account_integral(_idx: uint256, _account: address, _balance: uint256):
    """
    @notice Synchronize integral for a specific liquid locker and account
            Global integral must be synced before calling
    """
    epoch: uint256 = self._epoch()
    integral: uint256 = self.reward_integral[_idx]

    accrued_idx: uint256 = self.accrued_rewards[_account].count
    if accrued_idx == 0:
        # no entries yet
        accrued_idx = 1
        self.accrued_rewards[_account].count = 1
        self.accrued_reward_entries[_account][0].epoch = epoch
    accrued_idx -= 1

    accrued: uint256 = self.accrued_reward_entries[_account][accrued_idx].accrued
    if _balance > 0:
        if epoch > self.accrued_reward_entries[_account][accrued_idx].epoch:
            # new epoch, new entry
            accrued_idx += 1
            self.accrued_rewards[_account].count = accrued_idx + 1
            self.accrued_reward_entries[_account][accrued_idx].epoch = epoch

        accrued += (integral - self.account_reward_integral[_idx][_account]) * _balance // PRECISION
        self.accrued_reward_entries[_account][accrued_idx].accrued = accrued

    self.account_reward_integral[_idx][_account] = integral

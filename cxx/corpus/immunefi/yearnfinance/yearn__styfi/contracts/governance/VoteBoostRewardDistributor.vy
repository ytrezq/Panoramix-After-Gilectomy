# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Vote Boost Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice A component to the RewardDistributor, basing reward weights on the user's total stake in 
        the system and the participation rate in governance voting. The participation is determined
        by the fraction of proposals the user has voted on in a sliding window of 6 epochs.
        This component takes into account staking of the naked token as well as the liquid locker tokens
        and the legacy voting escrow and applies the legacy boost on the latter two.
"""

from ethereum.ercs import IERC20

interface IComponent:
    def sync_total_weight(_epoch: uint256) -> uint256: nonpayable

interface IDistributor:
    def genesis() -> uint256: view
    def components(_component: address) -> (address, uint256): view
    def claim() -> (uint256, uint256, uint256): nonpayable

interface IWeightAggregator:
    def staked(_account: address) -> uint256: view

interface VotingEscrowSnapshot:
    def locks(_account: address) -> Lock: view
    def check_lock(_account: address) -> (uint256, uint256): view
    def last_claimed(_account: address) -> uint256: view

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

interface IVotingHooks:
    def on_propose(_idx: uint256, _proposer: address): nonpayable
    def on_retract(_idx: uint256): nonpayable
    def on_vote(_idx: uint256, _account: address): nonpayable

implements: IComponent
implements: IHooks
implements: IVotingHooks

struct Lock:
    amount: uint256
    boost_epochs: uint256
    unlock_time: uint256

genesis: public(immutable(uint256))
token: public(immutable(IERC20))
ll_unlock_epoch: public(immutable(uint256))
management: public(address)
pending_management: public(address)
upstream: public(address)
downstream: public(IHooks)
weight_aggregator: public(IWeightAggregator)
staking: public(IERC20)
snapshot: public(VotingEscrowSnapshot)
distributor: public(IDistributor)
voting: public(HashMap[address, bool])
claimers: public(HashMap[address, bool])
reward_expiration: public(uint256)
reclaim_bounty: public(uint256)
reclaim_recipient: public(address)
report_bounty: public(uint256)
report_recipient: public(address)

num_proposals: public(HashMap[uint256, uint256]) # epoch => num proposals
packed_proposal_epochs: public(HashMap[address, HashMap[uint256, uint256]]) # voter => idx => epoch | has votes
packed_voted: public(HashMap[address, HashMap[address, HashMap[uint256, uint256]]]) # account => voter => voted bitmap
packed_num_votes: public(HashMap[address, HashMap[uint256, uint256]]) # account => packed count
packed_total_weights: public(HashMap[uint256, uint256]) # account => packed weights
packed_weights: public(HashMap[address, HashMap[uint256, uint256]]) # account => packed weights
ve_locks: public(HashMap[address, Lock]) # account => ve lock
ve_migrated: public(HashMap[address, bool]) # account => ve migrated

reward_epoch: public(uint256)
rewards: public(HashMap[uint256, uint256]) # epoch => rewards
last_claimed: public(HashMap[address, uint256]) # account => last claim timestamp

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

event SetUpstream:
    upstream: indexed(address)

event SetDownstream:
    downstream: indexed(address)

event SetWeightAggregator:
    aggregator: indexed(address)

event SetStaking:
    staking: indexed(address)

event SetSnapshot:
    snapshot: indexed(address)

event SetDistributor:
    distributor: indexed(address)

event SetVoting:
    account: indexed(address)
    voting: bool

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
MAX_NUM_PROPOSALS_PER_EPOCH: constant(uint256) = 64
NUM_VOTES_SIZE: constant(uint256) = 8
NUM_VOTES_PACKING: constant(uint256) = 256 // NUM_VOTES_SIZE
NUM_VOTES_MASK: constant(uint256) = 2**NUM_VOTES_SIZE - 1
WEIGHT_SIZE: constant(uint256) = 50
WEIGHT_PACKING: constant(uint256) = 256 // WEIGHT_SIZE
WEIGHT_MASK: constant(uint256) = 2**WEIGHT_SIZE - 1
WEIGHT_PACKING_SCALE: constant(uint256) = 10**10
BOOST_DURATION: constant(uint256) = 104
BOUNTY_PRECISION: constant(uint256) = 10_000

@deploy
def __init__(_distributor: address, _token: address, _unlock: uint256):
    """
    @notice Constructor
    @param _distributor The distributor address
    @param _token The reward token
    @param _unlock Liquid locker voting escrow unlock epoch
    """
    assert _unlock <= BOOST_DURATION

    genesis = staticcall IDistributor(_distributor).genesis()
    token = IERC20(_token)
    ll_unlock_epoch = _unlock

    assert block.timestamp >= genesis + 2 * EPOCH_LENGTH

    self.management = msg.sender
    self.distributor = IDistributor(_distributor)

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
    assert _epoch < self._epoch()

    num_proposals: uint256 = self.num_proposals[_epoch]
    if num_proposals == 0:
        return 0

    packed: uint256 = self.packed_total_weights[_epoch // WEIGHT_PACKING]
    sh: uint256 = (_epoch % WEIGHT_PACKING) * WEIGHT_SIZE
    total: uint256 = (packed >> sh) & WEIGHT_MASK

    # like the individual user weights, the total weight contains a multiplier for the
    # number of proposals voted on. we correct for it by dividing out the number of proposals.
    # this is correct since we only want to achieve full boost if all proposals are voted on
    return total * WEIGHT_PACKING_SCALE // num_proposals

@external
@view
def voted(_account: address, _voter: address, _idx: uint256) -> bool:
    """
    @notice Query whether an account voted for a specific proposal already
    @param _account Account to query for
    @param _voter Voter contract
    @param _idx Proposal index
    @return True: voted, False: not voted
    """
    bitmap: uint256 = self.packed_voted[_account][_voter][_idx // 256]
    return bitmap & (1 << _idx % 256) > 0

@external
@view
def num_votes(_epoch: uint256, _account: address) -> uint256:
    """
    @notice Query the effective number of proposals voted for by an account in a specific epoch.
            Represents a rolling count of the past 6 epochs
    @param _epoch Epoch to query for
    @param _account Account to query for
    @return Number of proposals voted for
    """
    packed: uint256 = self.packed_num_votes[_account][_epoch // NUM_VOTES_PACKING]
    sh: uint256 = (_epoch % NUM_VOTES_PACKING) * NUM_VOTES_SIZE
    num_votes: uint256 = (packed >> sh) & NUM_VOTES_MASK

    return num_votes

@external
@view
def weight(_epoch: uint256, _account: address) -> uint256:
    """
    @notice Query the reward weight of an account in a specific epoch.
            Effectively equal to the snapshotted total stake of the account
            multiplied by the rolling count of votes in the epoch
    @param _epoch Epoch to query for
    @param _account Account to query for
    @return Reward weight
    """
    packed: uint256 = self.packed_weights[_account][_epoch // WEIGHT_PACKING]
    sh: uint256 = (_epoch % WEIGHT_PACKING) * WEIGHT_SIZE
    weight: uint256 = (packed >> sh) & WEIGHT_MASK

    return weight * WEIGHT_PACKING_SCALE

@external
def claim(_account: address) -> uint256:
    """
    @notice Claim rewards on behalf of an account
    @param _account Account to claim rewards for
    @return Amount of rewards tokens claimed
    """
    assert self.claimers[msg.sender]
    
    if not self._sync_rewards(self._epoch()):
        # not fully synced, defer claim
        return 0

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
    assert self.ve_migrated[_account]

    epoch: uint256 = self._epoch()
    assert self._sync_rewards(epoch)

    # must be an active migrated account
    lock: Lock = self.ve_locks[_account]
    assert lock.amount > 0
    unlock_epoch: uint256 = (lock.unlock_time - genesis) // EPOCH_LENGTH

    # must have early exited
    assert epoch < unlock_epoch
    assert (staticcall self.snapshot.check_lock(_account))[0] == 0

    # claim all rewards up until end of this epoch
    rewards: uint256 = self._claim(_account, genesis + (epoch + 1) * EPOCH_LENGTH)

    # zero out lock and update weights
    self.ve_locks[_account] = empty(Lock)
    staked: uint256 = staticcall self.weight_aggregator.staked(_account) 
    self._update_weights(_account, staked, False)

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
    assert msg.sender == self.upstream

    self._update_weights(_from, _prev_staked_from - _amount, False)
    self._update_weights(_to, _prev_staked_to + _amount, False)
    extcall self.downstream.on_transfer(_caller, _from, _to, _supply, _prev_staked_from, _prev_staked_to, _amount)

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
    assert msg.sender == self.upstream

    self._update_weights(_account, _prev_staked + _amount, False)
    extcall self.downstream.on_stake(_caller, _account, _prev_supply, _prev_staked, _amount)

@external
def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon unstaking of tokens
    @param _account Originator of the staked tokens
    @param _prev_supply Total token supply before unstake
    @param _prev_staked Staked balance of originator before unstake
    @param _amount Amount of tokens to unstake
    """
    assert msg.sender == self.upstream

    self._update_weights(_account, _prev_staked - _amount, False)
    extcall self.downstream.on_unstake(_account, _prev_supply, _prev_staked, _amount)

@external
def on_propose(_idx: uint256, _proposer: address):
    """
    @notice Triggered by a voting contract upon creation of a proposal
    @param _idx Proposal index
    @param _proposer Author of the proposal
    """
    assert self.voting[msg.sender]

    # proposal must not exist
    assert self.packed_proposal_epochs[msg.sender][_idx] == 0

    # proposals are voted on in the epoch after they are proposed
    epoch: uint256 = self._epoch() + 1
    self.packed_proposal_epochs[msg.sender][_idx] = epoch << 1

    # proposals count towards the boost for 6 epochs, starting with the next epoch
    for i: uint256 in range(6):
        num_proposals: uint256 = self.num_proposals[epoch] + 1
        assert num_proposals <= MAX_NUM_PROPOSALS_PER_EPOCH
        self.num_proposals[epoch] = num_proposals
        epoch += 1

@external
def on_retract(_idx: uint256):
    """
    @notice Triggered by a voting contract upon retraction of a proposal
    @param _idx Proposal index
    @dev Can only be called if the proposal does not have any votes yet
    """
    assert self.voting[msg.sender]

    # proposal must exist and not have any votes
    packed: uint256 = self.packed_proposal_epochs[msg.sender][_idx]
    assert packed > 0 and packed & 1 == 0
    self.packed_proposal_epochs[msg.sender][_idx] = 0

    epoch: uint256 = packed >> 1
    for i: uint256 in range(6):
        self.num_proposals[epoch] -= 1
        epoch += 1

@external
def on_vote(_idx: uint256, _account: address):
    """
    @notice Triggered by a voting contract upon submission of a vote
    @param _idx Proposal index
    @param _account Account submitting the vote
    @dev Can only be called in the epoch after the proposal was created
    """
    assert self.voting[msg.sender]

    # proposal must exist and proposed last epoch
    packed: uint256 = self.packed_proposal_epochs[msg.sender][_idx]
    assert packed >> 1 == self._epoch()

    # mark proposal as having votes
    self.packed_proposal_epochs[msg.sender][_idx] = packed | 1

    # update voted bitmap
    bitmap: uint256 = self.packed_voted[_account][msg.sender][_idx // 256]
    increment: bool = bitmap & (1 << _idx % 256) == 0

    if increment:
        # first time voting for this proposal
        bitmap |= 1 << _idx % 256
        self.packed_voted[_account][msg.sender][_idx // 256] = bitmap

    staked: uint256 = staticcall self.weight_aggregator.staked(_account) 
    self._update_weights(_account, staked, increment)

@external
def activate():
    """
    @notice Activate as component inside the reward distributor
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert self.reward_epoch == 0
    epoch: uint256 = (staticcall self.distributor.components(self))[1]
    assert epoch > 0
    self.reward_epoch = epoch

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
def set_upstream(_upstream: address):
    """
    @notice Set the upstream address where weight hooks are originating from
    @param _upstream Upstream weight hook address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.upstream = _upstream
    log SetUpstream(upstream=_upstream)

@external
def set_downstream(_downstream: address):
    """
    @notice Set the dowstream address where weight hooks are forwarded to
    @param _downstream Downstream weight hook address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.downstream = IHooks(_downstream)
    log SetDownstream(downstream=_downstream)

@external
def set_weight_aggregator(_aggregator: address):
    """
    @notice Set the weight aggregator
    @param _aggregator Weight aggregator address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.weight_aggregator = IWeightAggregator(_aggregator)
    log SetWeightAggregator(aggregator=_aggregator)

@external
def set_staking(_staking: address):
    """
    @notice Set the staking address
    @param _staking Staking address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.staking = IERC20(_staking)
    log SetStaking(staking=_staking)

@external
def set_snapshot(_snapshot: address):
    """
    @notice Set voting escrow snapshot
    @param _snapshot Voting escrow snapshot address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.snapshot = VotingEscrowSnapshot(_snapshot)
    log SetSnapshot(snapshot=_snapshot)

@external
def set_distributor(_distributor: address):
    """
    @notice Set reward distributor
    @param _distributor Distributor address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.distributor = IDistributor(_distributor)
    log SetDistributor(distributor=_distributor)

@external
def set_voting(_account: address, _voting: bool):
    """
    @notice Whitelist account as voting contract
    @param _account Account
    @param _voting True: add to whitelist, False: remove from whitelist
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.voting[_account] = _voting
    log SetVoting(account=_account, voting=_voting)

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
def _update_weights(_account: address, _agg_staked: uint256, _voted: bool):
    """
    @notice Recalculate reward weights for the next 6 epochs.
            If triggered by a new vote, also increment the rolling vote count
    """
    epoch: uint256 = self._epoch()
    self._populate_lock(epoch, _account)

    # the aggregated staking balance is st + ll, so we seperate the two
    # to be able to apply the boost on the latter
    staked: uint256 = staticcall self.staking.balanceOf(_account)
    ll_staked: uint256 = _agg_staked - staked

    ve_weight: uint256 = 0
    ve_slope: uint256 = 0
    ve_unlock: uint256 = self.ve_locks[_account].unlock_time
    if ve_unlock >= genesis + (epoch + 1) * EPOCH_LENGTH:
        # lock has not expired yet
        migrated: bool = self.ve_migrated[_account]
        if not migrated:
            # re-check migration status
            migrated = staticcall self.snapshot.last_claimed(_account) > 0
            self.ve_migrated[_account] = migrated

        if migrated:
            # lock is migrated, count towards total weight
            ve_unlock = (ve_unlock - genesis) // EPOCH_LENGTH
            ve_weight = self.ve_locks[_account].amount
            ve_slope = ve_weight // BOOST_DURATION
            ve_weight += (self.ve_locks[_account].boost_epochs - epoch) * ve_slope
        else:
            ve_unlock = 0
    else:
        ve_unlock = 0

    # update weights for the next 6 epochs, starting with current, taking into account decaying boosts
    slot_n: uint256 = epoch // NUM_VOTES_PACKING
    slot_w: uint256 = epoch // WEIGHT_PACKING
    packed_n: uint256 = self.packed_num_votes[_account][slot_n]
    packed_t: uint256 = self.packed_total_weights[slot_w]
    packed_w: uint256 = self.packed_weights[_account][slot_w]
    for i: uint256 in range(6):
        # load stored number of votes
        if epoch // NUM_VOTES_PACKING > slot_n:
            # next slot for num votes
            if _voted:
                # write previous to storage
                self.packed_num_votes[_account][slot_n] = packed_n
            slot_n = unsafe_add(slot_n, 1)
            packed_n = self.packed_num_votes[_account][slot_n]

        sh: uint256 = (epoch % NUM_VOTES_PACKING) * NUM_VOTES_SIZE
        num_votes: uint256 = (packed_n >> sh) & NUM_VOTES_MASK
        if _voted:
            num_votes = unsafe_add(num_votes, 1)
            assert num_votes <= NUM_VOTES_MASK
            packed_n = (packed_n & ~(NUM_VOTES_MASK << sh)) | (num_votes << sh)

        if num_votes == 0:
            # no need to recalculate weights if user hasnt voted
            continue

        # compute updated weight in this epoch: (st + ll + ve) * n
        weight: uint256 = staked

        if epoch < ll_unlock_epoch:
            # apply liquid locker boost
            weight += ll_staked * (2 * BOOST_DURATION - epoch) // BOOST_DURATION

        if epoch < ve_unlock:
            # apply voting escrow boost
            weight += ve_weight
            ve_weight -= ve_slope

        weight = weight * num_votes // WEIGHT_PACKING_SCALE
        assert weight <= WEIGHT_MASK

        # load stored weight
        if epoch // WEIGHT_PACKING > slot_w:
            # next slot for weights, write previous to storage
            self.packed_total_weights[slot_w] = packed_t
            self.packed_weights[_account][slot_w] = packed_w
            slot_w = unsafe_add(slot_w, 1)
            packed_t = self.packed_total_weights[slot_w]
            packed_w = self.packed_weights[_account][slot_w]

        sh = (epoch % WEIGHT_PACKING) * WEIGHT_SIZE

        # compute new total weight
        total: uint256 = (packed_t >> sh) & WEIGHT_MASK
        prev: uint256 = (packed_w >> sh) & WEIGHT_MASK
        total = total - prev + weight
        assert total <= WEIGHT_MASK
        # assuming worst case scenario, this packing would support a total amount
        # of 2**50 / 10**8 (packed decimals) / 2 (boost) / 64 (proposals) = ~87_960 voting tokens

        # update packed values, but dont write to storage yet
        packed_t = (packed_t & ~(WEIGHT_MASK << sh)) | (total << sh)
        packed_w = (packed_w & ~(WEIGHT_MASK << sh)) | (weight << sh)
        epoch = unsafe_add(epoch, 1)

    # write packed values to storage
    if _voted:
        self.packed_num_votes[_account][slot_n] = packed_n
    self.packed_total_weights[slot_w] = packed_t
    self.packed_weights[_account][slot_w] = packed_w

@internal
def _populate_lock(_epoch: uint256, _account: address):
    """
    @notice Populate voting escrow lock data if not done already
    """
    if self.last_claimed[_account] > 0:
        return

    self.last_claimed[_account] = genesis + (_epoch + 1) * EPOCH_LENGTH
    self.ve_migrated[_account] = staticcall self.snapshot.last_claimed(_account) > 0

    lock: Lock = staticcall self.snapshot.locks(_account)
    if lock.amount == 0:
        # no snapshotted lock
        return
    
    unlock_epoch: uint256 = (lock.unlock_time - genesis) // EPOCH_LENGTH
    if _epoch >= unlock_epoch or (staticcall self.snapshot.check_lock(_account))[0] == 0:
        # lock no longer active
        return

    self.ve_locks[_account] = lock

@internal
def _sync_rewards(_current: uint256) -> bool:
    """
    @notice Sync epoch by epoch rewards by claiming from the distributor
    """
    epoch: uint256 = self.reward_epoch
    assert epoch > 0
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

    slot: uint256 = epoch // WEIGHT_PACKING
    packed_t: uint256 = self.packed_total_weights[slot]
    packed_w: uint256 = self.packed_weights[_account][slot]

    sh: uint256 = (epoch % WEIGHT_PACKING) * WEIGHT_SIZE
    total_weight: uint256 = (packed_t >> sh) & WEIGHT_MASK
    weight: uint256 = (packed_w >> sh) & WEIGHT_MASK
    epoch_rewards: uint256 = 0
    if total_weight > 0:
        epoch_rewards = self.rewards[epoch] * weight // total_weight

    rewards: uint256 = 0
    synced: bool = epoch == completed_epoch
    if not synced:
        # rollover to new epoch. first finalize the last one
        rewards += epoch_rewards - epoch_rewards * ((last_claimed - genesis) % EPOCH_LENGTH) // EPOCH_LENGTH

        for i: uint256 in range(32):
            epoch = unsafe_add(epoch, 1)
            if epoch // WEIGHT_PACKING > slot:
                # next storage slot
                slot = unsafe_add(slot, 1)
                packed_t = self.packed_total_weights[slot]
                packed_w = self.packed_weights[_account][slot]

            # compute user's rewards this epoch
            sh = (epoch % WEIGHT_PACKING) * WEIGHT_SIZE
            total_weight = (packed_t >> sh) & WEIGHT_MASK
            weight = (packed_w >> sh) & WEIGHT_MASK
            if total_weight > 0:
                epoch_rewards = self.rewards[epoch] * weight // total_weight
            else:
                epoch_rewards = 0

            synced = epoch == completed_epoch
            if synced:
                break
            else:
                rewards += epoch_rewards

        # set time to beginning of the epoch. only needs to be correct mod `EPOCH_LENGTH`
        last_claimed = genesis

    if synced:
        rewards += epoch_rewards * ((_time - genesis) % EPOCH_LENGTH) // EPOCH_LENGTH
        rewards -= epoch_rewards * ((last_claimed - genesis) % EPOCH_LENGTH) // EPOCH_LENGTH
        self.last_claimed[_account] = _time
    else:
        # not fully synced, but the last epoch is already added to the rewards,
        # so the claim time is one `EPOCH_LENGTH` bigger than you'd expect otherwise
        self.last_claimed[_account] = genesis + (epoch + 2) * EPOCH_LENGTH

    return rewards

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

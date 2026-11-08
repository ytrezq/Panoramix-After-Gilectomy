# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title YBC Membership Election
@author Yearn Finance
@license GNU AGPLv3
@notice YBC module that deals with adding/removing members based on a vote amongst its members.
        Any member can propose a vote to add a new member or remove an existing member.
        Proposals can be retracted by the proposer in the same epoch.
        Members can vote on proposals in the second half of the epoch after the proposal is made.
        Members cant vote on their own expulsion.
        A vote passes if a threshold fraction of votes is in favor of the proposal.
        Votes that have passed can be executed by anyone in the following epoch.
"""

interface IYBC:
    def members(_account: address) -> bool: view
    def call(_target: address, _data: Bytes[2048]): nonpayable

interface IWeightAggregator:
    def weight(_account: address) -> uint256: view

struct Proposal:
    account: address
    proposer: address
    epoch: uint256
    addition: bool
    threshold: uint256
    votes: uint256
    yea: uint256
    retracted: bool
    executed: bool

flag Status:
    PROPOSED
    RETRACTED
    VOTING
    PASSED
    FAILED
    EXECUTED
    EXPIRED
    INVALID

genesis: public(immutable(uint256))
ybc: public(immutable(IYBC))
management: public(address)
pending_management: public(address)
weight_aggregator: public(IWeightAggregator)
addition_threshold: public(uint256)
expulsion_threshold: public(uint256)
num_proposals: public(uint256)
proposals: public(HashMap[uint256, Proposal])
votes: public(HashMap[address, HashMap[uint256, uint256]]) # account => bitmap

event Propose:
    idx: indexed(uint256)
    account: indexed(address)
    proposer: indexed(address)
    epoch: uint256
    addition: bool

event Retract:
    idx: indexed(uint256)

event Vote:
    account: indexed(address)
    idx: indexed(uint256)
    weight: uint256
    yea: bool

event Execute:
    executor: indexed(address)
    idx: indexed(uint256)

event SetWeightAggregator:
    aggregator: indexed(address)

event SetThresholds:
    addition: uint256
    expulsion: uint256

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
VOTE_LENGTH: constant(uint256) = EPOCH_LENGTH // 2
DECAY_LENGTH: constant(uint256) = 24 * 60 * 60
THRESHOLD_PRECISION: constant(uint256) = 10_000
ADDITION: constant(bool) = True
EXPULSION: constant(bool) = False
YEA: constant(bool) = True
NAY: constant(bool) = False

@deploy
def __init__(_genesis: uint256, _ybc: address):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    @param _ybc The address of the YBC
    """
    genesis = _genesis
    ybc = IYBC(_ybc)
    self.management = msg.sender
    self.addition_threshold = THRESHOLD_PRECISION
    self.expulsion_threshold = THRESHOLD_PRECISION

@external
@view
def epoch() -> uint256:
    """
    @notice Query the current epoch number
    @return The current epoch number
    """
    return self._epoch()

@external
@view
def status(_idx: uint256) -> Status:
    """
    @notice Query the status of a proposal
    @param _idx Proposal index
    @return Status enum
    """
    if _idx >= self.num_proposals:
        return Status.INVALID
    if self.proposals[_idx].executed:
        return Status.EXECUTED
    if self.proposals[_idx].retracted:
        return Status.RETRACTED

    voting_epoch: uint256 = self.proposals[_idx].epoch
    vote_open: uint256 = genesis + (voting_epoch + 1) * EPOCH_LENGTH - VOTE_LENGTH
    if block.timestamp < vote_open:
        return Status.PROPOSED

    current_epoch: uint256 = self._epoch()
    if current_epoch == voting_epoch:
        return Status.VOTING

    if self._passed(_idx):
        if current_epoch == voting_epoch + 1:
            return Status.PASSED
        else:
            return Status.EXPIRED
    
    return Status.FAILED

@external
def propose_addition(_account: address) -> uint256:
    """
    @notice Propose the addition of a new member to the YBC
    @param _account Address of the new member
    @return Proposal index
    @dev Can only be called by current YBC members
    """
    assert not staticcall ybc.members(_account)
    return self._propose(_account, ADDITION)

@external
def propose_expulsion(_account: address) -> uint256:
    """
    @notice Propose the expulsion of an existing member from the YBC
    @param _account Address of the member
    @return Proposal index
    @dev Can only be called by current YBC members
    """
    assert staticcall ybc.members(_account)
    return self._propose(_account, EXPULSION)

@external
def retract(_idx: uint256):
    """
    @notice Retract a proposal
    @param _idx Index of proposal to retract
    @dev Can only be called by the creator of the proposal
    """
    assert msg.sender == self.proposals[_idx].proposer
    assert self._epoch() < self.proposals[_idx].epoch
    assert not self.proposals[_idx].retracted
    self.proposals[_idx].retracted = True

    log Retract(idx=_idx)

@external
@view
def voted(_account: address, _idx: uint256) -> bool:
    """
    @notice Query whether an account voted for a proposal or not
    @param _account Account to query vote status for
    @param _idx Proposal index
    @return True: voted, False: not voted
    """
    return self.votes[_account][_idx // 256] & (1 << _idx % 256) > 0

@external
def vote_yea(_idx: uint256):
    """
    @notice Vote in favor of a proposal
    @param _idx Proposal index to vote for
    @dev Can only be called by current YBC members
    """
    self._vote(_idx, YEA)

@external
def vote_nay(_idx: uint256):
    """
    @notice Vote in opposition of a proposal
    @param _idx Proposal index to vote against
    @dev Can only be called by current YBC members
    """
    self._vote(_idx, NAY)

@external
def execute(_idx: uint256):
    """
    @notice Execute a passed proposal
    @param _idx Proposal index to execute
    """
    account: address = self.proposals[_idx].account
    assert account != empty(address)
    assert self._epoch() == self.proposals[_idx].epoch + 1
    assert not self.proposals[_idx].retracted
    assert not self.proposals[_idx].executed
    assert self._passed(_idx)

    self.proposals[_idx].executed = True
    if self.proposals[_idx].addition == ADDITION:
        extcall ybc.call(ybc.address, abi_encode(account, method_id=method_id("add_member(address)")))
    else:
        extcall ybc.call(ybc.address, abi_encode(account, method_id=method_id("remove_member(address)")))

    log Execute(executor=msg.sender, idx=_idx)

@external
def set_weight_aggregator(_aggregator: address):
    """
    @notice Set the YBC weight aggregator
    @param _aggregator Weight aggregator address
    @dev Can only be called by management
    @dev Should only aggregate weights of members of the YBC
    """
    assert msg.sender == self.management

    self.weight_aggregator = IWeightAggregator(_aggregator)
    log SetWeightAggregator(aggregator=_aggregator)

@external
def set_thresholds(_addition: uint256, _expulsion: uint256):
    """
    @notice Set the thresholds required for votes to pass
    @param _addition Threshold for addition votes (bps)
    @param _expulsion Threshold for expulsion votes (bps)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _addition <= THRESHOLD_PRECISION and _expulsion <= THRESHOLD_PRECISION

    self.addition_threshold = _addition
    self.expulsion_threshold = _expulsion
    log SetThresholds(addition=_addition, expulsion=_expulsion)

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
def _propose(_account: address, _addition: bool) -> uint256:
    """
    @notice Create a new proposal
    """
    assert staticcall ybc.members(msg.sender)
    assert _account not in [empty(address), ybc.address]

    idx: uint256 = self.num_proposals
    self.num_proposals = idx + 1

    threshold: uint256 = 0
    if _addition == ADDITION:
        threshold = self.addition_threshold
    else:
        threshold = self.expulsion_threshold

    epoch: uint256 = self._epoch() + 1
    self.proposals[idx] = Proposal(
        account=_account, proposer=msg.sender, epoch=epoch, addition=_addition, 
        threshold=threshold, votes=0, yea=0, retracted=False, executed=False
    )

    log Propose(idx=idx, account=_account, proposer=msg.sender, epoch=epoch, addition=_addition)
    return idx

@internal
def _vote(_idx: uint256, _yea: bool):
    """
    @notice Vote on a proposal
    """
    assert staticcall ybc.members(msg.sender)
    target: address = self.proposals[_idx].account
    assert target != empty(address)
    if self.proposals[_idx].addition == EXPULSION:
        # not allowed to vote on your own expulsion
        assert msg.sender != target
    assert self.proposals[_idx].epoch == self._epoch()
    epoch_progress: uint256 = (block.timestamp - genesis) % EPOCH_LENGTH
    assert epoch_progress >= EPOCH_LENGTH - VOTE_LENGTH
    assert not self.proposals[_idx].retracted
    bitmap: uint256 = self.votes[msg.sender][_idx // 256]
    assert bitmap & (1 << _idx % 256) == 0

    bitmap |= 1 << _idx % 256
    self.votes[msg.sender][_idx // 256] = bitmap

    weight: uint256 = staticcall self.weight_aggregator.weight(msg.sender)
    if epoch_progress > EPOCH_LENGTH - DECAY_LENGTH:
        weight = weight * (EPOCH_LENGTH - epoch_progress) // DECAY_LENGTH
    assert weight > 0

    self.proposals[_idx].votes += weight
    if _yea:
        self.proposals[_idx].yea += weight

    log Vote(account=msg.sender, idx=_idx, weight=weight, yea=_yea)

@internal
@view
def _passed(_idx: uint256) -> bool:
    """
    @notice Check whether a proposal received sufficient votes
    """
    votes: uint256 = self.proposals[_idx].votes
    return votes > 0 and self.proposals[_idx].yea * THRESHOLD_PRECISION >= votes * self.proposals[_idx].threshold

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

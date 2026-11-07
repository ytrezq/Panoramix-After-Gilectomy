# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Voting
@author Yearn Finance
@license GNU AGPLv3
@notice Manages the full lifecycle of governance decisions, from proposals to the
        voting stage and on-chain execution. User votes should not be submitted directly
        to this contract but use a specialized voter contract instead.
        Proposals contain an IPFS hash and can optionally contain a script for on-chain execution.
        The guardian can veto proposals at any point before execution, permanently disabling
        execution. In addition the guardian can appoint an operator which can flag any proposal
        before it enters the voting stage, permanently disabling any voting on it.
"""

interface IBlacklist:
    def blacklist(_account: address) -> bool: view

interface IVoting:
    def voted(_account: address, _idx: uint256) -> bool: view
    def vote(_account: address, _idx: uint256, _scale: uint256, _yea: uint256) -> uint256: nonpayable

interface IWeightMeasure:
    def weight(_account: address) -> uint256: view

interface IVotingHooks:
    def on_propose(_idx: uint256, _proposer: address): nonpayable
    def on_retract(_idx: uint256): nonpayable
    def on_vote(_idx: uint256, _account: address): nonpayable

interface IExecutor:
    def execute(_script: Bytes[2048]): nonpayable

implements: IVoting

struct Votes:
    weight: uint256
    yea: uint256

struct Proposal:
    proposer: address
    epoch: uint256
    ipfs: bytes32
    script_hash: bytes32
    threshold: uint256
    votes: uint256
    yea: uint256
    retracted: bool
    executed: bool
    flagged: bool
    vetoed: bool

flag Status:
    PROPOSED
    RETRACTED
    VOTING
    PASSED
    FAILED
    EXECUTED
    EXPIRED
    INVALID
    FLAGGED
    VETOED

genesis: public(immutable(uint256))
management: public(address)
pending_management: public(address)
guardian: public(address)
pending_guardian: public(address)
operator: public(address)
hooks: public(IVotingHooks)
weight_measure: public(IWeightMeasure)

propose_min_weight: public(uint256)
propose_cooldown: public(uint256)
propose_blacklist: public(IBlacklist)
voter: public(address)
vote_start: public(uint256)
threshold: public(uint256)
execute_guard: public(bool)
execute_delay: public(uint256)
executor: public(IExecutor)

num_proposals: public(uint256)
proposals: public(HashMap[uint256, Proposal])
last_proposed: public(HashMap[address, uint256]) # account => timestamp
votes: public(HashMap[address, HashMap[uint256, Votes]]) # account => proposal => votes

event Propose:
    idx: indexed(uint256)
    proposer: indexed(address)
    epoch: indexed(uint256)
    ipfs: bytes32
    script: Bytes[2048]

event Retract:
    idx: indexed(uint256)

event Vote:
    account: indexed(address)
    idx: indexed(uint256)
    weight: uint256
    yea: uint256

event Flag:
    idx: indexed(uint256)
    reason: String[256]

event Veto:
    idx: indexed(uint256)
    reason: String[256]

event Execute:
    executor: indexed(address)
    idx: indexed(uint256)

event SetProposeParameters:
    min_weight: uint256
    cooldown: uint256
    blacklist: address

event SetVoteParameters:
    length: uint256
    voter: address

event SetExecuteParameters:
    delay: uint256
    guard: bool
    executor: address

event SetThreshold:
    threshold: uint256

event SetHooks:
    hooks: indexed(address)

event SetWeightMeasure:
    measure: indexed(address)

event SetOperator:
    operator: indexed(address)

event PendingGuardian:
    guardian: indexed(address)

event SetGuardian:
    guardian: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
MIN_PROPOSE_COOLDOWN: constant(uint256) = 24 * 60 * 60
PRECISION: constant(uint256) = 10_000
ADDITION: constant(bool) = True
EXPULSION: constant(bool) = False
YEA: constant(bool) = True
NAY: constant(bool) = False
EMPTY_SCRIPT_HASH: constant(bytes32) = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 # keccak256(b"")

@deploy
def __init__(_genesis: uint256):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    """
    genesis = _genesis
    self.management = msg.sender
    self.threshold = PRECISION // 2
    self.propose_min_weight = 10**18
    self.propose_cooldown = MIN_PROPOSE_COOLDOWN
    self.vote_start = EPOCH_LENGTH // 2
    self.guardian = msg.sender
    self.operator = msg.sender
    self.execute_guard = True

    assert block.timestamp >= genesis + EPOCH_LENGTH

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
    if self.proposals[_idx].flagged:
        return Status.FLAGGED
    if self.proposals[_idx].vetoed:
        return Status.VETOED
    if self.proposals[_idx].retracted:
        return Status.RETRACTED

    voting_epoch: uint256 = self.proposals[_idx].epoch
    vote_start: uint256 = genesis + voting_epoch * EPOCH_LENGTH + self.vote_start
    if block.timestamp < vote_start:
        return Status.PROPOSED

    current_epoch: uint256 = self._epoch()
    if current_epoch == voting_epoch:
        return Status.VOTING

    if not self._passed(_idx):
        return Status.FAILED

    if current_epoch == voting_epoch + 1:
        return Status.PASSED

    if self.proposals[_idx].script_hash == EMPTY_SCRIPT_HASH:
        # proposals without script get marked as executed
        return Status.EXECUTED

    return Status.EXPIRED    

@external
def propose(_ipfs: bytes32, _script: Bytes[2048]) -> uint256:
    """
    @notice Propose execution of a script
    @param _ipfs IPFS hash
    @param _script Script to execute
    @return Proposal index
    """
    assert not staticcall self.propose_blacklist.blacklist(msg.sender)
    assert staticcall self.weight_measure.weight(msg.sender) >= self.propose_min_weight
    assert block.timestamp - self.last_proposed[msg.sender] >= self.propose_cooldown

    self.last_proposed[msg.sender] = block.timestamp

    idx: uint256 = self.num_proposals
    self.num_proposals = idx + 1

    epoch: uint256 = self._epoch() + 1
    self.proposals[idx] = Proposal(
        proposer=msg.sender, epoch=epoch, ipfs=_ipfs, script_hash = keccak256(_script), threshold=self.threshold, 
        votes=0, yea=0, retracted=False, executed=False, flagged=False, vetoed=False
    )

    extcall self.hooks.on_propose(idx, msg.sender)
    log Propose(idx=idx, proposer=msg.sender, epoch=epoch, ipfs=_ipfs, script=_script)
    return idx

@external
def retract(_idx: uint256):
    """
    @notice Retract a proposal
    @param _idx Index of proposal to retract
    @dev Can only be called by the creator of the proposal
    """
    assert msg.sender == self.proposals[_idx].proposer
    assert self._epoch() <= self.proposals[_idx].epoch
    assert not self.proposals[_idx].retracted
    assert not self.proposals[_idx].vetoed
    assert self.proposals[_idx].votes == 0

    self.proposals[_idx].retracted = True

    extcall self.hooks.on_retract(_idx)
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
    return self.votes[_account][_idx].weight > 0

@external
def vote(_account: address, _idx: uint256, _scale: uint256, _yea: uint256) -> uint256:
    """
    @notice Submit a vote on behalf of an account
    @param _account Account to vote on behalf of
    @param _idx Proposal index
    @param _scale Fraction of weight to count (bps)
    @param _yea Fraction of votes in favor of the proposal (bps)
    @return Effective vote weight
    @dev Can only be called by the voter
    @dev Submitting a vote more than once overwrites the previous vote
    """
    assert msg.sender == self.voter
    assert self.proposals[_idx].epoch == self._epoch()
    assert (block.timestamp - genesis) % EPOCH_LENGTH >= self.vote_start
    assert not self.proposals[_idx].retracted
    assert _scale <= PRECISION
    assert _yea <= PRECISION

    prev: Votes = self.votes[_account][_idx]
    weight: uint256 = staticcall self.weight_measure.weight(_account) * _scale // PRECISION

    votes: Votes = Votes(weight=weight, yea=weight * _yea // PRECISION)
    self.proposals[_idx].votes = self.proposals[_idx].votes - prev.weight + votes.weight
    self.proposals[_idx].yea = self.proposals[_idx].yea - prev.yea + votes.yea
    self.votes[_account][_idx] = votes

    if weight > 0:
        # votes are only counted if they are non-zero
        extcall self.hooks.on_vote(_idx, _account)

    log Vote(account=_account, idx=_idx, weight=weight, yea=_yea)
    return weight

@external
def flag(_idx: uint256, _reason: String[256]):
    """
    @notice Flag a proposal as invalid
    @param _idx Proposal index
    @param _reason Reason for flagging
    @dev Can only be called by the operator
    @dev Can only be called before the proposal has any votes
    """
    assert msg.sender == self.operator
    current: uint256 = self._epoch()
    voting_epoch: uint256 = self.proposals[_idx].epoch
    assert voting_epoch > 0 and current <= voting_epoch
    assert not self.proposals[_idx].retracted
    assert self.proposals[_idx].votes == 0

    self.proposals[_idx].flagged = True
    self.proposals[_idx].retracted = True
    extcall self.hooks.on_retract(_idx)
    log Flag(idx=_idx, reason=_reason)

@external
def veto(_idx: uint256, _reason: String[256]):
    """
    @notice Veto a proposal
    @param _idx Proposal index
    @param _reason Reason for vetoing
    @dev Can only be called by the guardian
    @dev Can be called at any point before the proposal is executed
    """
    assert msg.sender == self.guardian
    current: uint256 = self._epoch()
    voting_epoch: uint256 = self.proposals[_idx].epoch
    assert voting_epoch > 0 and current <= voting_epoch + 1
    assert not self.proposals[_idx].retracted
    assert not self.proposals[_idx].executed
    assert not self.proposals[_idx].vetoed

    self.proposals[_idx].vetoed = True
    if self.proposals[_idx].votes == 0:
        # no votes yet, vote can be retracted without side effects
        self.proposals[_idx].retracted = True
        extcall self.hooks.on_retract(_idx)
    log Veto(idx=_idx, reason=_reason)

@external
def execute(_idx: uint256, _script: Bytes[2048]):
    """
    @notice Execute a passed proposal
    @param _idx Proposal index to execute
    @param _script The script corresponding to the proposal
    """
    if self.execute_guard:
        assert msg.sender == self.operator
    assert self._epoch() == self.proposals[_idx].epoch + 1
    assert (block.timestamp - genesis) % EPOCH_LENGTH >= self.execute_delay
    assert not self.proposals[_idx].retracted
    assert not self.proposals[_idx].vetoed
    assert not self.proposals[_idx].executed
    assert self._passed(_idx)
    assert keccak256(_script) == self.proposals[_idx].script_hash

    self.proposals[_idx].executed = True
    if len(_script) > 0:
        extcall self.executor.execute(_script)
    log Execute(executor=msg.sender, idx=_idx)

@external
def set_propose_parameters(_min_weight: uint256, _cooldown: uint256, _blacklist: address):
    """
    @notice Set parameters related to creating proposals
    @param _min_weight Minimum weight
    @param _cooldown Minimum time between proposals (seconds)
    @param _blacklist Contract mainting the blacklist
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _cooldown >= MIN_PROPOSE_COOLDOWN and _cooldown <= EPOCH_LENGTH
    assert _blacklist != empty(address)

    self.propose_min_weight = _min_weight
    self.propose_cooldown = _cooldown
    self.propose_blacklist = IBlacklist(_blacklist)
    log SetProposeParameters(min_weight=_min_weight, cooldown=_cooldown, blacklist=_blacklist)

@external
def set_vote_parameters(_length: uint256, _voter: address):
    """
    @notice Set parameters related to voting on proposals
    @param _length Length of voting period (seconds)
    @param _voter Address submitting the votes
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.vote_start = EPOCH_LENGTH - _length
    self.voter = _voter
    log SetVoteParameters(length=_length, voter=_voter)

@external
def set_execute_parameters(_delay: uint256, _guard: bool, _executor: address):
    """
    @notice Set parameters related to executing proposals
    @param _delay Minimum delay between approval and execution (seconds)
    @param _guard True: only operator can execute proposals, False: anyone can execute proposals
    @param _executor Contract to execute approved proposals through
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _delay < EPOCH_LENGTH
    assert _executor != empty(address)

    self.execute_delay = _delay
    self.execute_guard = _guard
    self.executor = IExecutor(_executor)
    log SetExecuteParameters(delay=_delay, guard=_guard, executor=_executor)

@external
def set_threshold(_threshold: uint256):
    """
    @notice Set the threshold required for votes to pass
    @param _threshold Threshold (bps)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _threshold <= PRECISION

    self.threshold = _threshold
    log SetThreshold(threshold=_threshold)

@external
def set_hooks(_hooks: address):
    """
    @notice Set the hooks address
    @param _hooks New hooks address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.hooks = IVotingHooks(_hooks)
    log SetHooks(hooks=_hooks)

@external
def set_weight_measure(_measure: address):
    """
    @notice Set the weight measure address
    @param _measure New weight measure address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.weight_measure = IWeightMeasure(_measure)
    log SetWeightMeasure(measure=_measure)

@external
def set_operator(_operator: address):
    """
    @notice Set the operator address
    @param _operator New operator address
    @dev Can only be called by the guardian
    """
    assert msg.sender == self.guardian

    self.operator = _operator
    log SetOperator(operator=_operator)

@external
def set_guardian(_guardian: address):
    """
    @notice Set the pending guardian address.
            Needs to be accepted by that account separately to transfer guardian over
    @param _guardian New pending guardian address
    """
    assert msg.sender == self.guardian

    self.pending_guardian = _guardian
    log PendingGuardian(guardian=_guardian)

@external
def accept_guardian():
    """
    @notice Accept guardian role.
            Can only be called by account previously marked as pending by current guardian
    """
    assert msg.sender == self.pending_guardian

    self.pending_guardian = empty(address)
    self.guardian = msg.sender
    log SetGuardian(guardian=msg.sender)

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
def _passed(_idx: uint256) -> bool:
    """
    @notice Check whether a proposal received sufficient votes
    """
    votes: uint256 = self.proposals[_idx].votes
    return votes > 0 and self.proposals[_idx].yea * PRECISION >= votes * self.proposals[_idx].threshold

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

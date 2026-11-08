# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Voter
@author Yearn Finance
@license GNU AGPLv3
@notice User-facing contract to submit votes on governance proposals.
        Supports vote weight decay near the end of the epoch to discourage late voting.
        If the user is also a YBC member, the votes for delegated staking and YBC are updated 
        based on their YBC weight and the YBC weight of all the YBC voters before.
"""

interface IYBC:
    def members(_account: address) -> bool: view

interface IWeightAggregator:
    def weight(_account: address) -> uint256: view

interface IVoting:
    def voted(_account: address, _idx: uint256) -> bool: view
    def vote(_account: address, _idx: uint256, _scale: uint256, _yea: uint256) -> uint256: nonpayable

struct Votes:
    weight: uint256
    yea: uint256

genesis: public(immutable(uint256))
management: public(address)
pending_management: public(address)
decay_length: public(uint256)
delegated_staking: public(address)
ybc: public(IYBC)
ybc_weight_aggregator: public(IWeightAggregator)
ybc_votes: public(HashMap[address, HashMap[uint256, Votes]]) # voting => proposal => votes

event SetDecayLength:
    length: uint256

event SetDelegatedStaking:
    staking: indexed(address)

event SetYBC:
    ybc: indexed(address)

event SetYBCWeightAggregator:
    aggregator: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
PRECISION: constant(uint256) = 10_000

@deploy
def __init__(_genesis: uint256):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    """
    genesis = _genesis
    self.management = msg.sender

@external
@view
def epoch() -> uint256:
    """
    @notice Query the current epoch number
    @return The current epoch number
    """
    return self._epoch()

@external
def vote_yea(_voting: address, _idx: uint256) -> uint256:
    """
    @notice Vote in favor of a proposal
    @param _voting Voting contract that holds the proposal
    @param _idx Proposal index
    @return Effective vote weight
    @dev Also updates vote for delegated staking and YBC, if applicable
    @dev Can only be called once together with `vote_nay` per proposal per user
    """
    return self._vote(_voting, _idx, PRECISION)

@external
def vote_nay(_voting: address, _idx: uint256) -> uint256:
    """
    @notice Vote in opposition of a proposal
    @param _voting Voting contract that holds the proposal
    @param _idx Proposal index
    @return Effective vote weight
    @dev Also updates vote for delegated staking and YBC, if applicable
    @dev Can only be called once together with `vote_yea` per proposal per user
    """
    return self._vote(_voting, _idx, 0)

@external
def set_decay_length(_length: uint256):
    """
    @notice Set the vote weight decay length
    @param _length Decay length
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _length < EPOCH_LENGTH // 2

    self.decay_length = _length
    log SetDecayLength(length=_length)

@external
def set_delegated_staking(_staking: address):
    """
    @notice Set the delegated staking address
    @param _staking Delegated staking address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.delegated_staking = _staking
    log SetDelegatedStaking(staking=_staking)

@external
def set_ybc(_ybc: address):
    """
    @notice Set the YBC address
    @param _ybc YBC address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.ybc = IYBC(_ybc)
    log SetYBC(ybc=_ybc)

@external
def set_ybc_weight_aggregator(_aggregator: address):
    """
    @notice Set the YBC weight aggregator address
    @param _aggregator YBC weight aggregator
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.ybc_weight_aggregator = IWeightAggregator(_aggregator)
    log SetYBCWeightAggregator(aggregator=_aggregator)

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
def _vote(_voting: address, _idx: uint256, _yea: uint256) -> uint256:
    """
    @notice Submit a vote for/against
    """
    assert not staticcall IVoting(_voting).voted(msg.sender, _idx)

    # determine weight decay factor
    scale: uint256 = PRECISION
    decay_length: uint256 = self.decay_length
    epoch_progress: uint256 = (block.timestamp - genesis) % EPOCH_LENGTH
    if epoch_progress > EPOCH_LENGTH - decay_length:
        scale = PRECISION * (EPOCH_LENGTH - epoch_progress) // decay_length

    # submit user vote
    user_weight: uint256 = extcall IVoting(_voting).vote(msg.sender, _idx, scale, _yea)
    assert user_weight > 0

    if not staticcall self.ybc.members(msg.sender):
        return user_weight

    weight: uint256 = staticcall self.ybc_weight_aggregator.weight(msg.sender)
    if weight == 0:
        return user_weight

    # YBC member: also update vote for delegated staking and YBC
    votes: Votes = self.ybc_votes[_voting][_idx]
    votes.weight += weight
    if _yea > 0:
        votes.yea += weight
    self.ybc_votes[_voting][_idx] = votes

    ybc_yea: uint256 = PRECISION * votes.yea // votes.weight
    extcall IVoting(_voting).vote(self.delegated_staking, _idx, PRECISION, ybc_yea)
    extcall IVoting(_voting).vote(self.ybc.address, _idx, PRECISION, ybc_yea)

    return user_weight

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

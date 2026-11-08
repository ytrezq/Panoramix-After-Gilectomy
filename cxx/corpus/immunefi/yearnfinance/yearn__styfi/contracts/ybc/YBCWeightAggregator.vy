# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title YBC Weight Aggregator
@author Yearn Finance
@license GNU AGPLv3
@notice Aggregates staked balances for YBC members only. This will allow for fair
        yield redistribution and decision making inside the Collective.
        Weights ramp up over 4 epochs.
"""

interface IMemberHooks:
    def on_add_member(_account: address): nonpayable
    def on_remove_member(_account: address): nonpayable

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

interface IWeightAggregator:
    def supply() -> uint256: view
    def staked(_account: address) -> uint256: view
    def weight(_account: address) -> uint256: view

implements: IMemberHooks
implements: IHooks
implements: IWeightAggregator

genesis: public(immutable(uint256))
management: public(address)
pending_management: public(address)
weight_aggregator: public(IWeightAggregator)
upstream_weights: public(address)
upstream_members: public(address)
downstream: public(IHooks)

supply: public(uint256)
packed_weights: public(HashMap[address, uint256])

event SetWeightAggregator:
    aggregator: indexed(address)

event SetUpstreamWeights:
    upstream: indexed(address)

event SetUpstreamMembers:
    upstream: indexed(address)

event SetDownstream:
    downstream: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
INCREMENT: constant(bool) = True
DECREMENT: constant(bool) = False
EPOCH_MASK: constant(uint256) = 2**16 - 1
WEIGHT_MASK: constant(uint256) = 2**60 - 1
PACKING_SCALE: constant(uint256) = 10**6

@deploy
def __init__(_genesis: uint256):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    """
    assert block.timestamp >= _genesis + 2 * EPOCH_LENGTH
    genesis = _genesis
    self.management = msg.sender

@external
@view
def staked(_account: address) -> uint256:
    """
    @notice Query the staked amount of a specific YBC member
    @param _account Account to query for
    @return Staked amount. Zero if not a member of the YBC
    """
    if self.packed_weights[_account] == 0:
        # not a YBC member
        return 0

    return staticcall self.weight_aggregator.staked(_account)

@external
@view
def weight(_account: address) -> uint256:
    """
    @notice Query the weight of a specific member. The weight ramps up over time after deposits
            and is snapshotted at the beginning of every epoch.
    @param _account Account to query for
    @return Staked amount. Zero if not a member of the YBC
    """
    packed: uint256 = self.packed_weights[_account]
    if packed == 0:
        # not a YBC member
        return 0

    staked: uint256 = staticcall self.weight_aggregator.staked(_account)
    packed = self._forward(self._epoch(), staked, packed)
    return ((packed >> 180) & WEIGHT_MASK) * PACKING_SCALE

@external
def on_add_member(_account: address):
    """
    @notice Triggered by the hook upon adding a member to the YBC
    @param _account Member to add
    @dev Forwarded downstream as a staking operation of the entire aggregated balance
    """
    assert msg.sender == self.upstream_members
    assert self.packed_weights[_account] == 0

    staked: uint256 = staticcall self.weight_aggregator.staked(_account)
    self.packed_weights[_account] = self._epoch() << 240

    prev_supply: uint256 = self._update_supply(staked, INCREMENT)
    self._update_staked(_account, 0, staked, INCREMENT)

    extcall self.downstream.on_stake(_account, _account, prev_supply, 0, staked)

@external
def on_remove_member(_account: address):
    """
    @notice Triggered by the hook upon removing a member from the YBC
    @param _account Member to remove
    @dev Forwarded downstream as a unstaking operation of the entire aggregated balance
    """
    assert msg.sender == self.upstream_members
    assert self.packed_weights[_account] > 0

    staked: uint256 = staticcall self.weight_aggregator.staked(_account)
    self.packed_weights[_account] = 0
    prev_supply: uint256 = self._update_supply(staked, DECREMENT)

    extcall self.downstream.on_unstake(_account, prev_supply, staked, staked)

@external
def on_transfer(_caller: address, _from: address, _to: address, _: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon transfer of tokens
    @param _caller Originator of the transfer
    @param _from Sender of the token
    @param _to Recipient of the tokens
    @param _ Total token supply (unused)
    @param _prev_staked_from Staked balance of sender before transfer
    @param _prev_staked_to Staked balance of recipient before transfer
    @param _amount Amount of tokens to transfer
    @dev Depending on membership status of sender and recipient, the transfer might be forwarded downstream as 
         a transfer, stake, unstake or not forwarded at all
    """
    assert msg.sender == self.upstream_weights

    # the upstream supply includes non-members, so we have to track it ourselves
    is_ybc_from: bool = self._update_staked(_from, _prev_staked_from, _amount, DECREMENT)
    is_ybc_to: bool = self._update_staked(_to, _prev_staked_to, _amount, INCREMENT)

    if is_ybc_from:
        if is_ybc_to:
            # both sides are in the YBC, pass transfer along
            extcall self.downstream.on_transfer(_caller, _from, _to, self.supply, _prev_staked_from, _prev_staked_to, _amount)
        else:
            # only the sender is in the YBC, treat as unstaking
            prev_supply: uint256 = self._update_supply(_amount, DECREMENT)
            extcall self.downstream.on_unstake(_from, prev_supply, _prev_staked_from, _amount)
    elif is_ybc_to:
        # only the receiver is in the YBC, treat as staking
        prev_supply: uint256 = self._update_supply(_amount, INCREMENT)
        extcall self.downstream.on_stake(_caller, _to, prev_supply, _prev_staked_to, _amount)
    # if neither party is in the YBC, ignore

@external
def on_stake(_caller: address, _account: address, _: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon staking of tokens
    @param _caller Originator of the tokens
    @param _account Recipient of the staked tokens
    @param _ Total token supply before stake (unused)
    @param _prev_staked Staked balance of recipient before stake
    @param _amount Amount of tokens to stake
    @dev Only forwarded downstream if the account is a member of the YBC
    """
    assert msg.sender == self.upstream_weights

    is_ybc: bool = self._update_staked(_account, _prev_staked, _amount, INCREMENT)
    if is_ybc:
        # the upstream supply includes non-members, so we have to track it ourselves
        prev_supply: uint256 = self._update_supply(_amount, INCREMENT)
        extcall self.downstream.on_stake(_caller, _account, prev_supply, _prev_staked, _amount)

@external
def on_unstake(_account: address, _: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon unstaking of tokens
    @param _account Originator of the staked tokens
    @param _ Total token supply before unstake (unused)
    @param _prev_staked Staked balance of originator before unstake
    @param _amount Amount of tokens to unstake
    @dev Only forwarded downstream if the account is a member of the YBC
    """
    assert msg.sender == self.upstream_weights

    is_ybc: bool = self._update_staked(_account, _prev_staked, _amount, DECREMENT)
    if is_ybc:
        # the upstream supply includes non-members, so we have to track it ourselves
        prev_supply: uint256 = self._update_supply(_amount, DECREMENT)
        extcall self.downstream.on_unstake(_account, prev_supply, _prev_staked, _amount)

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
def set_upstream_weights(_upstream: address):
    """
    @notice Set the upstream address where weight hooks are originating from
    @param _upstream Upstream weight hook address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.upstream_weights = _upstream
    log SetUpstreamWeights(upstream=_upstream)

@external
def set_upstream_members(_upstream: address):
    """
    @notice Set the upstream address where membership hooks are originating from
    @param _upstream Upstream membership hook address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.upstream_members = _upstream
    log SetUpstreamMembers(upstream=_upstream)

@external
def set_downstream(_downstream: address):
    """
    @notice Set the downstream address where hooks are forwarded to
    @param _downstream Downstream hook address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.downstream = IHooks(_downstream)
    log SetDownstream(downstream=_downstream)

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
def _update_supply(_amount: uint256, _increment: bool) -> uint256:
    """
    @notice Update the total staked amount
    """
    supply: uint256 = self.supply
    prev_supply: uint256 = supply

    if _increment == INCREMENT:
        supply += _amount
    else:
        supply -= _amount

    self.supply = supply
    return prev_supply

@internal
def _update_staked(_account: address, _prev_staked: uint256, _amount: uint256, _increment: bool) -> bool:
    """
    @notice Update the staked amount of an account
    """
    packed: uint256 = self.packed_weights[_account]
    if packed == 0:
        # not a YBC member, ignore
        return False
    packed = self._forward(self._epoch(), _prev_staked, packed)
    
    staked: uint256 = _prev_staked
    sh: uint256 = 240
    if _increment == INCREMENT:
        staked += _amount

        scaled: uint256 = _amount // PACKING_SCALE
        for i: uint256 in range(4):
            sh = unsafe_sub(sh, 60)
            weight: uint256 = (packed >> sh) & WEIGHT_MASK
            weight += scaled * i // 4
            packed = (packed & ~(WEIGHT_MASK << sh)) | (weight << sh)
    else:
        staked -= _amount

        scaled: uint256 = (_amount + PACKING_SCALE - 1) // PACKING_SCALE
        for i: uint256 in range(4):
            sh = unsafe_sub(sh, 60)
            weight: uint256 = (packed >> sh) & WEIGHT_MASK
            if scaled > weight:
                weight = 0
            else:
                weight -= scaled
            packed = (packed & ~(WEIGHT_MASK << sh)) | (weight << sh)

    self.packed_weights[_account] = packed

    return True

@internal
@pure
def _forward(_current_epoch: uint256, _staked: uint256, _packed: uint256) -> uint256:
    epoch: uint256 = _packed >> 240
    if epoch == _current_epoch:
        return _packed

    staked: uint256 = _staked // PACKING_SCALE
    assert staked <= WEIGHT_MASK

    packed: uint256 = _packed
    for i: uint256 in range(min(_current_epoch - epoch, 4), bound=4):
        packed = (packed << 60) | staked
    # after 4 iterations the slot contains all copies of `staked`, so no need to continue

    # overwrite the epoch
    packed = (packed & ~(EPOCH_MASK << 240)) | (_current_epoch << 240)
    return packed

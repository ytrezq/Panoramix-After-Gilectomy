# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Weight Measure
@author Yearn Finance
@license GNU AGPLv3
@notice Measures the voting weight of a user for usage inside a governance system.
        It fetches the weight from the weight aggregator (staked YFI and staked liquid locker YFI)
        and adds to it the user's snapshotted veYFI lock, if currently still active.
        The weight for delegated staking is obtained from a separate contract.
"""

interface IWeightMeasure:
    def weight(_account: address) -> uint256: view

interface IWeightAggregator:
    def weight(_account: address) -> uint256: view

interface IDelegatedStakingSnapshot:
    def upstream() -> address: view
    def weight() -> uint256: view

interface IVotingEscrow:
    def check_lock(_account: address) -> (uint256, uint256): view
    def last_claimed(_account: address) -> uint256: view

implements: IWeightMeasure

genesis: public(immutable(uint256))
weight_aggregator: public(immutable(IWeightAggregator))
delegated_staking: public(immutable(address))
delegated_staking_snapshot: public(immutable(IDelegatedStakingSnapshot))
voting_escrow: public(immutable(IVotingEscrow))

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60

@deploy
def __init__(_genesis: uint256, _aggregator: address, _delegated: address, _ve: address):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    @param _aggregator The weight aggreggator
    @param _delegated Contract providing the snapshotted delegated staking weight
    @param _ve Contract providing the legacy voting escrow snapshot
    """
    genesis = _genesis
    weight_aggregator = IWeightAggregator(_aggregator)
    delegated_staking_snapshot = IDelegatedStakingSnapshot(_delegated)
    delegated_staking = staticcall delegated_staking_snapshot.upstream()
    voting_escrow = IVotingEscrow(_ve)

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
def weight(_account: address) -> uint256:
    """
    @notice Query the voting weight of an account
    @param _account The account to query for
    @return The current voting weight
    """
    if _account == delegated_staking:
        return staticcall delegated_staking_snapshot.weight()

    # stYFI + llYFI
    weight: uint256 = staticcall weight_aggregator.weight(_account)

    locked: uint256 = 0
    unlock: uint256 = 0
    locked, unlock = staticcall voting_escrow.check_lock(_account)

    # veYFI
    if locked > 0:
        unlock = (unlock - genesis) // EPOCH_LENGTH
        if unlock > self._epoch() and staticcall voting_escrow.last_claimed(_account) > 0:
            # lock migrated and not expired: add to weight
            weight += locked

    return weight

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

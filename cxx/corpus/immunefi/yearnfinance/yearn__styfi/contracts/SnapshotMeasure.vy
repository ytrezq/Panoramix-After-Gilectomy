# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Snapshot measure
@author Yearn Finance
@license GNU AGPLv3
@notice Measures the voting weight by summing up contributions from stYFI, staked 
        veYFI liquid locker tokens and migrated veYFI. Redistributes staking weight
        from stYFIx and the YBC to all YBC members proportionally
"""

from ethereum.ercs import IERC20

interface IWeightAggregator:
    def genesis() -> uint256: view
    def supply() -> uint256: view
    def staked(_account: address) -> uint256: view
    def weight(_account: address) -> uint256: view

interface VeRewardDistributor:
    def last_claimed(_account: address) -> uint256: view
    def check_lock(_account: address) -> (uint256, uint256): view

interface IYBC:
    def members(_account: address) -> bool: view

event SetYBC:
    ybc: address

genesis: public(immutable(uint256))
styfix: public(immutable(address))
aggregator: public(immutable(IWeightAggregator))
ve_reward_distributor: public(immutable(VeRewardDistributor))
ybc: public(immutable(IYBC))
ybc_aggregator: public(immutable(IWeightAggregator))

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60

@deploy
def __init__(_styfix: address, _aggregator: address, _verd: address, _ybc: address, _ybc_aggregator: address):
    """
    @notice Constructor
    @param _styfix stYFIx address
    @param _aggregator Weight aggregator address
    @param _verd veYFI reward distributor address
    @param _ybc YBC address
    @param _ybc_aggregator YBC weight aggregator address
    """
    styfix = _styfix
    aggregator = IWeightAggregator(_aggregator)
    genesis = staticcall aggregator.genesis()
    ve_reward_distributor = VeRewardDistributor(_verd)
    ybc = IYBC(_ybc)
    ybc_aggregator = IWeightAggregator(_ybc_aggregator)

@external
@view
def balanceOf(_account: address) -> uint256:
    """
    @notice Query voting weight of a specific account
    @param _account Account to query voting weight for
    @return Voting weight
    """
    # stYFI + llYFI
    staked: uint256 = staticcall aggregator.weight(_account)
    weight: uint256 = staked

    # migrated veYFI
    if staticcall ve_reward_distributor.last_claimed(_account) > 0:
        lock_amount: uint256 = 0
        unlock_time: uint256 = 0
        lock_amount, unlock_time = staticcall ve_reward_distributor.check_lock(_account)
        
        epoch_end: uint256 = genesis + ((block.timestamp - genesis) // EPOCH_LENGTH + 1) * EPOCH_LENGTH
        if unlock_time >= epoch_end:
            weight += lock_amount

    # YBC members: share of stYFIx and YBC stYFI
    if staticcall ybc.members(_account):
        delegated: uint256 = staticcall aggregator.staked(styfix) + staticcall aggregator.weight(ybc.address)
        supply: uint256 = staticcall ybc_aggregator.supply()
        if supply > 0:
            weight += delegated * staked // supply

    return weight

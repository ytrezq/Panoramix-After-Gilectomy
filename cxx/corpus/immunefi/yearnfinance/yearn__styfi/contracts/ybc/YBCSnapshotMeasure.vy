# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title YBC Snapshot measure
@author Yearn Finance
@license GNU AGPLv3
@notice Snapshot.org compatible YBC weights. View only
"""

from ethereum.ercs import IERC20

interface IWeightAggregator:
    def weight(_account: address) -> uint256: view

ybc_aggregator: public(immutable(IWeightAggregator))

@deploy
def __init__(_ybc_aggregator: address):
    """
    @notice Constructor
    @param _ybc_aggregator YBC weight aggregator address
    """
    ybc_aggregator = IWeightAggregator(_ybc_aggregator)

@external
@view
def balanceOf(_account: address) -> uint256:
    """
    @notice Query voting weight of a specific account
    @param _account Account to query voting weight for
    @return Voting weight
    @dev Equal to the weight from the YBC aggregator
    """
    return staticcall ybc_aggregator.weight(_account)

# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Delegated Staking Reward Claimer
@author Yearn Finance
@license GNU AGPLv3
@notice Claims and forwards rewards earmarked for the delegated stakers from its two 
        sources: the staking rewards and the vote boost rewards.
"""

from ethereum.ercs import IERC20

interface DelegatedStakingDistributor:
    def token() -> address: view
    def distributor() -> address: view
    def distributor_claim() -> address: view

interface IStakingDistributor:
    def claim(_account: address) -> uint256: nonpayable
implements: IStakingDistributor

token: public(immutable(IERC20))
delegated_staking: public(immutable(address))
delegated_staking_distributor: public(immutable(address))
staking_distributor: public(immutable(IStakingDistributor))
vote_boost_distributor: public(immutable(IStakingDistributor))

@deploy
def __init__(_dsrd: address, _vbrd: address):
    """
    @notice Constructor
    @param _dsrd Delegated staking reward distributor
    @param _vbrd Vote boost reward distributor
    """
    dsrd: DelegatedStakingDistributor = DelegatedStakingDistributor(_dsrd)

    token = IERC20(staticcall dsrd.token())
    delegated_staking = staticcall dsrd.distributor_claim()
    delegated_staking_distributor = _dsrd
    staking_distributor = IStakingDistributor(staticcall dsrd.distributor())
    vote_boost_distributor = IStakingDistributor(_vbrd)

@external
def claim(_account: address) -> uint256:
    """
    @notice Claim rewards from staking and vote boosting
    @param _account Account to claim rewards for. Has to be equal to delegated staking
    @dev Can only be called by the delegated staking reward distributor
    """
    assert msg.sender == delegated_staking_distributor
    assert _account == delegated_staking

    rewards: uint256 = 0
    rewards += extcall staking_distributor.claim(delegated_staking)
    rewards += extcall vote_boost_distributor.claim(delegated_staking)

    if rewards > 0:
        assert extcall token.transfer(msg.sender, rewards, default_return_value=True)

    return rewards

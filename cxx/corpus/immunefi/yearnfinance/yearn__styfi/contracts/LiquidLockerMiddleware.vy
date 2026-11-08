# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Liquid Locker Middleware
@author Yearn Finance
@license GNU AGPLv3
@notice Middleware contract for LiquidLockerDepositor hooks. It forwards all state
        modifying calls to a downstream address as well as to the weight aggregator.
"""

interface IHooks:
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

implements: IHooks

upstream: public(immutable(address))
downstream: public(immutable(IHooks))
aggregator: public(immutable(IHooks))

@deploy
def __init__(_upstream: address, _downstream: address, _aggregator: address):
    """
    @notice Constructor
    @param _upstream The address where hook calls originate from
    @param _downstream The address where hook calls are forwarded to
    @param _aggregator The address of the weight aggregator contract
    """
    upstream = _upstream
    downstream = IHooks(_downstream)
    aggregator = IHooks(_aggregator)

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
    assert msg.sender == upstream

    extcall downstream.on_stake(_caller, _account, _prev_supply, _prev_staked, _amount)
    extcall aggregator.on_stake(_caller, _account, _prev_supply, _prev_staked, _amount)

@external
def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon unstaking of tokens
    @param _account Originator of the staked tokens
    @param _prev_supply Total token supply before unstake
    @param _prev_staked Staked balance of originator before unstake
    @param _amount Amount of tokens to unstake
    """
    assert msg.sender == upstream

    extcall downstream.on_unstake(_account, _prev_supply, _prev_staked, _amount)
    extcall aggregator.on_unstake(_account, _prev_supply, _prev_staked, _amount)

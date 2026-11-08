# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Delegated Staking Middleware
@author Yearn Finance
@license GNU AGPLv3
@notice Middleware contract for DelegatedStakedYFI hooks. It forwards all state modifying 
        calls to a downstream address and keeps track of the current total supply as well 
        as the supply at the last epoch boundary.
"""

from ethereum.ercs import IERC20

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

implements: IHooks

genesis: public(immutable(uint256))
upstream: public(immutable(address))
downstream: public(immutable(IHooks))
packed_supply: public(uint256)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
SMALL_MASK: constant(uint256) = 2**40 - 1
BIG_MASK: constant(uint256) = 2**108 - 1

@deploy
def __init__(_genesis: uint256, _upstream: address, _downstream: address):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    @param _upstream The address where hook calls originate from
    @param _downstream The address where hook calls are forwarded to
    """
    genesis = _genesis
    upstream = _upstream
    downstream = IHooks(_downstream)

    supply: uint256 = staticcall IERC20(_upstream).totalSupply()
    self._pack(0, supply, supply)

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
def weight() -> uint256:
    """
    @notice Query the total weight of the delegated stakers
    @return The delegated weight, defined as the amount delegated at the end of the last epoch
    """
    epoch: uint256 = 0
    last_supply: uint256 = 0
    current_supply: uint256 = 0
    epoch, last_supply, current_supply = self._unpack()

    if epoch == self._epoch():
        # supply changed this epoch, use snapshotted value
        return last_supply

    return current_supply

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
    assert msg.sender == upstream

    extcall downstream.on_transfer(_caller, _from, _to, _supply, _prev_staked_from, _prev_staked_to, _amount)

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

    self._update(_prev_supply + _amount)
    extcall downstream.on_stake(_caller, _account, _prev_supply, _prev_staked, _amount)

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

    self._update(_prev_supply - _amount)
    extcall downstream.on_unstake(_account, _prev_supply, _prev_staked, _amount)

@internal
@view
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

@internal
def _update(_supply: uint256):
    """
    @notice Update the current delegated supply and its snapshotted value
    """
    epoch: uint256 = 0
    last_supply: uint256 = 0
    current_supply: uint256 = 0
    epoch, last_supply, current_supply = self._unpack()

    current_epoch: uint256 = self._epoch()
    if current_epoch > epoch:
        last_supply = current_supply

    self._pack(current_epoch, last_supply, _supply)

@internal
def _pack(_a: uint256, _b: uint256, _c: uint256):
    """
    @notice Pack a small value and two big values into a single storage slot
    """
    assert _a <= SMALL_MASK and _b <= BIG_MASK and _c <= BIG_MASK
    self.packed_supply = (_a << 216) | (_b << 108) | _c

@internal
@view
def _unpack() -> (uint256, uint256, uint256):
    """
    @notice Unpack a small value and two big values from a single storage slot
    """
    packed: uint256 = self.packed_supply
    return packed >> 216, (packed >> 108) & BIG_MASK, packed & BIG_MASK

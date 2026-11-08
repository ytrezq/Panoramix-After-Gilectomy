# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Liquid Locker Redemption
@author Yearn Finance
@license GNU AGPLv3
@notice Redemption facility for liquid locker tokens. Tokens are redeemable for YFI with a fee that 
        decays over time. Liquid locker tokens can also be bought back at no fee.
        Each token has a predefined capacity, which increases on redemption and decreases on buyback.
"""

from ethereum.ercs import IERC20

genesis: public(immutable(uint256))
yfi: public(immutable(IERC20))
lock: public(immutable(uint256))
management: public(address)
pending_management: public(address)

liquid_locker_recipient: public(address)
yfi_recipient: public(address)

tokens: public(IERC20[3])
scales: public(uint256[3])
capacities: public(uint256[3])
enabled: public(bool[3])
used: public(uint256[3])

event Redeem:
    token: indexed(address)
    amount: uint256
    fee: uint256

event Exchange:
    token: indexed(address)
    amount: uint256

event SetCapacity:
    token: indexed(address)
    capacity: uint256

event SetEnabled:
    token: indexed(address)
    enabled: bool

event SetLiquidLockerRecipient:
    recipient: indexed(address)

event SetYfiRecipient:
    recipient: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
PRECISION: constant(uint256) = 10**18
MAX_FEE: constant(uint256) = 10**17 # 10%
BOOST_DURATION: constant(uint256) = 104

@deploy
def __init__(_genesis: uint256, _yfi: address, _lock: uint256, _tokens: address[3], _scales: uint256[3]):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    @param _yfi YFI token address
    @param _lock Number of epochs that the lock is active
    @param _tokens Liquid locker token addresses
    @param _scale Amount of liquid locker tokens per underlying YFI in its lock
    """
    assert _lock <= BOOST_DURATION

    genesis = _genesis
    yfi = IERC20(_yfi)
    lock = _lock
    self.management = msg.sender
    for i: uint256 in range(3):
        assert _scales[i] > 0
        self.tokens[i] = IERC20(_tokens[i])
    self.scales = _scales

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
def fee() -> uint256:
    """
    @notice Query the current redemption fee
    @return The current redemption fee
    """
    epoch: uint256 = self._epoch()
    assert epoch < lock
    return self._fee(epoch)

@external
@view
def fee_at(_epoch: uint256) -> uint256:
    """
    @notice Query the redemption fee at a specific epoch
    @param _epoch The epoch number
    @return The redemption fee
    """
    assert _epoch < lock
    return self._fee(_epoch)

@external
def redeem(_idx: uint256, _ll_amount: uint256) -> uint256:
    """
    @notice Redeem a liquid locker token for YFI
    @param _idx Index of the liquid locker
    @param _ll_amount Amount of liquid locker tokens to redeem
    @return The amount of YFI received
    """
    assert self.enabled[_idx]
    epoch: uint256 = self._epoch()
    assert epoch < lock

    # update used capacity
    yfi_amount: uint256 = _ll_amount // self.scales[_idx]
    assert yfi_amount > 0
    used: uint256 = self.used[_idx] + yfi_amount
    assert used <= self.capacities[_idx]
    self.used[_idx] = used

    recipient: address = self.liquid_locker_recipient
    if recipient == empty(address):
        recipient = self

    assert extcall self.tokens[_idx].transferFrom(msg.sender, recipient, _ll_amount, default_return_value=True)

    # subtract fee
    fee: uint256 = self._fee(epoch)
    yfi_amount = yfi_amount * (PRECISION - fee) // PRECISION

    assert extcall yfi.transfer(msg.sender, yfi_amount, default_return_value=True)
    log Redeem(token=self.tokens[_idx].address, amount=_ll_amount, fee=fee)
    return yfi_amount

@external
def exchange(_idx: uint256, _yfi_amount: uint256) -> uint256:
    """
    @notice Exchange YFI for a liquid locker token
    @param _idx Index of the liquid locker
    @param _yfi_amount Amount of YFI to exchange
    @return The amount of liquid locker token received
    """
    assert self.enabled[_idx]
    epoch: uint256 = self._epoch()
    assert epoch < lock

    self.used[_idx] -= _yfi_amount

    recipient: address = self.yfi_recipient
    if recipient == empty(address):
        recipient = self

    ll_amount: uint256 = _yfi_amount * self.scales[_idx]

    assert extcall yfi.transferFrom(msg.sender, recipient, _yfi_amount, default_return_value=True)
    assert extcall self.tokens[_idx].transfer(msg.sender, ll_amount, default_return_value=True)
    log Exchange(token=self.tokens[_idx].address, amount=_yfi_amount)
    return ll_amount

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    """
    @notice Transfer out a token
    @param _token The token address
    @param _amount The amount of tokens. Defaults to all
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC20(_token).balanceOf(self)

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_liquid_locker_recipient(_recipient: address):
    """
    @notice Set recipient of redeemed liquid locker tokens
    @param _recipient Recipient address. If set to zero the tokens are kept inside the contract
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.liquid_locker_recipient = _recipient
    log SetLiquidLockerRecipient(recipient=_recipient)

@external
def set_yfi_recipient(_recipient: address):
    """
    @notice Set recipient of received YFI tokens
    @param _recipient Recipient address. If set to zero the tokens are kept inside the contract
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.yfi_recipient = _recipient
    log SetYfiRecipient(recipient=_recipient)

@external
def set_capacity(_idx: uint256, _capacity: uint256):
    """
    @notice Set maximum capacity of a specific liquid locker
    @param _idx Index of the liquid locker
    @param _capacity Maximum capacity
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.capacities[_idx] = _capacity
    log SetCapacity(token=self.tokens[_idx].address, capacity=_capacity)

@external
def set_enabled(_idx: uint256, _enabled: bool):
    """
    @notice Enable/disable redemption of a specific liquid locker
    @param _idx Index of the liquid locker
    @param _enabled True: enable, False: disable
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.enabled[_idx] = _enabled
    log SetEnabled(token=self.tokens[_idx].address, enabled=_enabled)

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
@view
def _fee(_epoch: uint256) -> uint256:
    return MAX_FEE * (BOOST_DURATION - _epoch) // BOOST_DURATION

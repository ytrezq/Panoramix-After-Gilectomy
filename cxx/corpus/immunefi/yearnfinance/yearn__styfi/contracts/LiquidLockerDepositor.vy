# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Liquid Locker Depositor
@author Yearn Finance
@license GNU AGPLv3
@notice ERC4626 vault that is `1:S` to the underlying, intended to be a veYFI Liquid Locker token,
        where `S` is set on deployment and intended to be equal to the amount of liquid locker tokens
        per underlying YFI in its lock.
        Staked (deposited) assets can only be withdrawn by first unstaking them, which burns the 
        vault shares immediately and releases the underlying tokens in a stream, making
        them claimable through the regular 4626 `withdraw` or `redeem` methods.
        Operations modifiying the amount of shares are passed through to a hook. Transfers are disabled.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

interface IHooks:
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

implements: IERC4626

asset: public(immutable(address))
scale: public(immutable(uint256))
management: public(address)
pending_management: public(address)
killed: public(bool)
capacity: public(uint256)
hooks: public(IHooks)

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
packed_streams: public(HashMap[address, uint256]) # time | total | claimed

decimals: public(constant(uint8)) = 18
name: public(String[28])
symbol: public(String[10])

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event Deposit:
    sender: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

event Withdraw:
    sender: indexed(address)
    receiver: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

event SetKilled:
    killed: bool

event SetCapacity:
    capacity: uint256

event SetHooks:
    hooks: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

SMALL_MASK: constant(uint256) = 2**40 - 1
BIG_MASK: constant(uint256) = 2**108 - 1
STREAM_DURATION: constant(uint256) = 14 * 24 * 60 * 60

@deploy
def __init__(_asset: address, _scale: uint256, _name: String[10], _symbol: String[4]):
    """
    @notice Constructor
    @param _asset Underlying asset of the vault
    @param _scale The value of `S`, the amount of liquid locker tokens
        per underlying YFI in its lock
    @param _name Name of the Liquid Locker
    @param _symbol Symbol of the liquid locker
    """
    asset = _asset
    scale = _scale
    self.name = concat(_name, " Liquid Locker YFI")
    self.symbol = concat("llYFI-", _symbol)
    self.management = msg.sender

@external
def approve(_spender: address, _value: uint256) -> bool:
    """
    @notice Approve spending of the caller's tokens
    @param _spender User that is allowed to spend caller's tokens
    @param _value Amount of tokens spender is allowed to spend
    @return Always True
    """
    assert _spender != empty(address)

    self.allowance[msg.sender][_spender] = _value

    log Approval(owner=msg.sender, spender=_spender, value=_value)
    return True

@external
def deposit(_assets: uint256, _receiver: address = msg.sender) -> uint256:
    """
    @notice Deposit assets
    @param _assets Amount of assets to deposit
    @param _receiver Recipient of the shares
    @return Amount of shares minted
    """
    assert _assets >= scale
    self._stake(_receiver, _assets // scale)
    assert extcall IERC20(asset).transferFrom(msg.sender, self, _assets, default_return_value=True)
    return _assets // scale

@external
def mint(_shares: uint256, _receiver: address = msg.sender) -> uint256:
    """
    @notice Mint shares
    @param _shares Amount of shares to mint
    @param _receiver Recipient of the shares
    @return Amount of assets deposited
    """
    self._stake(_receiver, _shares)
    assert extcall IERC20(asset).transferFrom(msg.sender, self, _shares * scale, default_return_value=True)
    return _shares * scale

@external
def unstake(_shares: uint256):
    """
    @notice Unstake shares, streaming them out
    @param _shares Amount of shares to unstake
    @dev Adds existing stream to new stream, if applicable
    """
    assert _shares > 0

    prev_supply: uint256 = self.totalSupply
    prev_balance: uint256 = self.balanceOf[msg.sender]
    self.totalSupply = prev_supply - _shares
    self.balanceOf[msg.sender] = prev_balance - _shares

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[msg.sender])
    self.packed_streams[msg.sender] = self._pack(block.timestamp, total - claimed + _shares, 0)

    extcall self.hooks.on_unstake(msg.sender, prev_supply, prev_balance, _shares)

    log Transfer(sender=msg.sender, receiver=empty(address), value=_shares)

@external
def withdraw(_assets: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    """
    @notice Withdraw assets
    @param _assets Amount of assets to withdraw
    @param _receiver Recipient of the assets
    @param _owner Owner of the shares
    @return Amount of shares redeemed
    @dev Requires unstaking before assets become withdrawable in a stream
    """
    self._redeem(_owner, _assets // scale, _receiver)
    return _assets // scale

@external
def redeem(_shares: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    """
    @notice Redeem shares
    @param _shares Amount of shares to redeem
    @param _receiver Recipient of the assets
    @param _owner Owner of the shares
    @return Amount of assets withdrawn
    @dev Requires unstaking before assets become withdrawable in a stream
    """
    self._redeem(_owner, _shares, _receiver)
    return _shares * scale

@view
@external
def totalAssets() -> uint256:
    """
    @notice Get the total amount of assets in the vault
    @return Total amount of assets
    @dev Does not include any assets that are currently being unstaked
    """
    return self.totalSupply * scale

@view
@external
def convertToShares(_assets: uint256) -> uint256:
    """
    @notice Convert an amount of assets to shares
    @param _assets Amount of assets
    @return Amount of shares
    """
    return _assets // scale

@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    """
    @notice Convert an amount of shares to assets
    @param _shares Amount of shares
    @return Amount of assets
    """
    return _shares * scale

@view
@external
def maxDeposit(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets a user can deposit
    @param _owner User depositing
    @return Maximum amount of assets that can be deposited
    """
    supply: uint256 = self.totalSupply
    capacity: uint256 = self.capacity
    if self.killed or supply >= capacity:
        return 0
    return (capacity - supply) * scale

@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    """
    @notice Preview a deposit
    @param _assets Amount of assets to be deposited
    @return Equivalent amount of shares to be minted
    """
    return _assets // scale

@view
@external
def maxMint(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares a user can mint
    @param _owner User minting
    @return Maximum amount of shares that can be minted
    """
    supply: uint256 = self.totalSupply
    capacity: uint256 = self.capacity
    if self.killed or supply >= capacity:
        return 0
    return capacity - supply

@view
@external
def previewMint(_shares: uint256) -> uint256:
    """
    @notice Preview a mint
    @param _shares Amount of shares to be minted
    @return Equivalent amount of assets to be deposited
    """
    return _shares * scale

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets a user can withdraw
    @param _owner User withdrawing
    @return Maximum amount of assets that can be withdrawn
    """
    return self._redeemable(_owner) * scale

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    """
    @notice Preview a withdrawal
    @param _assets Amount of assets to be withdrawn
    @return Equivalent amount of shares to be burned
    """
    return _assets // scale

@view
@external
def maxRedeem(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares a user can redeem
    @param _owner User redeeming
    @return Maximum amount of shares that can be redeemed
    """
    return self._redeemable(_owner)

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    """
    @notice Preview a redemption
    @param _shares Amount of shares to be redeemed
    @return Equivalent amount of assets to be withdrawn
    """
    return _shares * scale

@external
@view
def streams(_account: address) -> (uint256, uint256, uint256):
    """
    @notice Get a user's stream details
    @param _account User address
    @return Tuple with stream start time, stream amount, claimed amount
    """
    return self._unpack(self.packed_streams[_account])

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    """
    @notice Transfer out a token
    @param _token The token address
    @param _amount The amount of tokens. Defaults to all
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _token != asset

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC20(_token).balanceOf(self)

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_killed(_killed: bool):
    """
    @notice Set the killed status
    @param _killed True: kill the vault, disabling deposits
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.killed = _killed
    log SetKilled(killed=_killed)

@external
def set_capacity(_capacity: uint256):
    """
    @notice Set the vault capacity, which is the maximum supply
    @param _capacity The capacity
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _capacity <= max_value(uint256) // scale

    self.capacity = _capacity
    log SetCapacity(capacity=_capacity)

@external
def set_hooks(_hooks: address):
    """
    @notice Set the hooks address
    @param _hooks New hooks address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.hooks = IHooks(_hooks)
    log SetHooks(hooks=_hooks)

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
def _stake(_receiver: address, _shares: uint256):
    """
    @notice Mint shares and take underlying tokens from caller
    """
    assert not self.killed
    assert _receiver != empty(address) and _receiver != self

    prev_supply: uint256 = self.totalSupply
    prev_balance: uint256 = self.balanceOf[_receiver]
    
    supply: uint256 = prev_supply + _shares
    assert supply <= self.capacity
    self.totalSupply = supply
    self.balanceOf[_receiver] = prev_balance + _shares

    extcall self.hooks.on_stake(msg.sender, _receiver, prev_supply, prev_balance, _shares)

    log Deposit(sender=msg.sender, owner=_receiver, assets=_shares * scale, shares=_shares)
    log Transfer(sender=empty(address), receiver=_receiver, value=_shares)

@internal
@view
def _redeemable(_account: address) -> uint256:
    """
    @notice Get immediate redeemable amount
    """
    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[_account])
    if time == 0:
        return 0
    time = min(block.timestamp - time, STREAM_DURATION)

    return max(total * time // STREAM_DURATION, claimed) - claimed

@internal
def _redeem(_owner: address, _shares: uint256, _receiver: address):
    """
    @notice Redeem from the stream
    """
    assert _receiver != empty(address) and _receiver != self
    
    # check allowance
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender]
        if allowance < max_value(uint256):
            self.allowance[_owner][msg.sender] = allowance - _shares

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[_owner])

    claimable: uint256 = 0
    if time > 0:
        # calculate time since unstake
        claimable = total * min(block.timestamp - time, STREAM_DURATION) // STREAM_DURATION

    claimed += _shares
    assert claimed <= claimable

    if claimed < total:
        self.packed_streams[_owner] = self._pack(time, total, claimed)
    else:
        self.packed_streams[_owner] = 0

    assert extcall IERC20(asset).transfer(_receiver, _shares * scale, default_return_value=True)

    log Withdraw(sender=msg.sender, receiver=_receiver, owner=_owner, assets=_shares * scale, shares=_shares)

@internal
@pure
def _pack(_a: uint256, _b: uint256, _c: uint256) -> uint256:
    """
    @notice Pack a small value and two big values into a single storage slot
    """
    assert _a <= SMALL_MASK and _b <= BIG_MASK and _c <= BIG_MASK
    return (_a << 216) | (_b << 108) | _c

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256, uint256):
    """
    @notice Unpack a small value and two big values from a single storage slot
    """
    return _packed >> 216, (_packed >> 108) & BIG_MASK, _packed & BIG_MASK

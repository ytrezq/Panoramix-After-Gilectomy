# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Delegated Staked YFI
@author Yearn Finance
@license GNU AGPLv3
@notice ERC4626 vault that is 1:1 to the underlying, intended to be the YFI token.
        Staked assets are deposited into StakedYFI and can only be withdrawn by first unstaking 
        them, which burns the vault shares immediately and releases the underlying tokens in a stream, making
        them claimable through the regular 4626 `withdraw` or `redeem` methods.
        Works under the assumption that it is whitelisted for instant withdrawals in StakedYFI.
        Operations modifiying the amount of shares are passed through to a hook.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626
implements: IERC20
implements: IERC4626

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

asset: public(immutable(address))
staking: public(immutable(IERC4626))
management: public(address)
pending_management: public(address)
killed: public(bool)
hooks: public(IHooks)

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
packed_streams: public(HashMap[address, uint256]) # time | total | claimed

decimals: public(constant(uint8)) = 18
name: public(constant(String[14])) = "Staked YFI Max"
symbol: public(constant(String[6])) = "stYFIx"

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
def __init__(_staking: address):
    """
    @notice Constructor
    @param _staking Address of StakedYFI (stYFI)
    """
    staking = IERC4626(_staking)
    asset = staticcall staking.asset()
    self.management = msg.sender

    assert extcall IERC20(asset).approve(_staking, max_value(uint256), default_return_value=True)

@external
def transfer(_to: address, _value: uint256) -> bool:
    """
    @notice Transfer tokens to another user
    @param _to User to transfer tokens to
    @param _value Amount of tokens to transfer
    @return Always True
    @dev Reverts if caller does not have at least `_value` tokens
    """
    self._transfer(msg.sender, _to, _value)

    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    """
    @notice Transfer another user's tokens by spending an allowance
    @param _from User to transfer tokens from
    @param _to User to transfer tokens to
    @param _value Amount of tokens to transfer
    @return Always True
    @dev Reverts if `_from` does not have at least `_value` tokens, or if caller
         does not have at least `_value` allowance to spend from `_from`
    """
    if _value > 0:
        allowance: uint256 = self.allowance[_from][msg.sender]
        if allowance < max_value(uint256):
            self.allowance[_from][msg.sender] = allowance - _value

    self._transfer(_from, _to, _value)

    return True

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
    self._stake(_receiver, _assets)
    return _assets

@external
def mint(_shares: uint256, _receiver: address = msg.sender) -> uint256:
    """
    @notice Mint shares
    @param _shares Amount of shares to mint
    @param _receiver Recipient of the shares
    @return Amount of assets deposited
    """
    self._stake(_receiver, _shares)
    return _shares

@external
def unstake(_assets: uint256):
    """
    @notice Unstake assets, streaming them out
    @param _assets Amount of assets to unstake
    @dev Adds existing stream to new stream, if applicable
    """
    self._unstake(msg.sender, _assets)

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
    self._withdraw(_owner, _assets, _receiver)
    return _assets

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
    self._withdraw(_owner, _shares, _receiver)
    return _shares

@view
@external
def totalAssets() -> uint256:
    """
    @notice Get the total amount of assets in the vault
    @return Total amount of assets
    @dev Does not include any assets that are currently being unstaked
    """
    return self.totalSupply

@view
@external
def convertToShares(_assets: uint256) -> uint256:
    """
    @notice Convert an amount of assets to shares
    @param _assets Amount of assets
    @return Amount of shares
    """
    return _assets

@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    """
    @notice Convert an amount of shares to assets
    @param _shares Amount of shares
    @return Amount of assets
    """
    return _shares

@view
@external
def maxDeposit(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets a user can deposit
    @param _owner User depositing
    @return Maximum amount of assets that can be deposited
    """
    if self.killed:
        return 0
    return max_value(uint256)

@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    """
    @notice Preview a deposit
    @param _assets Amount of assets to be deposited
    @return Equivalent amount of shares to be minted
    """
    return _assets

@view
@external
def maxMint(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares a user can mint
    @param _owner User minting
    @return Maximum amount of shares that can be minted
    """
    if self.killed:
        return 0
    return max_value(uint256)

@view
@external
def previewMint(_shares: uint256) -> uint256:
    """
    @notice Preview a mint
    @param _shares Amount of shares to be minted
    @return Equivalent amount of assets to be deposited
    """
    return _shares

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets a user can withdraw
    @param _owner User withdrawing
    @return Maximum amount of assets that can be withdrawn
    """
    return self._withdrawable(_owner)

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    """
    @notice Preview a withdrawal
    @param _assets Amount of assets to be withdrawn
    @return Equivalent amount of shares to be burned
    """
    return _assets

@view
@external
def maxRedeem(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares a user can redeem
    @param _owner User redeeming
    @return Maximum amount of shares that can be redeemed
    """
    return self._withdrawable(_owner)

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    """
    @notice Preview a redemption
    @param _shares Amount of shares to be redeemed
    @return Equivalent amount of assets to be withdrawn
    """
    return _shares

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
    assert _token not in [asset, staking.address]

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
def _transfer(_from: address, _to: address, _value: uint256):
    """
    @notice Transfer vault shares from one owner to another
    """
    assert _from != _to
    assert _to != empty(address) and _to != self

    prev_from: uint256 = self.balanceOf[_from]
    prev_to: uint256 = self.balanceOf[_to]
    self.balanceOf[_from] = prev_from - _value
    self.balanceOf[_to] = prev_to + _value

    extcall self.hooks.on_transfer(msg.sender, _from, _to, self.totalSupply, prev_from, prev_to, _value)

    log Transfer(sender=_from, receiver=_to, value=_value)

@internal
def _stake(_receiver: address, _value: uint256):
    """
    @notice Mint shares, take underlying tokens from caller and deposit into staking contract
    """
    assert not self.killed
    assert _receiver != empty(address) and _receiver != self

    prev_supply: uint256 = self.totalSupply
    prev_balance: uint256 = self.balanceOf[_receiver]
    self.totalSupply = prev_supply + _value
    self.balanceOf[_receiver] = prev_balance + _value

    assert extcall IERC20(asset).transferFrom(msg.sender, self, _value, default_return_value=True)
    extcall staking.deposit(_value, self)
    extcall self.hooks.on_stake(msg.sender, _receiver, prev_supply, prev_balance, _value)

    log Deposit(sender=msg.sender, owner=_receiver, assets=_value, shares=_value)
    log Transfer(sender=empty(address), receiver=_receiver, value=_value)

@internal
def _unstake(_owner: address, _value: uint256):
    """
    @notice Burn shares, withdraw from staking contract and create/update the stream
    """
    assert _value > 0

    prev_supply: uint256 = self.totalSupply
    prev_balance: uint256 = self.balanceOf[_owner]
    self.totalSupply = prev_supply - _value
    self.balanceOf[_owner] = prev_balance - _value

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[_owner])
    self.packed_streams[_owner] = self._pack(block.timestamp, total - claimed + _value, 0)

    extcall staking.withdraw(_value, self, self)
    extcall self.hooks.on_unstake(_owner, prev_supply, prev_balance, _value)

    log Transfer(sender=_owner, receiver=empty(address), value=_value)

@internal
@view
def _withdrawable(_account: address) -> uint256:
    """
    @notice Get immediate withdrawable amount
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
def _withdraw(_owner: address, _value: uint256, _receiver: address):
    """
    @notice Withdraw from the stream
    """
    assert _receiver != empty(address) and _receiver != self
    
    # check allowance
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender]
        if allowance < max_value(uint256):
            self.allowance[_owner][msg.sender] = allowance - _value

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[_owner])

    claimable: uint256 = 0
    if time > 0:
        # calculate time since unstake
        claimable = total * min(block.timestamp - time, STREAM_DURATION) // STREAM_DURATION
        
    claimed += _value
    assert claimed <= claimable

    if claimed < total:
        self.packed_streams[_owner] = self._pack(time, total, claimed)
    else:
        self.packed_streams[_owner] = 0

    assert extcall IERC20(asset).transfer(_receiver, _value, default_return_value=True)

    log Withdraw(sender=msg.sender, receiver=_receiver, owner=_owner, assets=_value, shares=_value)

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

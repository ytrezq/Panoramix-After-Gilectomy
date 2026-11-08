# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed
from ethereum.ercs import IERC4626
implements: IERC20
implements: IERC4626

asset: public(immutable(address))
scale: public(uint256)

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

name: public(constant(String[9])) = "MockVault"
symbol: public(constant(String[6])) = "stMOCK"

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


@deploy
def __init__(_asset: address):
    asset = _asset
    self.scale = 1

@external
def set_scale(_scale: uint256):
    self.scale = _scale

@external
@view
def decimals() -> uint8:
    return staticcall IERC20Detailed(asset).decimals()

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address)
    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log Transfer(sender=msg.sender, receiver=_to, value=_value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address)
    self.allowance[_from][msg.sender] -= _value
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    log Transfer(sender=_from, receiver=_to, value=_value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    assert _spender != empty(address)
    self.allowance[msg.sender][_spender] = _value
    log Approval(owner=msg.sender, spender=_spender, value=_value)
    return True

@external
def deposit(_assets: uint256, _receiver: address = msg.sender) -> uint256:
    assert _assets >= self.scale
    self._mint(_receiver, _assets // self.scale)
    assert extcall IERC20(asset).transferFrom(msg.sender, self, _assets, default_return_value=True)
    return _assets // self.scale

@external
def mint(_shares: uint256, _receiver: address = msg.sender) -> uint256:
    self._mint(_receiver, _shares)
    assert extcall IERC20(asset).transferFrom(msg.sender, self, _shares * self.scale, default_return_value=True)
    return _shares * self.scale

@external
def withdraw(_assets: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._redeem(_owner, _assets // self.scale, _receiver)
    return _assets // self.scale

@external
def redeem(_shares: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._redeem(_owner, _shares, _receiver)
    return _shares * self.scale

@view
@external
def totalAssets() -> uint256:
    return self.totalSupply * self.scale

@view
@external
def convertToShares(_assets: uint256) -> uint256:
    return _assets // self.scale

@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    return _shares * self.scale

@view
@external
def maxDeposit(_owner: address) -> uint256:
    return max_value(uint256)

@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    return _assets // self.scale

@view
@external
def maxMint(_owner: address) -> uint256:
    return max_value(uint256)

@view
@external
def previewMint(_shares: uint256) -> uint256:
    return _shares * self.scale

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    return self.balanceOf[_owner] * self.scale

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    return _assets // self.scale

@view
@external
def maxRedeem(_owner: address) -> uint256:
    return self.balanceOf[_owner]

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    return _shares * self.scale

@internal
def _mint(_receiver: address, _shares: uint256):
    assert _receiver != empty(address) and _receiver != self

    self.totalSupply += _shares
    self.balanceOf[_receiver] += _shares

    log Deposit(sender=msg.sender, owner=_receiver, assets=_shares * self.scale, shares=_shares)
    log Transfer(sender=empty(address), receiver=_receiver, value=_shares)

@internal
def _redeem(_owner: address, _shares: uint256, _receiver: address):
    assert _receiver != empty(address) and _receiver != self

    self.totalSupply -= _shares
    self.balanceOf[_owner] -= _shares

    assert extcall IERC20(asset).transfer(_receiver, _shares * self.scale, default_return_value=True)

    log Withdraw(sender=msg.sender, receiver=_receiver, owner=_owner, assets=_shares * self.scale, shares=_shares)
    log Transfer(sender=msg.sender, receiver=empty(address), value=_shares)

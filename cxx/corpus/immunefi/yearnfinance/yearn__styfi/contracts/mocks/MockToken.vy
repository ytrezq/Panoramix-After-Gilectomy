# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

from ethereum.ercs import IERC20
implements: IERC20

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

name: public(constant(String[9])) = "MockToken"
symbol: public(constant(String[4])) = "MOCK"
decimals: public(uint8)

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

@deploy
def __init__():
    self.decimals = 18
    log Transfer(sender=empty(address), receiver=msg.sender, value=0)

@external
def set_decimals(_decimals: uint8):
    self.decimals = _decimals

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
    self.allowance[msg.sender][_spender] = _value
    log Approval(owner=msg.sender, spender=_spender, value=_value)
    return True

@external
def mint(_account: address, _value: uint256):
    self.totalSupply += _value
    self.balanceOf[_account] += _value
    log Transfer(sender=empty(address), receiver=_account, value=_value)

@external
def burn(_account: address, _value: uint256):
    self.totalSupply -= _value
    self.balanceOf[_account] -= _value
    log Transfer(sender=_account, receiver=empty(address), value=_value)

# @version ^0.3.7
# A token (Vyper 0.3's syntax; token_04.vy is the same contract in 0.4's):
# nested mappings, the compiler's overflow checks, external calls through an
# interface, loops over calldata arrays, storage strings returned by getters.
# Compiled by tests/fixtures/compile.sh (-f bytecode_runtime).

interface ERC20:
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def balanceOf(_owner: address) -> uint256: view

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

name: public(String[32])
symbol: public(String[8])
decimals: public(uint8)
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
minter: address
deposits: public(HashMap[address, HashMap[address, uint256]])


@external
def __init__():
    self.name = "Fixture Token"
    self.symbol = "FIX"
    self.decimals = 18
    self.minter = msg.sender


@external
def transfer(to: address, amount: uint256) -> bool:
    self.balanceOf[msg.sender] -= amount
    self.balanceOf[to] += amount
    log Transfer(msg.sender, to, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    self.allowance[msg.sender][spender] = amount
    log Approval(msg.sender, spender, amount)
    return True


@external
def transferFrom(owner: address, to: address, amount: uint256) -> bool:
    self.allowance[owner][msg.sender] -= amount
    self.balanceOf[owner] -= amount
    self.balanceOf[to] += amount
    log Transfer(owner, to, amount)
    return True


@external
def mint(to: address, amount: uint256):
    assert msg.sender == self.minter, "minter only"
    self.totalSupply += amount
    self.balanceOf[to] += amount
    log Transfer(empty(address), to, amount)


@external
def batch(to: DynArray[address, 5], amounts: DynArray[uint256, 5]):
    assert len(to) == len(amounts), "lengths"
    for i in range(5):
        if i >= len(to):
            break
        self.balanceOf[msg.sender] -= amounts[i]
        self.balanceOf[to[i]] += amounts[i]
        log Transfer(msg.sender, to[i], amounts[i])


@view
@external
def total_of(holders: DynArray[address, 10]) -> uint256:
    s: uint256 = 0
    for h in holders:
        s += self.balanceOf[h]
    return s


@view
@external
def share(amount: uint256, num: uint256, den: uint256) -> uint256:
    return amount * num / den


@external
def pull(token: address, amount: uint256):
    assert ERC20(token).transferFrom(msg.sender, self, amount), "transfer failed"
    self.deposits[token][msg.sender] += amount


@view
@external
def held(token: address) -> uint256:
    return ERC20(token).balanceOf(self)

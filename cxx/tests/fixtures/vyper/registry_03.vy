# @version ^0.3.7
# A registry of named entries (Vyper 0.3's syntax; registry_04.vy is the same
# contract in 0.4's): storage strings and a DynArray of structs copied to
# memory word by word, a mapping of balances, events, a default function.
# Compiled by tests/fixtures/compile.sh (-f bytecode_runtime).

struct Entry:
    name: String[64]
    owner: address
    weight: uint256
    note: String[40]

event Added:
    name_hash: indexed(String[64])
    entry: Entry

event Moved:
    who: indexed(address)
    amount: uint256

MAX_ENTRIES: constant(uint256) = 8

admin: public(address)
title: public(String[48])
entries: DynArray[Entry, MAX_ENTRIES]
balances: public(HashMap[address, uint256])
version: public(uint256)


@external
def __init__():
    self.admin = msg.sender
    self.title = "registry"


@view
@external
def count() -> uint256:
    return len(self.entries)


@view
@external
def all_entries() -> DynArray[Entry, MAX_ENTRIES]:
    return self.entries


@view
@external
def entry(i: uint256) -> Entry:
    return self.entries[i]


@view
@external
def find(name: String[64]) -> uint256:
    return self._find(name)


@external
def add_entry(name: String[64], weight: uint256, note: String[40]):
    assert msg.sender == self.admin, "not admin"
    assert len(self.entries) < MAX_ENTRIES, "full"
    e: Entry = Entry({name: name, owner: msg.sender, weight: weight, note: note})
    self.entries.append(e)
    self.version += 1
    log Added(name, e)


@external
def remove_entry(name: String[64]):
    assert msg.sender == self.admin, "not admin"
    n: uint256 = len(self.entries)
    i: uint256 = self._find(name)
    assert i < n, "no such entry"
    if i != n - 1:
        self.entries[i] = self.entries[n - 1]
    self.entries.pop()
    self.version += 1


@external
def set_title(t: String[48]):
    assert msg.sender == self.admin, "not admin"
    self.title = t


@payable
@external
def deposit():
    self.balances[msg.sender] += msg.value
    log Moved(msg.sender, msg.value)


@external
def withdraw(amount: uint256):
    self.balances[msg.sender] -= amount
    send(msg.sender, amount)
    log Moved(msg.sender, amount)


@payable
@external
def __default__():
    self.balances[msg.sender] += msg.value


@view
@internal
def _find(name: String[64]) -> uint256:
    i: uint256 = 0
    for e in self.entries:
        if keccak256(e.name) == keccak256(name):
            return i
        i += 1
    return max_value(uint256)

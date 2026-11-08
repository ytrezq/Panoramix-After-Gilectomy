# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def instant_withdrawal(_account: address) -> bool: view

implements: IHooks

struct Transfer:
    caller: address
    sender: address
    receiver: address
    supply: uint256
    prev_from: uint256
    prev_to: uint256
    amount: uint256

struct Stake:
    caller: address
    account: address
    prev_supply: uint256
    prev_balance: uint256
    amount: uint256

struct Unstake:
    account: address
    prev_supply: uint256
    prev_balance: uint256
    amount: uint256

last_transfer: public(Transfer)
last_stake: public(Stake)
last_unstake: public(Unstake)
last_proposal: public(uint256)
last_proposer: public(address)
last_retract: public(uint256)
last_vote: public(uint256)
last_voter: public(address)
instant_withdrawal: public(HashMap[address, bool])
num_triggers: public(uint256)

@external
def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256):
    self.num_triggers += 1
    self.last_transfer = Transfer(caller=_caller, sender=_from, receiver=_to, supply=_supply, prev_from=_prev_staked_from, prev_to=_prev_staked_to, amount=_value)

@external
def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256):
    self.num_triggers += 1
    self.last_stake = Stake(caller=_caller, account=_account, prev_supply=_prev_supply, prev_balance=_prev_staked, amount=_value)

@external
def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256):
    self.num_triggers += 1
    self.last_unstake = Unstake(account=_account, prev_supply=_prev_supply, prev_balance=_prev_staked, amount=_value)

@external
def on_propose(_idx: uint256, _proposer: address):
    self.last_proposal = _idx
    self.last_proposer = _proposer

@external
def on_retract(_idx: uint256):
    self.last_retract = _idx

@external
def on_vote(_idx: uint256, _account: address):
    self.last_vote = _idx
    self.last_voter = _account

@external
def set_instant_withdrawal(_account: address, _instant: bool):
    self.instant_withdrawal[_account] = _instant

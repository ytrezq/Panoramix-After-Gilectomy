# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IVotingEscrow:
    def locked(_account: address) -> (uint256, uint256): view

implements: IVotingEscrow

struct Locked:
    amount: uint256
    end: uint256

lock: public(HashMap[address, Locked])

@external
def set_locked(_account: address, _amount: uint256, _end: uint256):
    self.lock[_account] = Locked(amount=_amount, end=_end)

@external
@view
def locked(_account: address) -> (uint256, uint256):
    lock: Locked = self.lock[_account]
    return lock.amount, lock.end

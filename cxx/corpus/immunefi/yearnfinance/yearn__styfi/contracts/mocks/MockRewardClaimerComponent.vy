# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

from ethereum.ercs import IERC20

interface IComponent:
    def claim(_account: address) -> uint256: nonpayable

implements: IComponent

token: public(immutable(IERC20))
rewards: public(HashMap[address, uint256])

@deploy
def __init__(_token: address):
    token = IERC20(_token)

@external
def claim(_account: address) -> uint256:
    amount: uint256 = self.rewards[_account]
    self.rewards[_account] = 0
    assert extcall token.transfer(msg.sender, amount, default_return_value=True)
    return amount

@external
def set_rewards(_account: address, _amount: uint256):
    self.rewards[_account] = _amount

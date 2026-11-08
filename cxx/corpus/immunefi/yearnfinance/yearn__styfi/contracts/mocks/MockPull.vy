# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

from ethereum.ercs import IERC20

interface IPull:
    def pull(_epoch: uint256) -> uint256: nonpayable

implements: IPull

upstream: public(immutable(address))
token: public(immutable(IERC20))
rewards: public(HashMap[uint256, uint256])

@deploy
def __init__(_upstream:address, _token: address):
    upstream = _upstream
    token = IERC20(_token)
    
@external
def set_rewards(_epoch: uint256, _rewards: uint256):
    self.rewards[_epoch] = _rewards

@external
def pull(_epoch: uint256) -> uint256:
    assert msg.sender == upstream

    rewards: uint256 = self.rewards[_epoch]
    assert extcall token.approve(msg.sender, rewards, default_return_value=True)

    return rewards

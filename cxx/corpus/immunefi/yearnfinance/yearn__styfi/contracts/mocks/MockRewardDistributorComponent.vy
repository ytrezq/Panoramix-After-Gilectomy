# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IComponent:
    def sync_total_weight(_epoch: uint256) -> uint256: nonpayable

interface IDistributor:
    def claim() -> (uint256, uint256, uint256): nonpayable

implements: IComponent

upstream: public(immutable(address))
total_weight: public(HashMap[uint256, uint256])

@deploy
def __init__(_upstream: address):
    upstream = _upstream

@external
def set_total_weight(_epoch: uint256, _weight: uint256):
    self.total_weight[_epoch] = _weight

@external
def sync_total_weight(_epoch: uint256) -> uint256:
    assert msg.sender == upstream
    return self.total_weight[_epoch]

@external
def claim_upstream() -> (uint256, uint256, uint256):
    return extcall IDistributor(upstream).claim()

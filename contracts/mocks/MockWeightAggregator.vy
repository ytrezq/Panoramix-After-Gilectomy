# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IWeightAggregator:
    def weight(_account: address) -> uint256: view
implements: IWeightAggregator

weight: public(HashMap[address, uint256])

@external
def set_weight(_account: address, _weight: uint256):
    self.weight[_account] = _weight

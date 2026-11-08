# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

deployed: public(HashMap[address, bool])

@external
def set_deployed(_account: address, _deployed: bool):
    self.deployed[_account] = _deployed

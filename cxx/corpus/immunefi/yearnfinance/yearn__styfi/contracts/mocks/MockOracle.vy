# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IOracle:
    def price(_asset: address) -> uint256: view
implements: IOracle

price: public(HashMap[address, uint256])

@external
def set_price(_token: address, _price: uint256):
    self.price[_token] = _price

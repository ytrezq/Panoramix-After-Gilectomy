# @version 0.4.2

someNumber: public(uint256)
multiplier: public(uint256)

@deploy
def __init__(_mult: uint256):
    self.multiplier = _mult

@external
def setSomeNumber(_val: uint256):
    self.someNumber = _val

@external
def increment():
    self.someNumber = self.someNumber + 1

# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title YBC Bonus Recipient
@author Yearn Finance
@license GNU AGPLv3
@notice Helper contract that accepts YFI and deposits it into stYFI on behalf of the YBC.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

interface IYBCRecipient:
    def deposit_bonus(_amount: uint256): nonpayable

implements: IYBCRecipient

styfi: public(immutable(IERC4626))
yfi: public(immutable(IERC20))
ybc: public(immutable(address))

event Deposit:
    depositor: indexed(address)
    amount: uint256

@deploy
def __init__(_styfi: address, _ybc: address):
    """
    @notice Constructor
    @param _styfi stYFI address
    @param _ybc YBC address
    """
    styfi = IERC4626(_styfi)
    yfi = IERC20(staticcall styfi.asset())
    ybc = _ybc

    assert extcall yfi.approve(_styfi, max_value(uint256), default_return_value=True)

@external
def deposit_bonus(_amount: uint256):
    """
    @notice Deposit bonus tokens for the YBC
    @param _amount Amount of bonus tokens to deposit
    """
    assert extcall yfi.transferFrom(msg.sender, self, _amount, default_return_value=True)
    extcall styfi.deposit(_amount, ybc)
    log Deposit(depositor=msg.sender, amount=_amount)

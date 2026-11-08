# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Revenue Price Oracle
@author Yearn Finance
@license GNU AGPLv3
@notice Dual-functionality contract for the revenue recipient, acting as both price oracle for 
        a naked token (priced at $1) and a corresponding 4626 vault token, as well as converter 
        for the naked token into the vault token.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed
from ethereum.ercs import IERC4626

interface IOracle:
    def price(_asset: address) -> uint256: nonpayable
implements: IOracle

interface IConverter:
    def convert(_token: address, _amount: uint256): nonpayable

token: public(immutable(address))
vault: public(immutable(address))
scale: public(immutable(uint256))

@deploy
def __init__(_vault: address):
    """
    @notice Constructor
    @param _vault Vault address
    """
    vault = _vault
    token = staticcall IERC4626(_vault).asset()
    decimals: uint8 = staticcall IERC20Detailed(token).decimals()
    assert decimals <= 18
    scale = 10**(36 - convert(decimals, uint256))

    assert extcall IERC20(token).approve(_vault, max_value(uint256), default_return_value=True)

@external
def price(_token: address) -> uint256:
    """
    @notice Get token price
    @param _token Token address
    @return Value of 1 wad of tokens in USD (18 decimals)
    """
    if _token == token:
        return scale
    elif _token == vault:
        return staticcall IERC4626(vault).convertToAssets(scale)
    raise

@external
def convert(_token: address, _amount: uint256):
    """
    @notice Convert a token
    @param _token Token address
    @param _amount Token ammount
    """
    assert _token == token

    assert extcall IERC20(token).transferFrom(msg.sender, self, _amount, default_return_value=True)
    extcall IERC4626(vault).deposit(_amount, msg.sender)

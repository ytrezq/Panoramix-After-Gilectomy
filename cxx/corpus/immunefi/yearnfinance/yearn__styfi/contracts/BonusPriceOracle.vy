# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Bonus Price Oracle
@author Yearn Finance
@license GNU AGPLv3
@notice Tracks the price of the bonus token in each budget period.
        The price can be set manually for all historical periods and optionally can 
        be fetched from a spot price oracle for the most recent completed period.
"""

struct RoundData:
    id: uint80
    answer: int256
    started: uint256
    updated: uint256
    round: uint80

interface IBonusPriceOracle:
    def price(_period: uint256) -> uint256: nonpayable
implements: IBonusPriceOracle

interface IChainLink:
    def latestRoundData() -> RoundData: view

genesis: public(immutable(uint256))
management: public(address)
pending_management: public(address)
oracle: public(IChainLink)
oracle_timeout: public(uint256)
oracle_multiplier: public(uint256)
bonus_distributor: public(address)
prices: public(HashMap[uint256, uint256])

event SetPrice:
    period: indexed(uint256)
    price: uint256
    chainlink: bool

event SetPriceOracle:
    oracle: indexed(address)
    timeout: uint256
    multiplier: uint256

event SetBonusDistributor:
    distributor: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

PERIOD_LENGTH: constant(uint256) = 6 * 14 * 24 * 60 * 60

@deploy
def __init__(_genesis: uint256):
    genesis = _genesis
    self.management = msg.sender
    self.bonus_distributor = msg.sender

@external
@view
def period() -> uint256:
    """
    @notice Query the current budget period number
    @return The current budget period number
    """
    return self._period()

@external
def price(_period: uint256) -> uint256:
    """
    @notice Get the price of the bonus token
    @param _period The budget period number
    @return The value of 1 wad of bonus tokens in USD (18 decimals)
    @dev Will use and write a spot price oracle for the most recent period, if configured
    @dev If a bonus distributor is configured, only they may initially call this for the most recent period
    """
    current: uint256 = self._period()
    assert _period < current
    price: uint256 = self.prices[_period]

    if price == 0 and _period + 1 == current:
        # use oracle price for latest period
        assert self.bonus_distributor in [msg.sender, empty(address)]
        data: RoundData = staticcall self.oracle.latestRoundData()
        assert block.timestamp - data.updated < self.oracle_timeout
        assert data.answer > 0

        price = convert(data.answer, uint256) * self.oracle_multiplier
        self.prices[_period] = price
        log SetPrice(period=_period, price=price, chainlink=True)

    assert price > 0
    return price

@external
def set_price(_period: uint256, _price: uint256):
    """
    @notice Set the bonus token price for a period
    @param _period The budget period number
    @param _price The value of 1 wad of bonus tokens in USD (18 decimals)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _period <= self._period()

    self.prices[_period] = _price
    log SetPrice(period=_period, price=_price, chainlink=False)

@external
def set_price_oracle(_oracle: address, _timeout: uint256, _multiplier: uint256):
    """
    @notice Set the underlying spot price oracle
    @param _oracle Oracle address
    @param _timeout Time after which answers are considered stale
    @param _multiplier Value by which to multiply the spot oracle response with
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.oracle = IChainLink(_oracle)
    self.oracle_timeout = _timeout
    self.oracle_multiplier = _multiplier
    log SetPriceOracle(oracle=_oracle, timeout=_timeout, multiplier=_multiplier)

@external
def set_bonus_distributor(_distributor: address):
    """
    @notice Set the bonus distributor
    @param _distributor Bonus distributor
    @dev If non-zero, only they may initially query the price for the most recent period
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.bonus_distributor = _distributor
    log SetBonusDistributor(distributor=_distributor)

@external
def set_management(_management: address):
    """
    @notice Set the pending management address.
            Needs to be accepted by that account separately to transfer management over
    @param _management New pending management address
    """
    assert msg.sender == self.management

    self.pending_management = _management
    log PendingManagement(management=_management)

@external
def accept_management():
    """
    @notice Accept management role.
            Can only be called by account previously marked as pending by current management
    """
    assert msg.sender == self.pending_management

    self.pending_management = empty(address)
    self.management = msg.sender
    log SetManagement(management=msg.sender)

@internal
@view
def _period() -> uint256:
    return unsafe_div(block.timestamp - genesis, PERIOD_LENGTH)

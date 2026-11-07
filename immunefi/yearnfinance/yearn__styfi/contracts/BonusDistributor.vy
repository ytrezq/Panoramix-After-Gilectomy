# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Bonus Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice Awards bonus tokens to teams based on their profit. The bonus token is priced by an oracle 
        and is adjusted by the growth of revenue of all teams combined, meaning growth is rewarded 
        by a lowering of the effective bonus token price, resulting in more bonus tokens being awarded.
        The awarded tokens are split between the teams and the YBC, with a configurable ratio.
"""

from ethereum.ercs import IERC20

struct Parameters:
    bonus_factor: uint256
    ybc_split: uint256
    bonus_price: uint256

interface IAccountant:
    def global_revenues(_period: uint256) -> uint256: view
    def team_profits(_team: address, _period: uint256) -> uint256: view

interface ITeam:
    def owner() -> address: view

interface IBonusPriceOracle:
    def price(_period: uint256) -> uint256: nonpayable

interface IYBCRecipient:
    def deposit_bonus(_amount: uint256): nonpayable

genesis: public(immutable(uint256))
bonus_token: public(immutable(IERC20))
management: public(address)
pending_management: public(address)
operator: public(address)
accountant: public(IAccountant)
bonus_price_oracle: public(IBonusPriceOracle)
ybc_recipient: public(IYBCRecipient)

smoothing_factor: public(uint256)
growth_rate_cap: public(uint256)
bonus_factor: public(uint256)
ybc_split: public(uint256)

pending_period: public(uint256)
pending_claims: public(HashMap[address, uint256]) # team => pending claim period
ema_revenue: public(uint256)
parameters: public(HashMap[uint256, Parameters])

event ClaimBonus:
    team: indexed(address)
    period: indexed(uint256)
    amount: uint256
    ybc_amount: uint256
    recipient: address

event SetOperator:
    operator: indexed(address)

event SetAccountant:
    accountant: indexed(address)

event SetBonusPriceOracle:
    oracle: indexed(address)

event SetYBC:
    recipient: indexed(address)
    split: uint256

event SetSmoothingFactor:
    factor: uint256

event SetGrowthRateCap:
    cap: uint256

event SetBonusFactor:
    factor: uint256

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

PRECISION: constant(uint256) = 10**18
BPS_PRECISION: constant(uint256) = 10000
PERIOD_LENGTH: constant(uint256) = 6 * 14 * 24 * 60 * 60

@deploy
def __init__(_genesis: uint256, _token: address):
    """
    @notice Constructor
    @param _genesis Budget period genesis timestamp
    @param _token Bonus token address
    """
    genesis = _genesis
    bonus_token = IERC20(_token)

    self.management = msg.sender
    self.operator = msg.sender
    self.smoothing_factor = PRECISION
    self.growth_rate_cap = BPS_PRECISION * 4 // 5
    self.bonus_factor = BPS_PRECISION

@external
@view
def period() -> uint256:
    """
    @notice Query the current budget period number
    @return The current budget period number
    """
    return self._period()

@external
def finalize_period() -> (uint256, uint256, uint256):
    """
    @notice Finalize bonus accounting for a budget period
    @return Tuple with: budget period number, spot token price, growth factor
    @dev Can only be called by the operator, if set
    """
    assert self.operator in [msg.sender, empty(address)]
    period: uint256 = self.pending_period
    assert self._period() > period
    self.pending_period = period + 1

    # compute EMA smoothed revenue
    global_revenue: uint256 = staticcall self.accountant.global_revenues(period)
    prev_ema_revenue: uint256 = self.ema_revenue
    ema_revenue: uint256 = 0
    if period == 0:
        prev_ema_revenue = global_revenue
        ema_revenue = global_revenue
    else:
        smoothing_factor: uint256 = self.smoothing_factor
        ema_revenue = (smoothing_factor * global_revenue + (PRECISION - smoothing_factor) * prev_ema_revenue) // PRECISION
    self.ema_revenue = ema_revenue

    if prev_ema_revenue == 0:
        # prevent division by zero - the cap will keep the growth factor in check
        prev_ema_revenue = 1

    # compute global growth and cap in either direction
    growth_rate_cap: uint256 = self.growth_rate_cap * PRECISION // BPS_PRECISION
    growth_factor: uint256 = ema_revenue * PRECISION // prev_ema_revenue
    growth_factor = min(growth_factor, PRECISION + growth_rate_cap)
    growth_factor = max(growth_factor, PRECISION - growth_rate_cap)

    # calculate adjusted bonus token price
    price: uint256 = extcall self.bonus_price_oracle.price(period)
    adjusted_price: uint256 = price * (2 * PRECISION - growth_factor) // PRECISION

    self.parameters[period] = Parameters(bonus_factor=self.bonus_factor, ybc_split=self.ybc_split, bonus_price=adjusted_price)
    return period, price, growth_factor

@external
def claim(_team: address, _recipient: address = msg.sender) -> (uint256, uint256):
    """
    @notice Claim a team's bonus tokens
    @param _team Team address
    @param _recipient Receiver of the bonus tokens. Defaults to caller
    @return Tuple with: bonus tokens to team, bonus tokens to YBC
    @dev Can only be called by the team owner
    """
    assert msg.sender == staticcall ITeam(_team).owner()

    total_amount: uint256 = 0
    ybc_amount: uint256 = 0

    pending: uint256 = self.pending_period
    period: uint256 = self.pending_claims[_team]
    for i: uint256 in range(16):
        if period == pending:
            break

        par: Parameters = self.parameters[period]
        profit: uint256 = staticcall self.accountant.team_profits(_team, period)
        amount: uint256 = profit * par.bonus_factor * PRECISION // par.bonus_price // BPS_PRECISION
        total_amount += amount
        
        loop_ybc_amount: uint256 = amount * par.ybc_split // BPS_PRECISION
        ybc_amount += loop_ybc_amount

        log ClaimBonus(team=_team, period=period, amount=amount, ybc_amount=loop_ybc_amount, recipient=_recipient)
        period += 1

    self.pending_claims[_team] = period

    team_amount: uint256 = total_amount - ybc_amount
    if team_amount > 0:
        assert extcall bonus_token.transfer(_recipient, team_amount, default_return_value=True)

    if ybc_amount > 0:
        recipient: IYBCRecipient = self.ybc_recipient
        assert extcall bonus_token.approve(recipient.address, ybc_amount, default_return_value=True)
        extcall recipient.deposit_bonus(ybc_amount)

    return team_amount, ybc_amount

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    """
    @notice Transfer out a token
    @param _token The token address
    @param _amount The amount of tokens. Defaults to all
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC20(_token).balanceOf(self)

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_operator(_operator: address):
    """
    @notice Set a new operator
    @param _operator New operator address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.operator = _operator
    log SetOperator(operator=_operator)

@external
def set_accountant(_accountant: address):
    """
    @notice Set a new accountant
    @param _accountant New accountant address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.accountant = IAccountant(_accountant)
    log SetAccountant(accountant=_accountant)

@external
def set_bonus_price_oracle(_oracle: address):
    """
    @notice Set a new bonus price oracle
    @param _oracle New bonus price oracle address
    @dev The oracle should return the value of 1 wad of bonus tokens in USD (18 decimals)
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.bonus_price_oracle = IBonusPriceOracle(_oracle)
    log SetBonusPriceOracle(oracle=_oracle)

@external
def set_ybc(_recipient: address, _split: uint256):
    """
    @notice Set the YBC parameters
    @param _recipient YBC recipient
    @param _split Split of bonus tokens to the YBC (bps)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _recipient != empty(address)
    assert _split <= BPS_PRECISION

    self.ybc_recipient = IYBCRecipient(_recipient)
    self.ybc_split = _split
    log SetYBC(recipient=_recipient, split=_split)

@external
def set_smoothing_factor(_factor: uint256):
    """
    @notice Set the revenue smoothing factor
    @param _factor Revenue soothing factor (18 decimals)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _factor <= PRECISION

    self.smoothing_factor = _factor
    log SetSmoothingFactor(factor=_factor)

@external
def set_growth_rate_cap(_cap: uint256):
    """
    @notice Set the cap on the growth rate
    @param _cap Growth rate cap (bps)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _cap <= BPS_PRECISION * 4 // 5

    self.growth_rate_cap = _cap
    log SetGrowthRateCap(cap=_cap)

@external
def set_bonus_factor(_factor: uint256):
    """
    @notice Set the bonus factor
    @param _factor Bonus factor (bps)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _factor <= 2 * BPS_PRECISION

    self.bonus_factor = _factor
    log SetBonusFactor(factor=_factor)

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

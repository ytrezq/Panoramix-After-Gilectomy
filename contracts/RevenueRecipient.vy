# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Revenue Recipient
@author Yearn Finance
@license GNU AGPLv3
@notice Temporary contract designed to take in team revenues as they are submitted, before
        they are redistributed to stYFI + treasury + yETH recovery by the operator.
        Will eventually be replaced by a contract that automatically spreads incoming revenues
        over the appropriate stYFI epochs.
"""

from ethereum.ercs import IERC20

interface IRevenueRecipient:
    def deposit(_token: address, _amount: uint256) -> (uint256, uint256): nonpayable
implements: IRevenueRecipient

interface IAccountant:
    def adjust_revenue(_team: address, _period: uint256, _amount: uint256, _increment: bool): nonpayable

interface IOracle:
    def price(_asset: address) -> uint256: nonpayable

interface IConverter:
    def convert(_token: address, _amount: uint256): nonpayable

interface IRegistry:
    def is_team(_team: address) -> bool: view

interface IRewardDistributor:
    def token() -> address: view
    def deposit(_epoch: uint256, _amount: uint256): nonpayable

interface IAuction:
    def auctions(_token: address) -> (uint64, uint64, uint128): view
    def kick(_token: address): nonpayable

genesis: public(immutable(uint256))
token: public(immutable(IERC20))
token_split: public(immutable(uint256[3])) # stYFI, treasury, yETH
management: public(address)
pending_management: public(address)
killed: public(bool)
operator: public(address)
registry: public(IRegistry)
accountant: public(IAccountant)
treasury: public(address)
reward_distributor: public(IRewardDistributor)
recovery_auction: public(IAuction)
oracles: public(HashMap[address, address])
converters: public(HashMap[address, address])

last_balance: public(uint256)
sum_balance: public(uint256)
used: public(uint256[3])

event DepositRevenue:
    team: indexed(address)
    period: indexed(uint256)
    token: address
    amount: uint256
    revenue: uint256

event ConvertToken:
    token: indexed(address)
    converter: address
    amount: uint256

event ToTreasury:
    amount: uint256

event ToRewards:
    epoch: indexed(uint256)
    amount: uint256

event ToRecovery:
    amount: uint256

event Kill: pass

event SetOperator:
    operator: indexed(address)

event SetRegistry:
    registry: indexed(address)

event SetAccountant:
    accountant: indexed(address)

event SetTreasury:
    treasury: indexed(address)

event SetRewardDistributor:
    distributor: indexed(address)

event SetRecoveryAuction:
    auction: indexed(address)

event SetPriceOracle:
    token: indexed(address)
    oracle: address

event SetTokenConverter:
    token: indexed(address)
    converter: address

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

PRECISION: constant(uint256) = 10**18
BPS_PRECISION: constant(uint256) = 10000
PERIOD_LENGTH: constant(uint256) = 6 * 14 * 24 * 60 * 60
AUCTION_LENGTH: constant(uint256) = 24 * 60 * 60
INCREMENT: constant(bool) = True

@deploy
def __init__(_genesis: uint256, _token: address, _split: uint256[3]):
    """
    @notice Constructor
    @param _genesis Budget period genesis timestamp
    @param _token Main revenue token
    @param _split Token split between stYFI, treasury and yETH (in that order, bps)
    """
    assert _split[0] + _split[1] + _split[2] == BPS_PRECISION

    genesis = _genesis
    token = IERC20(_token)
    token_split = _split

    self.management = msg.sender
    self.operator = msg.sender
    self.treasury = msg.sender

@external
@view
def period() -> uint256:
    """
    @notice Query the current budget period number
    @return The current budget period number
    """
    return self._period()

@external
def deposit(_token: address, _amount: uint256) -> (uint256, uint256):
    """
    @notice Deposit revenue
    @param _token Token address
    @param _amount Token amount
    @return Tuple with: current budget period number, USD value of revenue (18 decimals)
    @dev Can only be called by a registered team
    @dev Only accepts tokens that are whitelisted by having a price oracle assigned
    """
    assert staticcall self.registry.is_team(msg.sender)
    assert not self.killed

    oracle: address = self.oracles[_token]
    assert oracle != empty(address)
    price: uint256 = extcall IOracle(oracle).price(_token)
    assert price > 0

    assert extcall IERC20(_token).transferFrom(msg.sender, self, _amount, default_return_value=True)
    converter: address = self.converters[_token]
    if converter != empty(address):
        assert extcall IERC20(_token).approve(converter, _amount, default_return_value=True)
        extcall IConverter(converter).convert(_token, _amount)

    period: uint256 = self._period()
    value: uint256 = _amount * price // PRECISION
    extcall self.accountant.adjust_revenue(msg.sender, period, value, INCREMENT)

    log DepositRevenue(team=msg.sender, period=period, token=_token, amount=_amount, revenue=value)
    return period, value

@external
def convert(_token: address, _amount: uint256):
    """
    @notice Convert a token
    @param _token Token address
    @param _amount Token amount
    @dev Can only be called by the operator
    @dev Only accepts tokens that are whitelisted by having a converter assigned
    """
    assert msg.sender == self.operator
    assert not self.killed
    converter: address = self.converters[_token]
    assert converter != empty(address)
    assert extcall IERC20(_token).approve(converter, _amount, default_return_value=True)
    extcall IConverter(converter).convert(_token, _amount)
    log ConvertToken(token=_token, converter=converter, amount=_amount)

@external
def to_styfi_rewards(_epoch: uint256, _amount: uint256):
    """
    @notice Queue the rewards token for future distribution to stYFI
    @param _epoch Epoch number to queue rewards for
    @param _amount Token amount
    @dev Can only be called by the operator
    """
    assert msg.sender == self.operator

    self._use_balance(0, _amount)
    distributor: IRewardDistributor = self.reward_distributor
    assert staticcall distributor.token() == token.address
    assert extcall token.approve(distributor.address, _amount, default_return_value=True)
    extcall distributor.deposit(_epoch, _amount)
    log ToRewards(epoch=_epoch, amount=_amount)

@external
def to_treasury(_amount: uint256):
    """
    @notice Send tokens to treasury
    @param _amount Token amount
    @dev Can only be called by the operator
    """
    assert msg.sender == self.operator

    self._use_balance(1, _amount)
    assert extcall token.transfer(self.treasury, _amount, default_return_value=True)
    log ToTreasury(amount=_amount)

@external
def to_yeth_recovery(_amount: uint256):
    """
    @notice Auction token for yETH recovery
    @param _amount Token amount
    @dev Can only be called by the operator
    """
    assert msg.sender == self.operator

    self._use_balance(2, _amount)

    # check token is enabled inside the auction
    auction: IAuction = self.recovery_auction
    kicked: uint64 = 0
    scaler: uint64 = 0
    available: uint128 = 0
    kicked, scaler, available = staticcall auction.auctions(token.address)
    assert scaler > 0
    assert block.timestamp >= convert(kicked, uint256) + AUCTION_LENGTH

    assert extcall token.transfer(auction.address, _amount, default_return_value=True)
    extcall auction.kick(token.address)
    log ToRecovery(amount=_amount)

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

    if _token == token.address:
        assert self.killed

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def kill():
    """
    @notice Kill the revenue recipient, making it unable to accept or redistribute revenue
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.killed = True
    log Kill()

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
def set_registry(_registry: address):
    """
    @notice Set a new registry
    @param _registry New registry address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.registry = IRegistry(_registry)
    log SetRegistry(registry=_registry)

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
def set_treasury(_treasury: address):
    """
    @notice Set a new treasury
    @param _treasury New treasury address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.treasury = _treasury
    log SetTreasury(treasury=_treasury)

@external
def set_reward_distributor(_distributor: address):
    """
    @notice Set a new stYFI reward distributor
    @param _distributor New stYFI reward distributor address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.reward_distributor = IRewardDistributor(_distributor)
    log SetRewardDistributor(distributor=_distributor)

@external
def set_recovery_auction(_auction: address):
    """
    @notice Set a yETH recovery auction
    @param _auction New yETH recovery auction address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.recovery_auction = IAuction(_auction)
    log SetRecoveryAuction(auction=_auction)

@external
def set_price_oracle(_token: address, _oracle: address):
    """
    @notice Set a token price oracle
    @param _token Token address
    @param _oracle Oracle address
    @dev The oracle should return the value of 1 wad of tokens in USD (18 decimals)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _token != empty(address)
    if _oracle != empty(address):
        assert extcall IOracle(_oracle).price(_token) > 0

    self.oracles[_token] = _oracle
    log SetPriceOracle(token=_token, oracle=_oracle)

@external
def set_token_converter(_token: address, _converter: address):
    """
    @notice Set a token converter
    @param _token Token address
    @param _converter Converter address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.converters[_token] = _converter
    log SetTokenConverter(token=_token, converter=_converter)

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

@internal
def _use_balance(_i: uint256, _amount: uint256):
    assert not self.killed
    current: uint256 = staticcall token.balanceOf(self)
    increase: uint256 = current - self.last_balance
    self.last_balance = current
    sum_balance: uint256 = self.sum_balance + increase
    self.sum_balance = sum_balance

    budget: uint256 = sum_balance * token_split[_i] // BPS_PRECISION
    used: uint256 = self.used[_i] + _amount
    assert used <= budget

    self.last_balance -= _amount
    self.used[_i] = used

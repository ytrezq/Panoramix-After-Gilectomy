# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Funding Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice Maintains a list of approved funding and distributes the funding to the team upon request. 
        Funding is either sent directly or in a vesting contract, depending on the duration specified
        in the approval as well as the time of claim.
        Supports returning of unused funding, which reduces the team's cost by the average price of 
        the tokens during all the claims.
"""

from ethereum.ercs import IERC20

struct Approval:
    team: address
    period: uint256
    token: address
    amount: uint256
    duration: uint256
    used: uint256

struct Cost:
    amount: uint256
    price: uint256

interface IFundingDistributor:
    def token(_idx: uint256) -> address: view
    def claimable(_idx: uint256) -> uint256: view
    def claim(_idx: uint256, _amount: uint256, _recipient: address) -> (uint256, uint256, address): nonpayable
    def refund(_idx: uint256, _amount: uint256) -> (uint256, uint256): nonpayable
implements: IFundingDistributor

interface IRegistry:
    def is_team(_team: address) -> bool: view

interface IAccountant:
    def adjust_cost(_team: address, _period: uint256, _amount: uint256, _increment: bool): nonpayable

interface IOracle:
    def price(_asset: address) -> uint256: nonpayable

interface IVestingFactory:
    def deploy_vesting_contract(
        _token: address, _recipient: address, _amount: uint256, _duration: uint256, _start: uint256, 
        _cliff: uint256, _open: bool, _donation: uint256, _owner: address
    ) -> address: nonpayable

genesis: public(immutable(uint256))
management: public(address)
pending_management: public(address)
registry: public(IRegistry)
accountant: public(IAccountant)
vesting_factory: public(IVestingFactory)
vesting_owner: public(address)
oracles: public(HashMap[address, address])
num_approvals: public(uint256)
approvals: public(HashMap[uint256, Approval])
costs: public(HashMap[address, HashMap[uint256, HashMap[address, Cost]]]) # team => period => token => cost

event ApproveFunding:
    idx: indexed(uint256)
    team: indexed(address)
    period: indexed(uint256)
    token: address
    amount: uint256
    duration: uint256

event ClaimFunding:
    idx: indexed(uint256)
    team: indexed(address)
    period: indexed(uint256)
    token: address
    amount: uint256
    cost: uint256
    vest: address
    recipient: address

event ReturnFunding:
    idx: indexed(uint256)
    team: indexed(address)
    period: indexed(uint256)
    token: address
    amount: uint256
    refund: uint256
    sender: address

event SetRegistry:
    registry: indexed(address)

event SetAccountant:
    accountant: indexed(address)

event SetVestingFactory:
    factory: indexed(address)

event SetVestingOwner:
    owner: indexed(address)

event SetPriceOracle:
    token: indexed(address)
    oracle: address

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

PRECISION: constant(uint256) = 10**18
PERIOD_LENGTH: constant(uint256) = 6 * 14 * 24 * 60 * 60
INCREMENT: constant(bool) = True
DECREMENT: constant(bool) = False

@deploy
def __init__(_genesis: uint256):
    """
    @notice Constructor
    @param _genesis Budget period genesis timestamp
    """
    genesis = _genesis
    self.management = msg.sender
    self.vesting_owner = msg.sender

@external
@view
def period() -> uint256:
    """
    @notice Query the current budget period number
    @return The current budget period number
    """
    return self._period()

@external
@view
def token(_idx: uint256) -> address:
    """
    @notice Query the token associated with a specific approval
    @param _idx Approval index
    @return The token address
    """
    token: address = self.approvals[_idx].token
    assert token != empty(address)
    return token

@external
def approve(_team: address, _period: uint256, _token: address, _amount: uint256, _duration: uint256) -> uint256:
    """
    @notice Approve funding
    @param _team Team address
    @param _period Budget period number. Cant be in the past
    @param _token Token address
    @param _amount Token amount
    @param _duration Vest duration from start of the budget period
    @return Approval index
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _team != empty(address)
    assert _period >= self._period()
    assert _token != empty(address)
    assert _amount > 0

    oracle: address = self.oracles[_token]
    assert oracle != empty(address)
    price: uint256 = extcall IOracle(oracle).price(_token)
    assert price > 0

    idx: uint256 = self.num_approvals
    self.num_approvals = idx + 1
    self.approvals[idx] = Approval(team=_team, period=_period, token=_token, amount=_amount, duration=_duration, used=0)

    log ApproveFunding(idx=idx, team=_team, period=_period, token=_token, amount=_amount, duration=_duration)
    return idx

@external
@view
def claimable(_idx: uint256) -> uint256:
    team: address = self.approvals[_idx].team
    if not staticcall self.registry.is_team(team):
        return 0

    period: uint256 = self._period()
    if period != self.approvals[_idx].period:
        return 0

    return self.approvals[_idx].amount - self.approvals[_idx].used

@external
def claim(_idx: uint256, _amount: uint256, _recipient: address) -> (uint256, uint256, address):
    """
    @notice Claim funding
    @param _idx Approval index
    @param _amount Token amount
    @param _recipient Funding recipient
    @return Tuple with: current budget period number, USD value of claim (18 decimals), vesting contract (if applicable)
    @dev Can only be called by the team associated with the approval
    """
    assert msg.sender == self.approvals[_idx].team
    assert staticcall self.registry.is_team(msg.sender)
    assert _amount > 0
    assert _recipient != empty(address)

    period: uint256 = self._period()
    assert period == self.approvals[_idx].period

    # update approval usage
    used: uint256 = self.approvals[_idx].used + _amount
    assert used <= self.approvals[_idx].amount
    self.approvals[_idx].used = used

    # get price from oracle
    token: address = self.approvals[_idx].token
    oracle: address = self.oracles[token]
    assert oracle != empty(address)
    price: uint256 = extcall IOracle(oracle).price(token)
    assert price > 0

    # update cost and average price
    cost: Cost = self.costs[msg.sender][period][token]
    new_cost: uint256 = cost.amount + _amount
    cost.price = (cost.amount * cost.price + _amount * price) // new_cost
    cost.amount = new_cost
    self.costs[msg.sender][period][token] = cost

    # report to accountant
    value: uint256 = _amount * price // PRECISION
    extcall self.accountant.adjust_cost(msg.sender, period, value, INCREMENT)

    duration: uint256 = self.approvals[_idx].duration
    start: uint256 = genesis + period * PERIOD_LENGTH
    vest: address = empty(address)
    if block.timestamp >= start + duration:
        # tokens unlock immediately
        assert extcall IERC20(token).transfer(_recipient, _amount, default_return_value=True)
    else:
        # tokens vest over time
        factory: IVestingFactory = self.vesting_factory
        assert extcall IERC20(token).approve(factory.address, _amount, default_return_value=True)
        vest = extcall factory.deploy_vesting_contract(token, _recipient, _amount, duration, start, 0, True, 0, self.vesting_owner)

    log ClaimFunding(idx=_idx, team=msg.sender, period=period, token=token, amount=_amount, cost=value, vest=vest, recipient=_recipient)
    return (period, value, vest)

@external
def refund(_idx: uint256, _amount: uint256) -> (uint256, uint256):
    """
    @notice Refund previously claimed funding
    @param _idx Approval index
    @param _amount Token amount
    @return Tuple with: current budget period number, USD value of refund (18 decimals)
    @dev Reduces the team's cost using the average price of all claims in this approval
    """
    assert msg.sender == self.approvals[_idx].team
    period: uint256 = self._period()
    assert period == self.approvals[_idx].period

    # update cost
    token: address = self.approvals[_idx].token
    cost: Cost = self.costs[msg.sender][period][token]
    self.costs[msg.sender][period][token].amount = cost.amount - _amount

    # report to accountant using the average price
    value: uint256 = _amount * cost.price // PRECISION
    extcall self.accountant.adjust_cost(msg.sender, period, value, DECREMENT)

    assert extcall IERC20(token).transferFrom(msg.sender, self, _amount, default_return_value=True)

    log ReturnFunding(idx=_idx, team=msg.sender, period=period, token=token, amount=_amount, refund=value, sender=msg.sender)
    return (period, value)

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
def set_vesting_factory(_factory: address):
    """
    @notice Set a new vesting factory
    @param _factory New vesting factory address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.vesting_factory = IVestingFactory(_factory)
    log SetVestingFactory(factory=_factory)

@external
def set_vesting_owner(_owner: address):
    """
    @notice Set a new vesting owner
    @param _owner New vesting owner address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.vesting_owner = _owner
    log SetVestingOwner(owner=_owner)

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

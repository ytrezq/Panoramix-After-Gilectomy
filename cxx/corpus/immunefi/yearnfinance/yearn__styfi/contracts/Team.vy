# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Team
@author Yearn Finance
@license GNU AGPLv3
@notice Implementation contract for proxies deployed by the team registry. Used to deposit
        revenue and claim funding by the owner.
"""

from ethereum.ercs import IERC20

interface ITeam:
    def migrate(_registry: address): nonpayable
implements: ITeam

interface IRegistry:
    def revenue_recipient() -> address: view
    def funding_distributor() -> address: view

interface IRevenueRecipient:
    def deposit(_token: address, _amount: uint256) -> (uint256, uint256): nonpayable

interface IFundingDistributor:
    def token(_idx: uint256) -> address: view
    def claimable(_idx: uint256) -> uint256: view
    def claim(_idx: uint256, _amount: uint256, _recipient: address) -> (uint256, uint256, address): nonpayable
    def refund(_idx: uint256, _amount: uint256) -> (uint256, uint256): nonpayable

name: public(String[100])
registry: public(IRegistry)
owner: public(address)
pending_owner: public(address)

event DepositRevenue:
    period: indexed(uint256)
    token: address
    amount: uint256
    revenue: uint256
    depositor: address

event ClaimFunding:
    idx: indexed(uint256)
    period: indexed(uint256)
    token: address
    amount: uint256
    cost: uint256
    vest: address
    recipient: address

event ReturnFunding:
    idx: indexed(uint256)
    period: indexed(uint256)
    token: address
    amount: uint256
    refund: uint256
    sender: address

event PendingOwner:
    owner: indexed(address)

event SetOwner:
    owner: indexed(address)

event Migrate:
    registry: indexed(address)

@deploy
def __init__():
    """
    @notice Constructor
    """
    self.registry = IRegistry(0x1111111111111111111111111111111111111111)

@external
def setup(_name: String[100], _owner: address):
    """
    @notice Set up team parameters
    @param _name Team name
    @param _owner Owner address
    """
    assert self.registry.address == empty(address)
    self.name = _name
    self.registry = IRegistry(msg.sender)
    self.owner = _owner

@external
def deposit_revenue(_token: address, _amount: uint256) -> uint256:
    """
    @notice Deposit earned revenue
    @param _token Token address
    @param _amount Token amount
    @return USD value of revenue (18 decimals)
    """
    recipient: address = staticcall self.registry.revenue_recipient()
    assert extcall IERC20(_token).transferFrom(msg.sender, self, _amount, default_return_value=True)
    assert extcall IERC20(_token).approve(recipient, _amount, default_return_value=True)
    period: uint256 = 0
    revenue: uint256 = 0
    period, revenue = extcall IRevenueRecipient(recipient).deposit(_token, _amount)

    log DepositRevenue(period=period, token=_token, amount=_amount, revenue=revenue, depositor=msg.sender)
    return revenue

@external
def claim_funding(_idx: uint256, _amount: uint256 = max_value(uint256), _recipient: address = msg.sender) -> (address, uint256, address):
    """
    @notice Claim funding
    @param _idx Approval index
    @param _amount Token amount. Defaults to all available
    @param _recipient Receiver of the funding
    @return Tuple with: token address, USD value of funding (18 decimals), vesting contract (if applicable)
    """
    assert msg.sender == self.owner

    distributor: address = staticcall self.registry.funding_distributor()
    token: address = staticcall IFundingDistributor(distributor).token(_idx)

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IFundingDistributor(distributor).claimable(_idx)

    period: uint256 = 0
    cost: uint256 = 0
    vest: address = empty(address)
    period, cost, vest = extcall IFundingDistributor(distributor).claim(_idx, amount, _recipient)

    log ClaimFunding(idx=_idx, period=period, token=token, amount=amount, cost=cost, vest=vest, recipient=_recipient)
    return token, cost, vest

@external
def return_funding(_idx: uint256, _amount: uint256) -> (address, uint256):
    """
    @notice Return previously claimed funding
    @param _idx Approval index
    @param _amount Token amount
    @return Tuple with: token address, USD value of refund (18 decimals)
    """
    assert _amount > 0

    distributor: address = staticcall self.registry.funding_distributor()
    token: address = staticcall IFundingDistributor(distributor).token(_idx)

    assert extcall IERC20(token).transferFrom(msg.sender, self, _amount, default_return_value=True)
    assert extcall IERC20(token).approve(distributor, _amount, default_return_value=True)

    period: uint256 = 0
    refund: uint256 = 0
    period, refund = extcall IFundingDistributor(distributor).refund(_idx, _amount)

    log ReturnFunding(idx=_idx, period=period, token=token, amount=_amount, refund=refund, sender=msg.sender)
    return token, refund

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    """
    @notice Transfer out a token
    @param _token The token address
    @param _amount The amount of tokens. Defaults to all
    @dev Can only be called by the owner
    """
    assert msg.sender == self.owner

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC20(_token).balanceOf(self)

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_owner(_owner: address):
    """
    @notice Set the pending owner address.
            Needs to be accepted by that account separately to transfer ownership over
    @param _owner New pending owner address
    """
    assert msg.sender == self.owner

    self.pending_owner = _owner
    log PendingOwner(owner=_owner)

@external
def accept_owner():
    """
    @notice Accept ownership role.
            Can only be called by account previously marked as pending by current owner
    """
    assert msg.sender == self.pending_owner

    self.pending_owner = empty(address)
    self.owner = msg.sender
    log SetOwner(owner=msg.sender)

@external
def migrate(_registry: address):
    """
    @notice Migrate to a new registry
    @param _registry New registry address
    @dev Can only be called by the current registry
    """
    assert msg.sender == self.registry.address
    assert _registry != empty(address)

    self.registry = IRegistry(_registry)
    log Migrate(registry=_registry)

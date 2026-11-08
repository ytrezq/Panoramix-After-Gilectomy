# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Team Accountant
@author Yearn Finance
@license GNU AGPLv3
@notice Tracks the revenues and costs of each team, both per period as well as aggregated over
        the teams' lifetimes. Also tracks global per-period and lifetime revenues and costs.
"""

interface IAccountant:
    def global_revenues(_period: uint256) -> uint256: view
    def team_profits(_team: address, _period: uint256) -> uint256: view
    def adjust_revenue(_team: address, _period: uint256, _amount: uint256, _increment: bool): nonpayable
    def adjust_cost(_team: address, _period: uint256, _amount: uint256, _increment: bool): nonpayable
implements: IAccountant

management: public(address)
pending_management: public(address)
operators: public(HashMap[address, bool])

global_revenues: public(HashMap[uint256, uint256]) # period => revenue
global_costs: public(HashMap[uint256, uint256]) # period => cost
lifetime_global_revenues: public(uint256)
lifetime_global_costs: public(uint256)

team_revenues: public(HashMap[address, HashMap[uint256, uint256]]) # team => period => revenue
team_costs: public(HashMap[address, HashMap[uint256, uint256]]) # team => period => cost
lifetime_team_revenues: public(HashMap[address, uint256]) # team => revenue
lifetime_team_costs: public(HashMap[address, uint256]) # team => costs

event AdjustRevenue:
    operator: indexed(address)
    team: indexed(address)
    period: indexed(uint256)
    amount: uint256
    increment: bool

event AdjustCost:
    operator: indexed(address)
    team: indexed(address)
    period: indexed(uint256)
    amount: uint256
    increment: bool

event SetOperator:
    operator: indexed(address)
    flag: bool

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

INCREMENT: constant(bool) = True

@deploy
def __init__():
    """
    @notice Constructor
    """
    self.management = msg.sender

@external
@view
def global_profits(_period: uint256) -> uint256:
    """
    @notice Query the global profits for a specific budget period
    @param _period Budget period number
    @return Global profits in this specific period
    """
    revenue: uint256 = self.global_revenues[_period]
    cost: uint256 = self.global_costs[_period]
    if cost >= revenue:
        return 0
    return revenue - cost

@external
@view
def global_losses(_period: uint256) -> uint256:
    """
    @notice Query the global losses for a specific budget period
    @param _period Budget period number
    @return Global losses in this specific period
    """
    revenue: uint256 = self.global_revenues[_period]
    cost: uint256 = self.global_costs[_period]
    if revenue >= cost:
        return 0
    return cost - revenue

@external
@view
def lifetime_global_profits() -> uint256:
    """
    @notice Query the lifetime global profits
    @return Global profits
    """
    revenue: uint256 = self.lifetime_global_revenues
    cost: uint256 = self.lifetime_global_costs
    if cost >= revenue:
        return 0
    return revenue - cost

@external
@view
def lifetime_global_losses() -> uint256:
    """
    @notice Query the lifetime global losses
    @return Global losses
    """
    revenue: uint256 = self.lifetime_global_revenues
    cost: uint256 = self.lifetime_global_costs
    if revenue >= cost:
        return 0
    return cost - revenue

@external
@view
def team_profits(_team: address, _period: uint256) -> uint256:
    """
    @notice Query the profits of a team for a specific budget period
    @param _team Team address
    @param _period Budget period number
    @return Profits in this specific period by this specific team
    """
    revenue: uint256 = self.team_revenues[_team][_period]
    cost: uint256 = self.team_costs[_team][_period]
    if cost >= revenue:
        return 0
    return revenue - cost

@external
@view
def team_losses(_team: address, _period: uint256) -> uint256:
    """
    @notice Query the losses of a team for a specific budget period
    @param _team Team address
    @param _period Budget period number
    @return Lossses in this specific period by this specific team
    """
    revenue: uint256 = self.team_revenues[_team][_period]
    cost: uint256 = self.team_costs[_team][_period]
    if revenue >= cost:
        return 0
    return cost - revenue

@external
@view
def lifetime_team_profits(_team: address) -> uint256:
    """
    @notice Query the lifetime profits of a team
    @param _team Team address
    @return Lifetime profits by this specific team
    """
    revenue: uint256 = self.lifetime_team_revenues[_team]
    cost: uint256 = self.lifetime_team_costs[_team]
    if cost >= revenue:
        return 0
    return revenue - cost

@external
@view
def lifetime_team_losses(_team: address) -> uint256:
    """
    @notice Query the lifetime losses of a team
    @param _team Team address
    @return Lifetime losses by this specific team
    """
    revenue: uint256 = self.lifetime_team_revenues[_team]
    cost: uint256 = self.lifetime_team_costs[_team]
    if revenue >= cost:
        return 0
    return cost - revenue

@external
def adjust_revenue(_team: address, _period: uint256, _amount: uint256, _increment: bool):
    """
    @notice Adjust revenue upwards or downwards
    @param _team Team address
    @param _period Budget period number
    @param _amount USD amount to adjust revenue by (18 decimals)
    @param _increment True: increment revenue, False: decrement revenue
    @dev Can only be called by an operator
    """
    assert self.operators[msg.sender]

    if _increment == INCREMENT:
        self.global_revenues[_period] += _amount
        self.lifetime_global_revenues += _amount

        self.team_revenues[_team][_period] += _amount
        self.lifetime_team_revenues[_team] += _amount
    else:
        self.global_revenues[_period] -= _amount
        self.lifetime_global_revenues -= _amount

        self.team_revenues[_team][_period] -= _amount
        self.lifetime_team_revenues[_team] -= _amount

    log AdjustRevenue(operator=msg.sender, team=_team, period=_period, amount=_amount, increment=_increment)

@external
def adjust_cost(_team: address, _period: uint256, _amount: uint256, _increment: bool):
    """
    @notice Adjust cost upwards or downwards
    @param _team Team address
    @param _period Budget period number
    @param _amount USD amount to adjust cost by (18 decimals)
    @param _increment True: increment cost, False: decrement cost
    @dev Can only be called by an operator
    """
    assert self.operators[msg.sender]

    if _increment == INCREMENT:
        self.global_costs[_period] += _amount
        self.lifetime_global_costs += _amount

        self.team_costs[_team][_period] += _amount
        self.lifetime_team_costs[_team] += _amount
    else:
        self.global_costs[_period] -= _amount
        self.lifetime_global_costs -= _amount

        self.team_costs[_team][_period] -= _amount
        self.lifetime_team_costs[_team] -= _amount

    log AdjustCost(operator=msg.sender, team=_team, period=_period, amount=_amount, increment=_increment)

@external
def set_operator(_operator: address, _flag: bool):
    """
    @notice Set an operator, allowing them to adjust revenues and costs
    @param _operator Operator address
    @param _flag True: add as operator, False: remove as operator
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.operators[_operator] = _flag
    log SetOperator(operator=_operator, flag=_flag)

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

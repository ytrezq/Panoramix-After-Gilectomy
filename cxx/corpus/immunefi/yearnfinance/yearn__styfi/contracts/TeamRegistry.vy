# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Team Registry
@author Yearn Finance
@license GNU AGPLv3
@notice Maintains the canonical list of teams. Inactive teams can be retired,
        which means they will no longer be considered registered in the following epoch.
        The registry also stores the official deployments for the revenue recipient and funding 
        distributor, which are used be each of the teams to submit revenue and claim funding.
"""

from ethereum.ercs import IERC20

interface IRegistry:
    def num_teams() -> uint256: view
    def teams(_idx: uint256) -> address: view
    def is_team(_team: address) -> bool: view
    def revenue_recipient() -> address: view
    def funding_distributor() -> address: view
implements: IRegistry

interface ITeam:
    def setup(_name: String[100], _owner: address): nonpayable
    def migrate(_registry: address): nonpayable

genesis: public(immutable(uint256))
management: public(address)
pending_management: public(address)
successor: public(address)
implementation: public(address)
revenue_recipient: public(address)
funding_distributor: public(address)

num_teams: public(uint256)
teams: public(HashMap[uint256, address])
team_retirements: public(HashMap[address, uint256])

event AddTeam:
    idx: indexed(uint256)
    team: indexed(address)

event RetireTeam:
    team: indexed(address)
    period: uint256

event Deprecate:
    successor: indexed(address)

event MigrateTeam:
    team: indexed(address)

event SetImplementation:
    implementation: indexed(address)

event SetRevenueRecipient:
    recipient: indexed(address)

event SetFundingDistributor:
    distributor: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

PERIOD_LENGTH: constant(uint256) = 6 * 14 * 24 * 60 * 60

@deploy
def __init__(_genesis: uint256):
    """
    @notice Constructor
    @param _genesis Budget period genesis timestamp
    """
    genesis = _genesis
    self.management = msg.sender

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
def is_team(_team: address) -> bool:
    """
    @notice Query whether an address is a registered team
    @param _team Adress to query status for
    @return True: address is a registered team, False: address is not a team
    @dev Retired teams are not considered registered
    """
    return self.team_retirements[_team] > self._period()

@external
def add_team(_name: String[100], _owner: address) -> (uint256, address):
    """
    @notice Deploy a team and add it to the registry
    @param _name Team name. Must be unique
    @param _owner Team owner address
    @return Tuple of team index and team contract address
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert len(_name) > 0
    team: address = create_minimal_proxy_to(self.implementation, salt=keccak256(_name))
    assert self.team_retirements[team] == 0
    extcall ITeam(team).setup(_name, _owner)

    idx: uint256 = self.num_teams
    self.num_teams = idx + 1
    self.teams[idx] = team
    self.team_retirements[team] = max_value(uint256)

    log AddTeam(idx=idx, team=team)
    return (idx, team)

@external
def retire_team(_team: address):
    """
    @notice Mark a team for retirement next epoch
    @param _team Team adress
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    period: uint256 = self._period() + 1
    assert self.team_retirements[_team] > period

    self.team_retirements[_team] = period
    log RetireTeam(team=_team, period=period)

@external
def migrate_team(_team: address):
    """
    @notice Migrate a team to the new registry
    @param _team Team adress
    @dev Can only be called once this registry is deprecated
    """
    successor: address = self.successor
    assert successor != empty(address)
    assert self.team_retirements[_team] > self._period() + 1

    extcall ITeam(_team).migrate(successor)
    log MigrateTeam(team=_team)

@external
def deprecate(_successor: address):
    """
    @notice Deprecate this registry and appoint a successor
    @param _successor The new registry
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _successor != empty(address)
    assert self.successor == empty(address)

    self.successor = _successor
    log Deprecate(successor=_successor)

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
def set_implementation(_implementation: address):
    """
    @notice Set the team implementation contract. Only affects new deployments
    @param _implementation Team implementation address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.implementation = _implementation
    log SetImplementation(implementation=_implementation)

@external
def set_revenue_recipient(_recipient: address):
    """
    @notice Set the revenue recipient
    @param _recipient Revenue recipient address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.revenue_recipient = _recipient
    log SetRevenueRecipient(recipient=_recipient)

@external
def set_funding_distributor(_distributor: address):
    """
    @notice Set the funding distributor
    @param _distributor Funding distributor address
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.funding_distributor = _distributor
    log SetFundingDistributor(distributor=_distributor)

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

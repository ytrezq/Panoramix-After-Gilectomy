# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Reward Claimer
@author Yearn Finance
@license GNU AGPLv3
@notice User-facing contract to claim all rewards from all components at once.
"""

from ethereum.ercs import IERC20

interface IComponent:
    def claim(_account: address) -> uint256: nonpayable

token: public(immutable(IERC20))
management: public(address)
pending_management: public(address)
num_components: public(uint256)
components: public(HashMap[uint256, address])

event Claim:
    account: indexed(address)
    rewards: uint256

event AddComponent:
    component: indexed(address)

event ReplaceComponent:
    idx: uint256
    component: indexed(address)

event RemoveComponent:
    component: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

MAX_NUM_COMPONENTS: constant(uint256) = 32

@deploy
def __init__(_token: address):
    """
    @notice Constructor
    @param _token Reward token address
    """
    token = IERC20(_token)
    self.management = msg.sender

@external
def claim(_recipient: address = msg.sender) -> uint256:
    """
    @notice Claim rewards from all components
    @param _recipient Optional recipient of rewards. Defaults to caller
    @return Total amount of rewards claimed
    """
    amount: uint256 = 0
    for i: uint256 in range(self.num_components, bound=MAX_NUM_COMPONENTS):
        amount += extcall IComponent(self.components[i]).claim(msg.sender)

    if amount > 0:
        assert extcall token.transfer(_recipient, amount, default_return_value=True)
        log Claim(account=msg.sender, rewards=amount)

    return amount

@external
def add_component(_component: address):
    """
    @notice Add a component
    @param _component Component address
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _component != empty(address)
    num: uint256 = self.num_components
    assert num < MAX_NUM_COMPONENTS

    self.num_components = num + 1
    self.components[num] = _component
    log AddComponent(component=_component)

@external
def replace_component(_idx: uint256, _component: address):
    """
    @notice Replace a component
    @param _idx Index of the component to replace
    @param _component Component address
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _idx < self.num_components
    assert _component != empty(address)

    self.components[_idx] = _component
    log ReplaceComponent(idx=_idx, component=_component)

@external
def remove_component():
    """
    @notice Remove the last component
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    num: uint256 = self.num_components - 1
    self.num_components = num
    component: address = self.components[num]
    self.components[num] = empty(address)
    log RemoveComponent(component=component)

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
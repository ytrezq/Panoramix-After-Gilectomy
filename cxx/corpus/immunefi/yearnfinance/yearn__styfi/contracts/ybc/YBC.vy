# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Yearn Builder Collective
@author Yearn Finance
@license GNU AGPLv3
@notice Maintains the list of users participating in the Yearn Builder Collective.
        Intended to hold stYFI on behalf of the collective.
        Outside contracts can be added as operator to this contract, allowing modular 
        functionality such as member addition/removal, voting and yield redistribution.
"""

interface IMemberHooks:
    def on_add_member(_account: address): nonpayable
    def on_remove_member(_account: address): nonpayable

management: public(address)
pending_management: public(address)
num_members: public(uint256)
members: public(HashMap[address, bool])
hooks: public(IMemberHooks)
operators: public(HashMap[address, bool])

event AddMember:
    member: indexed(address)

event RemoveMember:
    member: indexed(address)

event Call:
    operator: indexed(address)
    target: indexed(address)
    data: Bytes[2048]

event SetHooks:
    hooks: indexed(address)

event SetOperator:
    operator: indexed(address)
    flag: bool

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

@deploy
def __init__():
    """
    @notice Constructor
    """
    self.management = msg.sender

@external
def add_member(_account: address):
    """
    @notice Add a member to the YBC
    @param _account Member to add
    @dev Can only be called by an operator through the `call` function
    """
    assert msg.sender == self
    assert _account not in [empty(address), self]
    assert not self.members[_account]

    self.num_members += 1
    self.members[_account] = True
    if self.hooks.address != empty(address):
        extcall self.hooks.on_add_member(_account)
    log AddMember(member=_account)

@external
def remove_member(_account: address):
    """
    @notice Remove a member from the YBC
    @param _account Member to remove
    @dev Can only be called by an operator through the `call` function
    """
    assert msg.sender == self
    assert self.members[_account]

    self.num_members -= 1
    self.members[_account] = False
    if self.hooks.address != empty(address):
        extcall self.hooks.on_remove_member(_account)
    log RemoveMember(member=_account)

@external
def call(_target: address, _data: Bytes[2048]) -> Bytes[1024]:
    """
    @notice Call a function on behalf of the YBC
    @param _target Contract to call
    @param _data Calldata
    @dev Can only be called by an operator
    """
    assert self.operators[msg.sender]

    log Call(operator=msg.sender, target=_target, data=_data)
    return raw_call(_target, _data, max_outsize=1024)

@external
def set_hooks(_hooks: address):
    """
    @notice Set the hook contract for member additions/removals
    @param _hooks Hooks address. Can be zero for no hook
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.hooks = IMemberHooks(_hooks)
    log SetHooks(hooks=_hooks)

@external
def set_operator(_operator: address, _flag: bool):
    """
    @notice Set the operator status of an address
    @param _operator Address to set operator status for
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

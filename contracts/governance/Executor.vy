# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Executor
@author Yearn Finance
@license GNU AGPLv3
@notice Allows operators to execute one or more calls atomically. Intended to hold
        privileged roles inside the protocol, which will allow for hotswapping of 
        governance operators at any time by management without the need to move each 
        role individually.
"""

management: public(address)
pending_management: public(address)
operators: public(HashMap[address, bool])

event Execute:
    operator: indexed(address)
    target: indexed(address)
    data: Bytes[2048]

event SetOperator:
    operator: indexed(address)
    flag: bool

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

MAX_NUM_CALLS: constant(uint256) = 64
SIZE_MASK: constant(uint256) = (1 << 96) - 1

@deploy
def __init__():
    """
    @notice Constructor
    """
    self.management = msg.sender

@external
def execute(_script: Bytes[2048]):
    """
    @notice Execute a single script consisting of up to 64 calls
    @param _script Script to execute
    @dev Can only be called by an operator
    """
    assert self.operators[msg.sender]

    offset: uint256 = 0
    for i: uint256 in range(MAX_NUM_CALLS):
        if offset == len(_script):
            break
        assert offset + 32 <= len(_script)

        # extract target and calldata size
        header: uint256 = extract32(_script, offset, output_type=uint256) # address (160) | calldata size (96)
        offset += 32

        size: uint256 = header & SIZE_MASK
        target: address = convert(header >> 96, address)
        
        data: Bytes[2048] = slice(_script, offset, size)
        offset += size

        raw_call(target, data)
        log Execute(operator=msg.sender, target=target, data=data)

    assert offset == len(_script)

@external
@pure
def script(_to: address, _data: Bytes[2016]) -> Bytes[2048]:
    """
    @notice Generate script for a single call.
            Calls can be chained by concatenating their scripts
    @param _to The contract to call
    @param _data Calldata
    """
    prefix: uint256 = (convert(_to, uint256) << 96) | len(_data)
    return concat(convert(prefix, bytes32), _data)

@external
def set_operator(_operator: address, _flag: bool):
    """
    @notice Add or remove an operator
    @param _operator Operator
    @param _flag True: operator, False: not operator
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _operator != empty(address)

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

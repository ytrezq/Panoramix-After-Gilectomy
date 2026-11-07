# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Vesting Staker (Cove)
@author Yearn Finance
@license GNU AGPLv3
@notice Allows the vest recipient to stake their tokens into llYFI to earn rewards and 
        participate in governance while their tokens are vesting. Tokens can also be unstaked 
        and sent back to the vesting contract.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

interface IVest:
    def recipient() -> address: view
    def token() -> address: view
    def factory() -> address: view
    def end_time() -> uint256: view
    def call(_target: address, _data: Bytes[2048]): payable

interface IDepositor:
    def unstake(_amount: uint256): nonpayable

interface IFactory:
    def operators(_vest: address, _operator: address) -> bool: view

interface IRewardClaimer:
    def claim(_recipient: address) -> uint256: nonpayable

event Stake:
    amount: uint256

event Unstake:
    amount: uint256

event ClaimStream:
    amount: uint256

event ClaimRewards:
    receiver: address
    amount: uint256

event SetOperator:
    operator: indexed(address)
    flag: bool

event Call:
    operator: address
    target: address

vest: public(immutable(IVest))
recipient: public(immutable(address))
gauge: public(immutable(IERC4626))
token: public(immutable(IERC20))
factory: public(immutable(IFactory))
end_time: public(immutable(uint256))
operators: public(HashMap[address, bool])

DEPOSITOR: public(constant(address)) = 0x3d4Ced97ADb0ae3A53DA95a47fFc749aAd26BC8f
REWARD_CLAIMER: public(constant(IRewardClaimer)) = IRewardClaimer(0xA82454009E01Ae697012a73cB232d85e61B05e50)

@deploy
def __init__(_vest: address):
    """
    @notice Constructor
    @param _vest Address of the vest
    """
    vest = IVest(_vest)
    recipient = staticcall vest.recipient()
    gauge = IERC4626(staticcall vest.token())
    token = IERC20(staticcall gauge.asset())
    factory = IFactory(staticcall vest.factory())
    end_time = staticcall vest.end_time()

    assert staticcall IERC4626(DEPOSITOR).asset() == token.address

@external
def stake(_amount: uint256):
    """
    @notice Stake into llYFI
    @param _amount Amount of YFI to stake
    """
    assert msg.sender == recipient
    
    extcall vest.call(gauge.address, abi_encode(_amount, self, vest.address, method_id=method_id("withdraw(uint256,address,address)")))
    extcall token.approve(DEPOSITOR, _amount)
    extcall IERC4626(DEPOSITOR).mint(_amount, self)
    log Stake(amount=_amount)

@external
def unstake(_amount: uint256):
    """
    @notice Initiate unstake stream from llYFI
    @param _amount Amount of YFI to unstake
    """
    assert msg.sender == recipient
    extcall IDepositor(DEPOSITOR).unstake(_amount)
    log Unstake(amount=_amount)

@external
def claim_stream(_amount: uint256 = max_value(uint256)):
    """
    @notice Claim from unstaking stream
    @param _amount Amount of YFI to claim
    """
    assert msg.sender == recipient
    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC4626(DEPOSITOR).maxRedeem(self)
    extcall IERC4626(DEPOSITOR).redeem(amount, self, self)
    extcall token.approve(gauge.address, amount)
    extcall gauge.deposit(amount, vest.address)
    log ClaimStream(amount=amount)

@external
def claim_rewards(_receiver: address = msg.sender) -> uint256:
    """
    @notice Claim rewards
    @param _receiver Address the rewards will be sent to
    @return Amount of reward tokens claimed
    """
    assert msg.sender == recipient
    amount: uint256 = extcall REWARD_CLAIMER.claim(_receiver)
    log ClaimRewards(receiver=_receiver, amount=amount)
    return amount

@external
def set_operator(_operator: address, _flag: bool):
    """
    @notice Add or remove an operator
    @param _operator Operator
    @param _flag True: operator, False: not operator
    """
    assert msg.sender == recipient
    assert _operator != empty(address)
    if _flag:
        assert staticcall factory.operators(vest.address, _operator)
    self.operators[_operator] = _flag
    log SetOperator(operator=_operator, flag=_flag)

@external
@payable
def call(_target: address, _data: Bytes[2048]):
    """
    @notice Call another contract through the operator
    @param _target The contract to call
    @param _data The calldata of the call
    """
    if msg.sender == recipient:
        if _target in [gauge.address, token.address, DEPOSITOR]:
            assert block.timestamp >= end_time
    else:
        assert self.operators[msg.sender]
    raw_call(_target, _data, value=msg.value)
    log Call(operator=msg.sender, target=_target)

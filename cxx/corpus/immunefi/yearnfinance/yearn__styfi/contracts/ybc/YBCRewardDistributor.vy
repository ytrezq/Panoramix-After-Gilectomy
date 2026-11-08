# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title YBC Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice YBC module that deals with distributing rewards originating from the Collective's staking position(s).
        Any state change forwarded by the upstream YBC weight aggregator results in a rewards claim through
        the YBC and is distributed proportionally to each member according to their aggregated staked balance.
        The contract can be killed, permanently disabling further yield claiming from the YBC while keeping
        the ability for members to claim already earned rewards intact.
"""

from ethereum.ercs import IERC20

interface IYBC:
    def call(_target: address, _data: Bytes[2048]): nonpayable

interface IComponent:
    def claim(_account: address) -> uint256: nonpayable

interface IHooks:
    def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _value: uint256): nonpayable
    def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable
    def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _value: uint256): nonpayable

interface IWeightAggregator:
    def supply() -> uint256: view
    def staked(_account: address) -> uint256: view

implements: IHooks
implements: IComponent

ybc: public(immutable(IYBC))
token: public(immutable(IERC20))
management: public(address)
pending_management: public(address)
killed: public(bool)
weight_aggregator: public(IWeightAggregator)
upstream_weights: public(address)
claim_from: public(address)
claimers: public(HashMap[address, bool])

last_balance: public(uint256)
reward_integral: public(uint256)
account_reward_integral: public(HashMap[address, uint256])
pending_rewards: public(HashMap[address, uint256])

event Claim:
    account: indexed(address)
    rewards: uint256

event Kill: pass

event SetWeightAggregator:
    aggregator: indexed(address)

event SetUpstreamWeights:
    upstream: indexed(address)

event SetClaimFrom:
    claim: indexed(address)

event SetClaimer:
    account: indexed(address)
    claimer: bool

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

PRECISION: constant(uint256) = 10**30

@deploy
def __init__(_ybc: address, _token: address):
    """
    @notice Constructor
    @param _ybc YBC address
    @param _token Reward token address
    """
    ybc = IYBC(_ybc)
    token = IERC20(_token)
    self.management = msg.sender

@external
def claim(_account: address) -> uint256:
    """
    @notice Claim rewards on behalf of an account
    @param _account Account to claim rewards for
    @return Amount of rewards tokens claimed
    """
    staked: uint256 = staticcall self.weight_aggregator.staked(_account)
    if staked == 0 and self.pending_rewards[_account] == 0:
        # shortcut accounts that have never participated in the YBC
        return 0

    assert self.claimers[msg.sender]

    supply: uint256 = staticcall self.weight_aggregator.supply()
    self._sync_integral(supply)
    pending: uint256 = self._sync_account_integral(_account, staked)
    if pending > 0:
        self.pending_rewards[_account] = 0
        self.last_balance -= pending
        assert extcall token.transfer(msg.sender, pending, default_return_value=True)
        log Claim(account=_account, rewards=pending)

    return pending

@external
def sync_rewards():
    """
    @notice Synchronize rewards by claiming from the YBC
    """
    supply: uint256 = staticcall self.weight_aggregator.supply()
    self._sync_integral(supply)

@external
def on_transfer(_caller: address, _from: address, _to: address, _supply: uint256, _prev_staked_from: uint256, _prev_staked_to: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon transfer of tokens
    @param _caller Originator of the transfer
    @param _from Sender of the token
    @param _to Recipient of the tokens
    @param _supply Total staked of all YBC members
    @param _prev_staked_from Staked balance of sender before transfer
    @param _prev_staked_to Staked balance of recipient before transfer
    @param _amount Amount of tokens to transfer
    @dev Should only be called if both sender and recipient are members of the YBC
    """
    assert msg.sender == self.upstream_weights

    self._sync_integral(_supply)
    self._sync_account_integral(_from, _prev_staked_from)
    self._sync_account_integral(_to, _prev_staked_to)

@external
def on_stake(_caller: address, _account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon staking of tokens
    @param _caller Originator of the tokens
    @param _account Recipient of the staked tokens
    @param _prev_supply Total staked of all YBC members, before stake
    @param _prev_staked Staked balance of recipient before stake
    @param _amount Amount of tokens to stake
    @dev Should only be called if account is a member of the YBC
    """
    assert msg.sender == self.upstream_weights

    self._sync_integral(_prev_supply)
    self._sync_account_integral(_account, _prev_staked)

@external
def on_unstake(_account: address, _prev_supply: uint256, _prev_staked: uint256, _amount: uint256):
    """
    @notice Triggered by the hook upon unstaking of tokens
    @param _account Originator of the staked tokens
    @param _prev_supply Total staked of all YBC members, before unstake
    @param _prev_staked Staked balance of originator before unstake
    @param _amount Amount of tokens to unstake
    @dev Should only be called if account is a member of the YBC
    """
    assert msg.sender == self.upstream_weights

    self._sync_integral(_prev_supply)
    self._sync_account_integral(_account, _prev_staked)

@external
def kill():
    """
    @notice Kill the contract, permanently disabling claiming of new rewards from the YBC
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert not self.killed

    self.killed = True
    log Kill()

@external
def sweep(_token: address, _amount: uint256 = max_value(uint256)):
    """
    @notice Transfer out a token
    @param _token The token address
    @param _amount The amount of tokens. Defaults to all
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _token != token.address or self.killed

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = staticcall IERC20(_token).balanceOf(self)

    assert extcall IERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_weight_aggregator(_aggregator: address):
    """
    @notice Set the YBC weight aggregator
    @param _aggregator Weight aggregator address
    @dev Can only be called by management
    @dev Should only aggregate weights of members of the YBC
    """
    assert msg.sender == self.management

    self.weight_aggregator = IWeightAggregator(_aggregator)
    log SetWeightAggregator(aggregator=_aggregator)

@external
def set_upstream_weights(_upstream: address):
    """
    @notice Set the upstream address where weight hooks are originating from
    @param _upstream Upstream weight hook address
    @dev Can only be called by management
    @dev Upstream should only send hooks for members of the YBC
    """
    assert msg.sender == self.management

    self.upstream_weights = _upstream
    log SetUpstreamWeights(upstream=_upstream)

@external
def set_claim_from(_claim: address):
    """
    @notice Set the address to claim YBC rewards from
    @param _claim Claim contract
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.claim_from = _claim
    log SetClaimFrom(claim=_claim)

@external
def set_claimer(_account: address, _claimer: bool):
    """
    @notice Whitelist account as reward claimer
    @param _account Account
    @param _claimer True: add to whitelist, False: remove from whitelist
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.claimers[_account] = _claimer
    log SetClaimer(account=_account, claimer=_claimer)

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
def _sync_integral(_supply: uint256):
    """
    @notice Claim rewards through the YBC and update integral.
            Should be called before any state change
    """
    if _supply < 10**12:
        # no reward accrual if YBC members dont have anything staked
        return

    if not self.killed:
        # claim rewards from YBC
        extcall ybc.call(self.claim_from, abi_encode(self, method_id=method_id("claim(address)")))

    # use token balance change to be able to accept donations
    balance: uint256 = staticcall token.balanceOf(self)
    rewards: uint256 = balance - self.last_balance

    self.last_balance = balance
    self.reward_integral += rewards * PRECISION // _supply

@internal
def _sync_account_integral(_account: address, _staked: uint256) -> uint256:
    """
    @notice Update users integral by attributing rewards to them.
            Should be called before any state change involving the user
    """
    integral: uint256 = self.reward_integral
    pending: uint256 = self.pending_rewards[_account]

    if _staked > 0:
        pending += (integral - self.account_reward_integral[_account]) * _staked // PRECISION
        self.pending_rewards[_account] = pending
    self.account_reward_integral[_account] = integral

    return pending

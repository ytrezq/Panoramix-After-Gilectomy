# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun
"""
@title Reward Distributor
@author Yearn Finance
@license GNU AGPLv3
@notice Distributes token rewards epoch-by-epoch to a set of preconfigured components, 
        proportionally to their self reported weight.
        Rewards can be deposited for future epochs and optionally pulled from another contract.
"""

from ethereum.ercs import IERC20

interface IComponent:
    def sync_total_weight(_epoch: uint256) -> uint256: nonpayable

interface IPull:
    def pull(_epoch: uint256) -> uint256: nonpayable

interface IDistributor:
    def genesis() -> uint256: view
    def claim() -> (uint256, uint256, uint256): nonpayable

implements: IDistributor

struct ComponentData:
    next: address
    epoch: uint256
    numerator: uint256
    denominator: uint256

genesis: public(immutable(uint256))
token: public(immutable(IERC20))
management: public(address)
pending_management: public(address)

pull: public(IPull)
num_components: public(uint256)
packed_components: public(HashMap[address, uint256])

last_epoch: public(uint256)
epoch_rewards: public(HashMap[uint256, uint256]) # epoch => rewards
epoch_total_weight: public(HashMap[uint256, uint256]) # epoch => total weight
epoch_weights: public(HashMap[address, HashMap[uint256, uint256]]) # component => epoch => weight

event FinalizeEpoch:
    epoch: uint256
    total_weight: uint256
    rewards: uint256

event AddRewards:
    depositor: indexed(address)
    epoch: uint256
    rewards: uint256

event SetPull:
    pull: indexed(address)

event AddComponent:
    component: indexed(address)
    after: address

event SetComponentScale:
    component: indexed(address)
    numerator: uint256
    denominator: uint256

event RemoveComponent:
    component: indexed(address)

event PendingManagement:
    management: indexed(address)

event SetManagement:
    management: indexed(address)

MAX_NUM_COMPONENTS: constant(uint256) = 32
COMPONENTS_SENTINEL: constant(address) = 0x1111111111111111111111111111111111111111
EPOCH_LENGTH: constant(uint256) = 14 * 24 * 60 * 60
EPOCH_MASK: constant(uint256) = 2**16 - 1
NUM_MASK: constant(uint256) = 2**40 - 1

@deploy
def __init__(_genesis: uint256, _token: address):
    """
    @notice Constructor
    @param _genesis Genesis timestamp
    @param _token The address of the reward token
    """
    genesis = _genesis
    token = IERC20(_token)

    self.management = msg.sender
    self.packed_components[COMPONENTS_SENTINEL] = self._pack(COMPONENTS_SENTINEL, 0, 0, 0)

@external
@view
def epoch() -> uint256:
    """
    @notice Query the current epoch number
    @return The current epoch number
    """
    return self._epoch()

@external
@view
def rewards(_component: address, _epoch: uint256) -> uint256:
    """
    @notice Query the rewards for a specific component
    @param _component The component address
    @param _epoch The epoch number
    @return The amount of reward tokens allocated to the component
    @dev Returns zero for any unsynced epoch
    """
    return self._rewards(_component, _epoch)[1]

@external
@nonreentrant
def claim() -> (uint256, uint256, uint256):
    """
    @notice Claim epoch rewards in order
    @return A tuple with the epoch number, the previous reported weight and the token rewards
    @dev Can only be called by an address that has been a component at one point
    """
    # weights and amounts are only finalized at the end of the epoch
    current: uint256 = self._epoch()
    assert self._sync(current, 32)

    next: address = empty(address)
    epoch: uint256 = 0
    num: uint256 = 0
    den: uint256 = 0
    next, epoch, num, den = self._unpack(self.packed_components[msg.sender])
    assert epoch < current

    weight: uint256 = 0
    rewards: uint256 = 0
    weight, rewards = self._rewards(msg.sender, epoch)
    self.packed_components[msg.sender] = self._pack(next, epoch + 1, num, den)

    assert extcall token.transfer(msg.sender, rewards, default_return_value=True)

    return epoch, weight, rewards

@external
@nonreentrant
def sync(_range: uint256 = 32) -> bool:
    """
    @notice Finalize weights and rewards for completed epochs
    @param _range Maximum number of epochs to update at once
    @return True: fully synchronized, False: not fully synchronized
    """
    assert _range > 0 and _range <= 32
    return self._sync(self._epoch(), _range)

@external
def deposit(_epoch: uint256, _amount: uint256):
    """
    @notice Deposit rewards for distribution in a future epoch
    @param _epoch Epoch number to ascribe rewards to
    @param _amount Amount of reward tokens to deposit
    """
    assert _epoch >= self._epoch()

    self.epoch_rewards[_epoch] += _amount
    assert extcall token.transferFrom(msg.sender, self, _amount, default_return_value=True)
    log AddRewards(depositor=msg.sender, epoch=_epoch, rewards=_amount)

@external
@view
def components(_component: address) -> ComponentData:
    next: address = empty(address)
    epoch: uint256 = 0
    numerator: uint256 = 0
    denominator: uint256 = 0
    next, epoch, numerator, denominator = self._unpack(self.packed_components[_component])
    return ComponentData(next=next, epoch=epoch, numerator=numerator, denominator=denominator)

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
def set_pull(_pull: address):
    """
    @notice Set the address to pull future rewards from
    @param _pull Address to pull from. Set to zero address if none
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    self.pull = IPull(_pull)
    log SetPull(pull=_pull)

@external
def add_component(_component: address, _numerator: uint256, _denominator: uint256, _after: address):
    """
    @notice Add a component
    @param _component Address of the component to add
    @param _numerator Number to multiply reported weights with
    @param _denominator Number to divide reported weights by
    @param _after Address in the list to add the component after
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _component != empty(address)
    assert _numerator > 0 and _denominator > 0

    next: address = empty(address)
    epoch: uint256 = 0
    old_num: uint256 = 0
    old_den: uint256 = 0
    next, epoch, old_num, old_den = self._unpack(self.packed_components[_component])
    assert next == empty(address)

    after_epoch: uint256 = 0
    after_num: uint256 = 0
    after_den: uint256 = 0
    next, after_epoch, after_num, after_den = self._unpack(self.packed_components[_after])
    assert next != empty(address)
    num_components: uint256 = self.num_components
    assert num_components < MAX_NUM_COMPONENTS

    self.num_components = num_components + 1
    self.packed_components[_after] = self._pack(_component, after_epoch, after_num, after_den)

    if epoch == 0 and block.timestamp >= genesis + EPOCH_LENGTH:
        epoch = self._epoch() - 1

    self.packed_components[_component] = self._pack(next, epoch, _numerator, _denominator)
    log AddComponent(component=_component, after=_after)
    log SetComponentScale(component=_component, numerator=_numerator, denominator=_denominator)

@external
def set_component_scale(_component: address, _numerator: uint256, _denominator: uint256):
    """
    @notice Set a components scale
    @param _component Address of the component to update
    @param _numerator Number to multiply reported weights with
    @param _denominator Number to divide reported weights by
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _component != empty(address) and _component != COMPONENTS_SENTINEL
    assert _numerator > 0 and _denominator > 0

    next: address = empty(address)
    epoch: uint256 = 0
    num: uint256 = 0
    den: uint256 = 0
    next, epoch, num, den = self._unpack(self.packed_components[_component])
    assert next != empty(address)

    self.packed_components[_component] = self._pack(next, epoch, _numerator, _denominator)
    log SetComponentScale(component=_component, numerator=_numerator, denominator=_denominator)

@external
def remove_component(_component: address, _previous: address):
    """
    @notice Remove a component
    @param _component Address of the component to remove
    @param _previous Address in the list before the component
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _component != empty(address) and _component != COMPONENTS_SENTINEL
    assert _previous != empty(address)

    prev_next: address = empty(address)
    prev_epoch: uint256 = 0
    prev_num: uint256 = 0
    prev_den: uint256 = 0
    prev_next, prev_epoch, prev_num, prev_den = self._unpack(self.packed_components[_previous])
    assert prev_next == _component

    next: address = empty(address)
    epoch: uint256 = 0
    num: uint256 = 0
    den: uint256 = 0
    next, epoch, num, den = self._unpack(self.packed_components[_component])
    assert next != empty(address)

    self.num_components -= 1
    self.packed_components[_previous] = self._pack(next, prev_epoch, prev_num, prev_den)
    self.packed_components[_component] = self._pack(empty(address), epoch, 0, 0)
    log RemoveComponent(component=_component)

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
def _epoch() -> uint256:
    return unsafe_div(block.timestamp - genesis, EPOCH_LENGTH)

@internal
def _sync(_current: uint256, _range: uint256) -> bool:
    """
    @notice Finalize weights and rewards for completed epochs in order
    """
    epoch: uint256 = self.last_epoch

    if epoch == _current:
        return True

    pull: IPull = self.pull
    for i: uint256 in range(_range, bound=32):
        if epoch == _current:
            break
        
        # calculate sum of weights of all components
        total_weight: uint256 = 0
        next: address = self._unpack(self.packed_components[COMPONENTS_SENTINEL])[0]
        for j: uint256 in range(MAX_NUM_COMPONENTS):
            if next == COMPONENTS_SENTINEL:
                break
            component: address = next
            component_epoch: uint256 = 0
            num: uint256 = 0
            den: uint256 = 0
            next, component_epoch, num, den = self._unpack(self.packed_components[component])

            weight: uint256 = extcall IComponent(component).sync_total_weight(epoch) * num // den
            self.epoch_weights[component][epoch] = weight
            total_weight += weight
        self.epoch_total_weight[epoch] = total_weight

        # try to pull in rewards
        if pull.address != empty(address):
            pulled: uint256 = extcall pull.pull(epoch)
            if pulled > 0:
                assert extcall token.transferFrom(pull.address, self, pulled, default_return_value=True)
                self.epoch_rewards[epoch] += pulled
                log AddRewards(depositor=pull.address, epoch=epoch, rewards=pulled)

        rewards: uint256 = self.epoch_rewards[epoch]
        if total_weight == 0:
            # no weight, allocate rewards to next epoch instead
            self.epoch_rewards[epoch] = 0
            self.epoch_rewards[epoch + 1] += rewards
            log AddRewards(depositor=self, epoch=epoch + 1, rewards=rewards)
            rewards = 0

        log FinalizeEpoch(epoch=epoch, total_weight=total_weight, rewards=rewards)
        epoch += 1

    self.last_epoch = epoch
    return epoch == _current

@internal
@view
def _rewards(_component: address, _epoch: uint256) -> (uint256, uint256):
    """
    @notice Compute rewards for a specific component in a specific epoch
    """
    total: uint256 = self.epoch_total_weight[_epoch]
    if total == 0:
        return 0, 0
    weight: uint256 = self.epoch_weights[_component][_epoch]
    return weight, self.epoch_rewards[_epoch] * weight // total

@internal
@pure
def _pack(_next: address, _epoch: uint256, _num: uint256, _den: uint256) -> uint256:
    """
    @notice Pack values into a single storage slot
    """
    assert _epoch <= EPOCH_MASK and _num <= NUM_MASK and _den <= NUM_MASK
    return (convert(_next, uint256) << 96) | (_epoch << 80) | (_num << 40) | _den

@internal
@pure
def _unpack(_packed: uint256) -> (address, uint256, uint256, uint256):
    """
    @notice Unpack values from a single storage slot
    """
    return convert(_packed >> 96, address), (_packed >> 80) & EPOCH_MASK, (_packed >> 40) & NUM_MASK, _packed & NUM_MASK

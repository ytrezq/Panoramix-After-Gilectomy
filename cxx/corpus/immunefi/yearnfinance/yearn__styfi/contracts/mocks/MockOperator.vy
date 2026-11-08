# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IStaker:
    def call(_target: address, _data: Bytes[2048]): payable

@external
def redeem(_staker: address, _target: address, _amount: uint256):
    extcall IStaker(_staker).call(_target, abi_encode(_amount, msg.sender, _staker, method_id=method_id("redeem(uint256,address,address)")))

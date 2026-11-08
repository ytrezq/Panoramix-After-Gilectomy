# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

recipient: public(address)
token: public(address)
start_time: public(uint256)
end_time: public(uint256)
cliff_length: public(uint256)
total_locked: public(uint256)

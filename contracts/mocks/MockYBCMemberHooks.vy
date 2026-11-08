# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IMemberHooks:
    def on_add_member(_account: address): nonpayable
    def on_remove_member(_account: address): nonpayable
implements: IMemberHooks

last_add: public(address)
last_remove: public(address)

@external
def on_add_member(_account: address):
    self.last_add = _account

@external
def on_remove_member(_account: address):
    self.last_remove = _account

# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IYBC:
    def members(_account: address) -> bool: view
implements: IYBC

members: public(HashMap[address, bool])

@external
def set_member(_account: address, _member: bool):
    self.members[_account] = _member


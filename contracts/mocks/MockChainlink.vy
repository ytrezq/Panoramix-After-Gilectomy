# pragma version 0.4.2
# pragma optimize gas
# pragma evm-version cancun

interface IChainLink:
    def latestRoundData() -> RoundData: view
implements: IChainLink

struct RoundData:
    id: uint80
    answer: int256
    started: uint256
    updated: uint256
    round: uint80

latestRoundData: public(RoundData)

@external
def set_data(_id: uint80, _answer: int256, _started: uint256, _updated: uint256, _round: uint80):
    self.latestRoundData = RoundData(id=_id, answer=_answer, started=_started, updated=_updated, round=_round)

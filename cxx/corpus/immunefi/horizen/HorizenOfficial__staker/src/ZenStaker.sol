// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Staker} from "./Staker.sol";
import {StakerPermitAndStake} from "./extensions/StakerPermitAndStake.sol";
import {DelegationSurrogate} from "./DelegationSurrogate.sol";
import {IEarningPowerCalculator} from "./interfaces/IEarningPowerCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @notice Minimal non-voting delegation surrogate for ZenStaker. Holds staked tokens on behalf
/// of depositors without delegating any governance voting power. Governance delegation is out of
/// scope for Phase 1.
contract ZenDelegationSurrogate is DelegationSurrogate {
  constructor(IERC20 _token) DelegationSurrogate(_token) {}
}

/// @title ZenStaker
/// @notice Horizen Phase 1 concrete staking implementation. Users stake ZEN to earn ZEN rewards.
/// All write logic is inherited unchanged from the audited Tally Staker base contracts.
/// The only additions are view-only helper functions that reduce RPC round-trips for the
/// Goldsky indexer and frontend.
contract ZenStaker is Staker, StakerPermitAndStake {
  /// @notice Maps each delegatee address to its non-voting delegation surrogate contract.
  mapping(address delegatee => DelegationSurrogate surrogate) private _surrogates;

  /// @param _token ZEN token address (used as both reward and stake token — ZEN-on-ZEN staking).
  /// @param _earningPowerCalculator Earning power calculator (use IdentityEarningPowerCalculator).
  /// @param _maxBumpTip Maximum tip a bumper may request (0 — bumping disabled in Phase 1).
  /// @param _admin Horizen multisig address.
  constructor(
    IERC20 _token,
    IEarningPowerCalculator _earningPowerCalculator,
    uint256 _maxBumpTip,
    address _admin
  )
    Staker(_token, _token, _earningPowerCalculator, _maxBumpTip, _admin)
    StakerPermitAndStake(IERC20Permit(address(_token)))
  {
    MAX_CLAIM_FEE = 0;
    _setClaimFeeParameters(ClaimFeeParameters({feeAmount: 0, feeCollector: address(0)}));
  }

  /// @inheritdoc Staker
  function surrogates(address _delegatee) public view override returns (DelegationSurrogate) {
    return _surrogates[_delegatee];
  }

  /// @inheritdoc Staker
  function _fetchOrDeploySurrogate(address _delegatee)
    internal
    override
    returns (DelegationSurrogate _surrogate)
  {
    _surrogate = _surrogates[_delegatee];
    if (address(_surrogate) == address(0)) {
      _surrogate = new ZenDelegationSurrogate(STAKE_TOKEN);
      _surrogates[_delegatee] = _surrogate;
    }
  }

  // ---------------------------------------------------------------------------
  // View helpers — no state changes, no new storage written during stake/withdraw/claim
  // ---------------------------------------------------------------------------

  /// @notice Returns all useful deposit data for a single deposit in one call.
  /// @param _depositId The deposit to query.
  function getDepositInfo(DepositIdentifier _depositId)
    external
    view
    returns (
      uint96 balance,
      address owner,
      uint96 earningPower,
      address delegatee,
      address claimer,
      uint256 unclaimedRewards
    )
  {
    Deposit storage d = deposits[_depositId];
    balance = d.balance;
    owner = d.owner;
    earningPower = d.earningPower;
    delegatee = d.delegatee;
    claimer = d.claimer;
    unclaimedRewards = _scaledUnclaimedReward(d) / SCALE_FACTOR;
  }

  /// @notice Batch version of getDepositInfo. Caller supplies deposit IDs sourced from the
  /// off-chain indexer (Goldsky). Returns parallel arrays.
  /// @param _depositIds List of deposit identifiers to query.
  function getDepositsInfo(DepositIdentifier[] calldata _depositIds)
    external
    view
    returns (
      uint96[] memory balances,
      address[] memory owners,
      uint96[] memory earningPowers,
      uint256[] memory unclaimedRewards
    )
  {
    uint256 len = _depositIds.length;
    balances = new uint96[](len);
    owners = new address[](len);
    earningPowers = new uint96[](len);
    unclaimedRewards = new uint256[](len);
    for (uint256 i = 0; i < len; i++) {
      Deposit storage d = deposits[_depositIds[i]];
      balances[i] = d.balance;
      owners[i] = d.owner;
      earningPowers[i] = d.earningPower;
      unclaimedRewards[i] = _scaledUnclaimedReward(d) / SCALE_FACTOR;
    }
  }

  /// @notice Returns all global state the frontend dashboard needs in one call.
  function getGlobalState()
    external
    view
    returns (
      uint256 totalStaked_,
      uint256 totalEarningPower_,
      uint256 rewardRate_,
      uint256 rewardEndTime_,
      uint256 lastCheckpointTime_,
      uint256 rewardPerTokenAccumulated_
    )
  {
    totalStaked_ = totalStaked;
    totalEarningPower_ = totalEarningPower;
    rewardRate_ = scaledRewardRate / SCALE_FACTOR;
    rewardEndTime_ = rewardEndTime;
    lastCheckpointTime_ = lastCheckpointTime;
    rewardPerTokenAccumulated_ = rewardPerTokenAccumulated();
  }

  /// @notice Returns aggregated staking totals for a single depositor address.
  /// @dev Does not aggregate unclaimed rewards across deposits — deposit IDs are tracked by the
  /// indexer, not on-chain. Use getDepositorFullSummary with the IDs from the indexer for reward
  /// totals.
  /// @param _depositor The address to query.
  function getDepositorSummary(address _depositor)
    public
    view
    returns (uint256 totalStaked_, uint256 totalEarningPower_)
  {
    totalStaked_ = depositorTotalStaked[_depositor];
    totalEarningPower_ = depositorTotalEarningPower[_depositor];
  }

  /// @notice Returns voting power as staking totals for a depositor
  /// @param account The address to query.
  function getVotes(address account) public view returns (uint256) {
    (uint256 totalStaked,) = getDepositorSummary(account);
    return totalStaked;
  }

  /// @notice Returns aggregated staking totals plus total unclaimed rewards for a depositor in
  /// one call. Deposit IDs must be supplied by the caller (sourced from the Goldsky indexer via
  /// StakeDeposited events filtered on the indexed owner field).
  /// @param _depositor The address to query.
  /// @param _depositIds All deposit IDs belonging to this depositor.
  function getDepositorFullSummary(address _depositor, DepositIdentifier[] calldata _depositIds)
    external
    view
    returns (uint256 totalStaked_, uint256 totalEarningPower_, uint256 totalUnclaimedRewards_)
  {
    totalStaked_ = depositorTotalStaked[_depositor];
    totalEarningPower_ = depositorTotalEarningPower[_depositor];
    uint256 len = _depositIds.length;
    for (uint256 i = 0; i < len; i++) {
      // Skip duplicate IDs to avoid double-counting rewards.
      bool duplicate = false;
      for (uint256 j = 0; j < i; j++) {
        if (DepositIdentifier.unwrap(_depositIds[j]) == DepositIdentifier.unwrap(_depositIds[i])) {
          duplicate = true;
          break;
        }
      }
      if (duplicate) continue;
      Deposit storage d = deposits[_depositIds[i]];
      if (d.owner == _depositor) {
        totalUnclaimedRewards_ += _scaledUnclaimedReward(d) / SCALE_FACTOR;
      }
    }
  }
}

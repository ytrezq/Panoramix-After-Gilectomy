// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title Interface for StakingAdmin contract
/// @author Simon Mall
/// @notice StakingAdmin is an abstract base contract for StakingRouter
/// @notice StakingAdmin is meant to have admin only functions
interface IStakingAdmin {
  /// @dev Thrown in constructor for invalid params
  error InvalidConstructor();

  /// @dev Thrown in constructor for invalid restricted tokens
  error InvalidRestrictedToken();

  /// @dev Thrown in `execute` when calling untrusted contracts
  error InvalidExecute();

  /// @dev Thrown in `execute` for executing arbitrary calls for staking contracts
  error ExecuteFailed();

  /// @dev Thrown when creating staking contracts that have already been created for that deposit token
  error StakingContractsAlreadySet();

  /// @dev Thrown when a initializing the StakingAdmin with a zero address
  error MissingBeaconProxyFactory();

  /// @dev Thrown when a zero address is passed as one of the GS token parameters
  error MissingGSTokenParameter();

  /// @dev Thrown when setting GS token parameters when they have already been set
  error GSTokensAlreadySet();

  /// @dev Contracts for global staking
  struct AssetCoreTracker {
    address rewardTracker;  // Track GS + esGS
    address rewardDistributor;  // Reward esGS
    address loanRewardTracker;  // Track esGSb
    address loanRewardDistributor;  // Reward esGSb
    address bonusTracker; // Track GS + esGS + esGSb
    address bonusDistributor; // Reward bnGS
    address feeTracker; // Track GS + esGS + esGSb + bnGS(aka MP)
    address feeDistributor; // Reward WETH
    address vester; // Vest esGS -> GS (reserve GS or esGS or bnGS)
    address loanVester; // Vest esGSb -> GS (without reserved tokens)
  }

  /// @dev Contracts for pool-level staking
  struct AssetPoolTracker {
    address rewardTracker;  // Track GS_LP
    address rewardDistributor;  // Reward esGS
    address loanRewardTracker;  // Track tokenId(loan)
    address loanRewardDistributor;  // Reward esGSb
    address vester; // Vest esGS -> GS (reserve GS_LP)
  }

  /// @dev Setting up GS token parameters so that we can initialize the GS staking contracts (coreTrackers)
  /// @notice This can only be set once
  /// @param _gs - address of GS token
  /// @param _esGs - address of escrow GS token
  /// @param _esGsb - address of escrow GS token for loans
  /// @param _bnGs - address of bonus GS token
  /// @param _feeRewardToken - address of fee reward token
  function initializeGSTokens(address _gs, address _esGs, address _esGsb, address _bnGs, address _feeRewardToken) external;

  /// @dev GS token entitles stakers to a share of protocol revenue
  /// @return address of GS token
  function gs() external view returns(address);

  /// @dev Escrow GS tokens convert to GS token when vested
  /// @return address of escrow GS token
  function esGs() external view returns(address);

  /// @dev Escrow GS token for loans convert to GS token when vested
  /// @return address of escrow GS token for loans
  function esGsb() external view returns(address);

  /// @dev Bonus GS tokens increases share of protocol fees when staking GS tokens
  /// @return address of Bonus GS token
  function bnGs() external view returns(address);

  /// @dev Fee reward token is given as protocol revenue to stakers of GS token
  /// @return address of fee reward token
  function feeRewardToken() external view returns(address);

  /// @dev Get contracts for global staking
  /// @return rewardTracker Track GS + esGS
  /// @return rewardDistributor Reward esGS
  /// @return loanRewardTracker Track esGSb
  /// @return loanRewardDistributor Reward esGSb
  /// @return bonusTracker Track GS + esGS + esGSb
  /// @return bonusDistributor Reward bnGS
  /// @return feeTracker Track GS + esGS + esGSb + bnGS(aka MP)
  /// @return feeDistributor Reward WETH
  /// @return vester Vest esGS -> GS (reserve GS or esGS or bnGS)
  /// @return loanVester Vest esGSb -> GS (without reserved tokens)
  function coreTracker() external view returns(address rewardTracker, address rewardDistributor, address loanRewardTracker,
    address loanRewardDistributor, address bonusTracker, address bonusDistributor, address feeTracker, address feeDistributor,
    address vester, address loanVester);

  /// @dev Get contracts for pool staking
  /// @param pool address of GS pool that staking contract is for
  /// @param esToken address of escrow token staking contract rewards
  /// @return rewardTracker Track GS_LP
  /// @return rewardDistributor Reward esGS
  /// @return loanRewardTracker Track tokenId(loan)
  /// @return loanRewardDistributor Reward esGSb
  /// @return vester Vest esGS -> GS (reserve GS_LP)
  function poolTrackers(address pool, address esToken) external view returns(address rewardTracker,
    address rewardDistributor, address loanRewardTracker, address loanRewardDistributor, address vester);

  /// @dev Initialize StakingAdmin contract
  /// @param _loanTrackerFactory address of BeaconProxyFactory with LoanTracker implementation
  /// @param _rewardTrackerFactory address of BeaconProxyFactory with RewardTracker implementation
  /// @param _feeTrackerFactory address of BeaconProxyFactory with FeeTracker implementation
  /// @param _rewardDistributorFactory address of BeaconProxyFactory with RewardDistributor implementation
  /// @param _bonusDistributorFactory address of BeaconProxyFactory with BonusDistributor implementation
  /// @param _vesterFactory address of BeaconProxyFactory with Vester implementation
  /// @param _vesterNoReserveFactory address of BeaconProxyFactory with VesterNoReserve implementation
  function initialize(address _loanTrackerFactory, address _rewardTrackerFactory, address _feeTrackerFactory,
    address _rewardDistributorFactory, address _bonusDistributorFactory, address _vesterFactory,
    address _vesterNoReserveFactory) external;

  /// @dev Set vesting period for staking contract reward token
  function setPoolVestingPeriod(uint256 _poolVestingPeriod) external;

  /// @dev Setup global staking for GS/esGS/bnGS
  function setupGsStaking() external;

  /// @dev Setup global staking for esGSb
  function setupGsStakingForLoan() external;

  /// @dev Setup pool-level staking for GS_LP
  /// @param _gsPool GammaPool address
  /// @param _esToken Escrow reward token
  /// @param _claimableToken Claimable token from vesting
  function setupPoolStaking(address _gsPool, address _esToken, address _claimableToken) external;

  /// @dev Setup pool-level staking for loans
  /// @param _gsPool GammaPool address
  /// @param _refId Reference id for loan observer
  function setupPoolStakingForLoan(address _gsPool, uint16 _refId) external;

  /// @dev Execute arbitrary calls for staking contracts
  /// @param _stakingContract Contract to execute on
  /// @param _data Bytes data to pass as param
  function execute(address _stakingContract, bytes memory _data) external;

  /// @dev Emitted in `setupGsStaking`
  event CoreTrackerCreated(address rewardTracker, address rewardDistributor, address bonusTracker, address bonusDistributor, address feeTracker, address feeDistributor, address vester);

  /// @dev Emitted in `setupGsStakingForLoan`
  event CoreTrackerUpdated(address loanRewardTracker, address loanRewardDistributor, address loanVester);

  /// @dev Emitted in `setupPoolStaking`
  event PoolTrackerCreated(address indexed gsPool, address rewardTracker, address rewardDistributor, address vester);

  /// @dev Emitted in `setupPoolStakingForLoan`
  event PoolTrackerUpdated(address indexed gsPool, address loanRewardtracker, address loanRewardDistributor);
}

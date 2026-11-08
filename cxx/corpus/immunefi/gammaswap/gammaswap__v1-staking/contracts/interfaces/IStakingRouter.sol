// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IStakingAdmin.sol";

/// @title Interface for StakingRouter contract
/// @author Simon Mall
/// @notice Contains user facing functions
interface IStakingRouter is IStakingAdmin {
    /* Stake */
    /// @dev Stake GS tokens on behalf of user
    /// @param _account User address for query
    /// @param _amount Amount of GS tokens to stake
    function stakeGsForAccount(address _account, uint256 _amount) external;

    /// @dev Stake GS tokens
    /// @param _amount Amount of GS tokens to stake
    function stakeGs(uint256 _amount) external;

    /// @dev Stake esGS tokens
    /// @param _amount AMount of esGS tokens to stake
    function stakeEsGs(uint256 _amount) external;

    /// @dev Stake esGSb tokens
    /// @param _amount Amount of esGSb tokens to stake
    function stakeEsGsb(uint256 _amount) external;

    /// @dev Stake GS_LP tokens on behalf of user
    /// @param _account User address for query
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Amount of GS_LP tokens to stake
    function stakeLpForAccount(address _account, address _gsPool, address _esToken, uint256 _amount) external;

    /// @dev Stake GS_LP tokens
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Amount of GS_LP tokens to stake
    function stakeLp(address _gsPool, address _esToken, uint256 _amount) external;

    /// @dev Stake loan on behalf of user
    /// @param _account User address for query
    /// @param _gsPool GammaPool address
    /// @param _loanId NFT loan id
    function stakeLoanForAccount(address _account, address _gsPool, uint256 _loanId) external;

    /// @dev Stake loan
    /// @param _gsPool GammaPool address
    /// @param _loanId NFT loan id
    function stakeLoan(address _gsPool, uint256 _loanId) external;

    /// @dev Unstake GS tokens
    /// @param _amount Amount of GS tokens to unstake
    function unstakeGs(uint256 _amount) external;

    /// @dev Unstake esGS tokens
    /// @param _amount Amount of esGS tokens to unstake
    function unstakeEsGs(uint256 _amount) external;

    /// @dev Unstake esGSb tokens
    /// @param _amount Amount of esGSb tokens to unstake
    function unstakeEsGsb(uint256 _amount) external;

    /// @dev Unstake GS_LP tokens on behalf of user
    /// @param _account User address for query
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Amount of GS_LP tokens to unstake
    function unstakeLpForAccount(address _account, address _gsPool, address _esToken, uint256 _amount) external;

    /// @dev Unstake GS_LP tokens
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Amount of GS_LP tokens to unstake
    function unstakeLp(address _gsPool, address _esToken, uint256 _amount) external;

    /// @dev Unstake loan on behalf of user
    /// @param _account User address for query
    /// @param _gsPool GammaPool address
    /// @param _loanId NFT loan id
    function unstakeLoanForAccount(address _account, address _gsPool, uint256 _loanId) external;

    /// @dev Unstake loan
    /// @param _gsPool GammaPool address
    /// @param _loanId NFT loan id
    function unstakeLoan(address _gsPool, uint256 _loanId) external;

    /* Vest */
    /// @dev Vest esGS tokens
    /// @param _amount Amount of esGS tokens to vest
    function vestEsGs(uint256 _amount) external;

    /// @dev Vest escrow tokens for pool
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Amount of escrow tokens to vest
    function vestEsTokenForPool(address _gsPool, address _esToken, uint256 _amount) external;

    /// @dev Vest esGSb tokens
    /// @param _amount Amount of esGSb tokens to vest
    function vestEsGsb(uint256 _amount) external;

    /// @dev Withdraw esGS tokens in vesting
    function withdrawEsGs() external;

    /// @dev Withdraw escrow tokens in vesting for pool
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    function withdrawEsTokenForPool(address _gsPool, address _esToken) external;

    /// @dev Withdraw esGSb tokens in vesting
    function withdrawEsGsb() external;

    /* Claim */
    /// @dev Claim rewards
    /// @param _shouldClaimRewards Should claim esGS rewards?
    /// @param _shouldClaimFee Should claim protocol revenue fees?
    /// @param _shouldClaimVesting Should claim vested GS?
    function claim(bool _shouldClaimRewards, bool _shouldClaimFee, bool _shouldClaimVesting) external;

    /// @dev Claim rewards for pool
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _shouldClaimRewards Should claim esToken rewards?
    /// @param _shouldClaimVesting Should claim vested Token?
    function claimPool(address _gsPool, address _esToken, bool _shouldClaimRewards, bool _shouldClaimVesting) external;

    /* Compound */
    /// @dev Compound staking
    function compound() external;

    /// @dev Compound staking on behalf of user
    /// @param _account User address for query
    function compoundForAccount(address _account) external;

    /// @dev Get average staked amount for user
    /// @param _gsPool GammaPool address, address(0) refers to coreTracker
    /// @param _esToken Escrow token address, optional when referring to coreTracker
    /// @param _account User address for query
    function getAverageStakedAmount(address _gsPool, address _esToken, address _account) external view returns (uint256);

    /// @dev Emitted in `_stakeGs` function
    event StakedGs(address, address, uint256);

    /// @dev Emitted in `_stakeLp` function
    event StakedLp(address, address, uint256);

    /// @dev Emitted in `_stakeLoan` function
    event StakedLoan(address, address, uint256);

    /// @dev Emitted in `_unstakeGs` function
    event UnstakedGs(address, address, uint256);

    /// @dev Emitted in `_unstakeLp` function
    event UnstakedLp(address, address, uint256);

    /// @dev Emitted in `_unstakeLoan` function
    event UnstakedLoan(address, address, uint256);
}
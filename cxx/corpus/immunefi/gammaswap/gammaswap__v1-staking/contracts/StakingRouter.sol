// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IRestrictedToken.sol";
import "./interfaces/IStakingRouter.sol";
import "./StakingAdmin.sol";

/// @title StakingRouter contract
/// @author Simon Mall
/// @notice Single entry for all staking related functions
contract StakingRouter is ReentrancyGuard, StakingAdmin, IStakingRouter {
    constructor(address _factory, address _manager) StakingAdmin(_factory, _manager) {
    }

    /// @inheritdoc IStakingRouter
    function stakeGsForAccount(address _account, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        _stakeGs(msg.sender, _account, gs, _amount);
    }

    /// @inheritdoc IStakingRouter
    function stakeGs(uint256 _amount) external override virtual nonReentrant {
        _stakeGs(msg.sender, msg.sender, gs, _amount);
    }

    /// @inheritdoc IStakingRouter
    function stakeEsGs(uint256 _amount) external override virtual nonReentrant {
        _stakeGs(msg.sender, msg.sender, esGs, _amount);
    }

    /// @inheritdoc IStakingRouter
    function stakeEsGsb(uint256 _amount) external override virtual nonReentrant {
        _stakeGs(msg.sender, msg.sender, esGsb, _amount);
    }

    /// @inheritdoc IStakingRouter
    function stakeLpForAccount(address _account, address _gsPool, address _esToken, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        _stakeLp(address(this), _account, _gsPool, _esToken, _amount);
    }

    /// @inheritdoc IStakingRouter
    function stakeLp(address _gsPool, address _esToken, uint256 _amount) external override virtual nonReentrant {
        _stakeLp(msg.sender, msg.sender, _gsPool, _esToken, _amount);
    }

    /// @inheritdoc IStakingRouter
    function stakeLoanForAccount(address _account, address _gsPool, uint256 _loanId) external override virtual nonReentrant {
        _validateHandler();
        _stakeLoan(_account, _gsPool, _loanId);
    }

    /// @inheritdoc IStakingRouter
    function stakeLoan(address _gsPool, uint256 _loanId) external override virtual nonReentrant {
        _stakeLoan(msg.sender, _gsPool, _loanId);
    }

    /// @inheritdoc IStakingRouter
    function unstakeGs(uint256 _amount) external override virtual nonReentrant {
        _unstakeGs(msg.sender, gs, _amount, true);
    }

    /// @inheritdoc IStakingRouter
    function unstakeEsGs(uint256 _amount) external override virtual nonReentrant {
        _unstakeGs(msg.sender, esGs, _amount, true);
    }

    /// @inheritdoc IStakingRouter
    function unstakeEsGsb(uint256 _amount) external override virtual nonReentrant {
        _unstakeGs(msg.sender, esGsb, _amount, true);
    }

    /// @inheritdoc IStakingRouter
    function unstakeLpForAccount(address _account, address _gsPool, address _esToken, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        _unstakeLp(_account, _gsPool, _esToken, _amount);
    }

    /// @inheritdoc IStakingRouter
    function unstakeLp(address _gsPool, address _esToken, uint256 _amount) external override virtual nonReentrant {
        _unstakeLp(msg.sender, _gsPool, _esToken, _amount);
    }

    /// @inheritdoc IStakingRouter
    function unstakeLoanForAccount(address _account, address _gsPool, uint256 _loanId) external override virtual nonReentrant {
        _validateHandler();
        _unstakeLoan(_account, _gsPool, _loanId);
    }

    /// @inheritdoc IStakingRouter
    function unstakeLoan(address _gsPool, uint256 _loanId) external override virtual nonReentrant {
        _unstakeLoan(msg.sender, _gsPool, _loanId);
    }

    /// @inheritdoc IStakingRouter
    function vestEsGs(uint256 _amount) external override virtual nonReentrant {
        IVester(_coreTracker.vester).depositForAccount(msg.sender, _amount);
    }

    /// @inheritdoc IStakingRouter
    function vestEsTokenForPool(address _gsPool, address _esToken, uint256 _amount) external override virtual nonReentrant {
        address _vester = _poolTrackers[_gsPool][_esToken].vester;
        require(_vester != address(0), "StakingRouter: pool vester not found");

        IVester(_vester).depositForAccount(msg.sender, _amount);
    }

    /// @inheritdoc IStakingRouter
    function vestEsGsb(uint256 _amount) external override virtual nonReentrant {
        IVester(_coreTracker.loanVester).depositForAccount(msg.sender, _amount);
    }

    /// @inheritdoc IStakingRouter
    function withdrawEsGs() external override virtual nonReentrant {
        IVester(_coreTracker.vester).withdrawForAccount(msg.sender);
    }

    /// @inheritdoc IStakingRouter
    function withdrawEsTokenForPool(address _gsPool, address _esToken) external override virtual nonReentrant {
        address _vester = _poolTrackers[_gsPool][_esToken].vester;
        require(_vester != address(0), "StakingRouter: pool vester not found");

        IVester(_vester).withdrawForAccount(msg.sender);
    }

    /// @inheritdoc IStakingRouter
    function withdrawEsGsb() external override virtual nonReentrant {
        IVester(_coreTracker.loanVester).withdrawForAccount(msg.sender);
    }

    /// @inheritdoc IStakingRouter
    function claim(bool _shouldClaimRewards, bool _shouldClaimFee, bool _shouldClaimVesting) external override virtual nonReentrant {
        address account = msg.sender;

        if (_shouldClaimRewards) {
            IRewardTracker(_coreTracker.rewardTracker).claimForAccount(account, account);
        }
        if (_shouldClaimFee) {
            IRewardTracker(_coreTracker.feeTracker).claimForAccount(account, account);
        }
        if (_shouldClaimVesting) {
            IVester(_coreTracker.vester).claimForAccount(account, account);
        }

        // Loan Staking rewards
        if (_coreTracker.loanRewardTracker != address(0)) {
            IRewardTracker(_coreTracker.loanRewardTracker).claimForAccount(account, account);
        }
        if (_coreTracker.loanVester != address(0)) {
            IVester(_coreTracker.loanVester).claimForAccount(account, account);
        }
    }

    /// @inheritdoc IStakingRouter
    function claimPool(address _gsPool, address _esToken, bool _shouldClaimRewards, bool _shouldClaimVesting) external override virtual nonReentrant {
        address account = msg.sender;

        if (_shouldClaimRewards) {
            address _rewardTracker = _poolTrackers[_gsPool][_esToken].rewardTracker;
            require(_rewardTracker != address(0), "StakingRouter: pool tracker not found");
            IRewardTracker(_rewardTracker).claimForAccount(account, account);
        }
        if (_shouldClaimVesting) {
            address _vester = _poolTrackers[_gsPool][_esToken].vester;
            require(_vester != address(0), "StakingRouter: pool vester not found");
            IVester(_vester).claimForAccount(account, account);
        }

        // Loan Staking rewards
        if (_poolTrackers[_gsPool][esGsb].loanRewardTracker != address(0)) {
            ILoanTracker(_poolTrackers[_gsPool][esGsb].loanRewardTracker).claimForAccount(account, account);
        }
    }

    /// @inheritdoc IStakingRouter
    function compound() external override virtual nonReentrant {
        _compound(msg.sender);
    }

    /// @inheritdoc IStakingRouter
    function compoundForAccount(address _account) external override virtual nonReentrant {
        _validateHandler();
        _compound(_account);
    }

    /// @inheritdoc IStakingRouter
    function getAverageStakedAmount(address _gsPool, address _esToken, address _account) public override virtual view returns (uint256) {
        address vester = _gsPool == address(0) ? _coreTracker.vester : _poolTrackers[_gsPool][_esToken].vester;
        require(vester != address(0), "Vester contract not found");

        return IVester(vester).getAverageStakedAmount(_account);
    }

    function _validateHandler() private view {
        address user = msg.sender;
        require(owner() == user || manager == user, "StakingRouter: forbidden");
    }

    /// @dev Stake GS/esGS/esGSb
    /// @param _fundingAccount Funding account to move tokens from
    /// @param _account Account to stake tokens for
    /// @param _token Staking token address
    /// @param _amount Staking amount
    function _stakeGs(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "StakingRouter: invalid amount");

        address rewardTracker = _coreTracker.rewardTracker;
        address bonusTracker = _coreTracker.bonusTracker;
        address feeTracker = _coreTracker.feeTracker;

        IRewardTracker(rewardTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusTracker).stakeForAccount(_account, _account, rewardTracker, _amount);
        IRewardTracker(feeTracker).stakeForAccount(_account, _account, bonusTracker, _amount);

        emit StakedGs(_account, _token, _amount);
    }

    /// @dev Deposit GS_LP tokens
    /// @param _fundingAccount Funding account to move tokens from
    /// @param _account Account to stake tokens for
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Staking amount
    function _stakeLp(address _fundingAccount, address _account, address _gsPool, address _esToken, uint256 _amount) private {
        require(_amount > 0, "StakingRouter: invalid amount");

        address _rewardTracker = _poolTrackers[_gsPool][_esToken].rewardTracker;
        require(_rewardTracker != address(0), "StakingRouter: pool tracker not found");

        IRewardTracker(_rewardTracker).stakeForAccount(_fundingAccount, _account, _gsPool, _amount);

        emit StakedLp(_account, _gsPool, _amount);
    }

    /// @dev Stake loan
    /// @param _account Owner of the loan
    /// @param _gsPool GammaPool address
    /// @param _loanId Loan Id
    function _stakeLoan(address _account, address _gsPool, uint256 _loanId) private {
        address _loanRewardTracker = _poolTrackers[_gsPool][esGsb].loanRewardTracker;
        require(_loanRewardTracker != address(0), "StakingRouter: pool loan tracker not found");

        ILoanTracker(_loanRewardTracker).stakeForAccount(_account, _loanId);

        emit StakedLoan(_account, _gsPool, _loanId);
    }

    /// @dev Unstake GS/esGS/esGSb
    /// @param _account Account to unstake from
    /// @param _token Staking token address
    /// @param _amount Amount to unstake
    /// @param _shouldReduceBnGs True if MP tokens should be burned (default true)
    function _unstakeGs(address _account, address _token, uint256 _amount, bool _shouldReduceBnGs) private {
        require(_amount > 0, "StakingRouter: invalid amount");

        address rewardTracker = _coreTracker.rewardTracker;
        address bonusTracker = _coreTracker.bonusTracker;
        address feeTracker = _coreTracker.feeTracker;

        uint256 balance = IRewardTracker(rewardTracker).stakedAmounts(_account);

        IRewardTracker(feeTracker).unstakeForAccount(_account, bonusTracker, _amount, _account);
        IRewardTracker(bonusTracker).unstakeForAccount(_account, rewardTracker, _amount, _account);
        IRewardTracker(rewardTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnGs) {
            uint256 bnGsAmount = IRewardTracker(bonusTracker).claimForAccount(_account, _account);
            if (bnGsAmount > 0) {
                IRewardTracker(feeTracker).stakeForAccount(_account, _account, bnGs, bnGsAmount);
            }

            uint256 stakedBnGs = IRewardTracker(feeTracker).depositBalances(_account, bnGs);
            if (stakedBnGs > 0) {
                uint256 reductionAmount = stakedBnGs * _amount / balance;
                IRewardTracker(feeTracker).unstakeForAccount(_account, bnGs, reductionAmount, _account);
                IRestrictedToken(bnGs).burn(_account, reductionAmount);
            }
        }

        emit UnstakedGs(_account, _token, _amount);
    }

    /// @dev Unstake GS_LP tokens
    /// @param _account Account to unstake from
    /// @param _gsPool GammaPool address
    /// @param _esToken Escrow token address
    /// @param _amount Amount to unstake
    function _unstakeLp(address _account, address _gsPool, address _esToken, uint256 _amount) private {
        require(_amount > 0, "StakingRouter: invalid amount");

        address _rewardTracker = _poolTrackers[_gsPool][_esToken].rewardTracker;
        require(_rewardTracker != address(0), "StakingRouter: pool tracker not found");

        IRewardTracker(_rewardTracker).unstakeForAccount(_account, _gsPool, _amount, _account);

        emit UnstakedLp(_account, _gsPool, _amount);
    }

    /// @dev Unstake loan
    /// @param _account Owner of the loan
    /// @param _gsPool GammaPool
    /// @param _loanId Loan Id
    function _unstakeLoan(address _account, address _gsPool, uint256 _loanId) private {
        address _loanRewardTracker = _poolTrackers[_gsPool][esGsb].loanRewardTracker;
        require(_loanRewardTracker != address(0), "StakingRouter: pool loan tracker not found");

        ILoanTracker(_loanRewardTracker).unstakeForAccount(_account, _loanId);

        emit UnstakedLoan(_account, _gsPool, _loanId);
    }

    /// @dev Compound and restake tokens
    /// @param _account User account to compound for
    function _compound(address _account) private {
        uint256 esGsAmount = IRewardTracker(_coreTracker.rewardTracker).claimForAccount(_account, _account);
        if (esGsAmount > 0) {
            _stakeGs(_account, _account, esGs, esGsAmount);
        }

        if (_coreTracker.loanRewardTracker != address(0)) {
            uint256 esGsbAmount = IRewardTracker(_coreTracker.loanRewardTracker).claimForAccount(_account, _account);
            if (esGsbAmount > 0) {
                _stakeGs(_account, _account, esGsb, esGsbAmount);
            }
        }

        uint256 bnGsAmount = IRewardTracker(_coreTracker.bonusTracker).claimForAccount(_account, _account);
        if (bnGsAmount > 0) {
            IRewardTracker(_coreTracker.feeTracker).stakeForAccount(_account, _account, bnGs, bnGsAmount);
        }
    }
}
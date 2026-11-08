// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";

/// @title RewardTracker contract
/// @author Simon Mall
/// @notice Earn rewards by staking whitelisted tokens
contract RewardTracker is Initializable, ReentrancyGuard, Ownable2Step, IRewardTracker {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e30;

    uint8 public constant decimals = 18;

    string public name;
    string public symbol;

    address public override distributor;

    bool public override inPrivateTransferMode;
    bool public override inPrivateStakingMode;
    bool public override inPrivateClaimingMode;

    mapping (address => bool) public isHandler;
    mapping (address => bool) public isDepositToken;
    mapping (address => mapping (address => uint256)) public override depositBalances;
    mapping (address => uint256) public override totalDepositSupply;

    uint256 public override totalSupply;
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowances;

    uint256 public cumulativeRewardPerToken;
    mapping (address => uint256) public override stakedAmounts;
    mapping (address => uint256) public claimableReward;
    mapping (address => uint256) public previousCumulatedRewardPerToken;
    mapping (address => uint256) public override cumulativeRewards;
    mapping (address => uint256) public override averageStakedAmounts;

    constructor() {
    }

    /// @inheritdoc IRewardTracker
    function initialize(
        string memory _name,
        string memory _symbol,
        address[] memory _depositTokens,
        address _distributor
    ) external override virtual initializer {
        _transferOwnership(msg.sender);

        name = _name;
        symbol = _symbol;
        inPrivateTransferMode = true;
        inPrivateStakingMode = true;
        inPrivateClaimingMode = true;

        for (uint256 i = 0; i < _depositTokens.length; i++) {
            address depositToken = _depositTokens[i];
            isDepositToken[depositToken] = true;
        }

        distributor = _distributor;
    }

    /// @inheritdoc IRewardTracker
    function setDepositToken(address _depositToken, bool _isDepositToken) external override virtual onlyOwner {
        isDepositToken[_depositToken] = _isDepositToken;
    }

    /// @inheritdoc IRewardTracker
    function setInPrivateTransferMode(bool _inPrivateTransferMode) external override virtual onlyOwner {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    /// @inheritdoc IRewardTracker
    function setInPrivateStakingMode(bool _inPrivateStakingMode) external override virtual onlyOwner {
        inPrivateStakingMode = _inPrivateStakingMode;
    }

    /// @inheritdoc IRewardTracker
    function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external override virtual onlyOwner {
        inPrivateClaimingMode = _inPrivateClaimingMode;
    }

    /// @inheritdoc IRewardTracker
    function setHandler(address _handler, bool _isActive) external override virtual onlyOwner {
        isHandler[_handler] = _isActive;
    }

    /// @inheritdoc IRewardTracker
    function withdrawToken(address _token, address _recipient, uint256 _amount) external override virtual onlyOwner {
        if (_token == address(0)) {
            payable(_recipient).transfer(_amount);
        } else {
            _amount = _amount == 0 ? IERC20(_token).balanceOf(address(this)) : _amount;
            IERC20(_token).safeTransfer(_recipient, _amount);
        }
    }

    /// @inheritdoc IERC20
    function balanceOf(address _account) external override virtual view returns (uint256) {
        return balances[_account];
    }

    /// @inheritdoc IRewardTracker
    function stake(address _depositToken, uint256 _amount) external override virtual nonReentrant {
        if (inPrivateStakingMode) { revert("RewardTracker: action not enabled"); }
        _stake(msg.sender, msg.sender, _depositToken, _amount);
    }

    /// @inheritdoc IRewardTracker
    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        _stake(_fundingAccount, _account, _depositToken, _amount);
    }

    /// @inheritdoc IRewardTracker
    function unstake(address _depositToken, uint256 _amount) external override virtual nonReentrant {
        if (inPrivateStakingMode) { revert("RewardTracker: action not enabled"); }
        _unstake(msg.sender, _depositToken, _amount, msg.sender);
    }

    /// @inheritdoc IRewardTracker
    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external override virtual nonReentrant {
        _validateHandler();
        _unstake(_account, _depositToken, _amount, _receiver);
    }

    /// @inheritdoc IERC20
    function transfer(address _recipient, uint256 _amount) external override virtual returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(address _owner, address _spender) external override virtual view returns (uint256) {
        return allowances[_owner][_spender];
    }

    /// @inheritdoc IERC20
    function approve(address _spender, uint256 _amount) external override virtual returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address _sender, address _recipient, uint256 _amount) external override virtual returns (bool) {
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }

        uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    /// @inheritdoc IRewardTracker
    function tokensPerInterval() external override virtual view returns (uint256) {
        return IRewardDistributor(distributor).tokensPerInterval();
    }

    /// @inheritdoc IRewardTracker
    function updateRewards() external override virtual nonReentrant {
        _updateRewards(address(0));
    }

    /// @inheritdoc IRewardTracker
    function claim(address _receiver) external override virtual nonReentrant returns (uint256) {
        if (inPrivateClaimingMode) { revert("RewardTracker: action not enabled"); }
        return _claim(msg.sender, _receiver);
    }

    /// @inheritdoc IRewardTracker
    function claimForAccount(address _account, address _receiver) external override virtual nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    /// @inheritdoc IRewardTracker
    function claimable(address _account) public override virtual view returns (uint256) {
        uint256 stakedAmount = stakedAmounts[_account];
        uint256 _claimableReward = claimableReward[_account];
        if (stakedAmount == 0) {
            return _claimableReward;
        }

        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards() * PRECISION;
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken + pendingRewards / totalSupply;

        return _claimableReward + (stakedAmount * (nextCumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION);
    }

    /// @dev Returns reward token address
    function rewardToken() public override virtual view returns (address) {
        return IRewardDistributor(distributor).rewardToken();
    }

    /// @dev Claim rewards
    /// @param _account Owner of staked tokens
    /// @param _receiver Receiver for rewards
    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken()).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount, _receiver);
        }

        return tokenAmount;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: mint to the zero address");

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        IRewardDistributor(distributor).updateTokensPerInterval();

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: burn from the zero address");

        balances[_account] = balances[_account] - _amount;
        totalSupply = totalSupply - _amount;

        IRewardDistributor(distributor).updateTokensPerInterval();

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "RewardTracker: transfer from the zero address");
        require(_recipient != address(0), "RewardTracker: transfer to the zero address");

        if (inPrivateTransferMode) { _validateHandler(); }

        balances[_sender] = balances[_sender] - _amount;
        balances[_recipient] = balances[_recipient] + _amount;

        emit Transfer(_sender, _recipient, _amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "RewardTracker: approve from the zero address");
        require(_spender != address(0), "RewardTracker: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "RewardTracker: forbidden");
    }

    /// @dev Stake tokens in the contract
    /// @param _fundingAccount User account with stakable tokens
    /// @param _account User account to stake tokens for
    /// @param _depositToken Eligible token for staking
    /// @param _amount Staking amount
    function _stake(address _fundingAccount, address _account, address _depositToken, uint256 _amount) internal virtual {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(isDepositToken[_depositToken], "RewardTracker: invalid _depositToken");

        IERC20(_depositToken).safeTransferFrom(_fundingAccount, address(this), _amount);

        _updateRewards(_account);

        stakedAmounts[_account] = stakedAmounts[_account] + _amount;
        depositBalances[_account][_depositToken] = depositBalances[_account][_depositToken] + _amount;
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken] + _amount;

        _mint(_account, _amount);

        emit Stake(_fundingAccount, _account, _depositToken, _amount);
    }

    /// @dev Unstake tokens from contract
    /// @param _account User account to unstake tokens from
    /// @param _depositToken Staked token address
    /// @param _amount Unstaking amount
    /// @param _receiver Receiver to refund tokens
    function _unstake(address _account, address _depositToken, uint256 _amount, address _receiver) internal virtual {
        require(_amount > 0, "RewardTracker: invalid _amount");

        _updateRewards(_account);

        uint256 stakedAmount = stakedAmounts[_account];
        require(stakedAmount >= _amount, "RewardTracker: _amount exceeds stakedAmount");

        stakedAmounts[_account] = stakedAmount - _amount;

        uint256 depositBalance = depositBalances[_account][_depositToken];
        require(depositBalance >= _amount, "RewardTracker: _amount exceeds depositBalance");

        depositBalances[_account][_depositToken] = depositBalance - _amount;
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken] - _amount;

        _burn(_account, _amount);
        IERC20(_depositToken).safeTransfer(_receiver, _amount);

        emit Unstake(_account, _depositToken, _amount, _receiver);
    }

    /// @dev Calculate rewards amount for the user
    /// @param _account User earning rewards
    function _updateRewards(address _account) internal virtual {
        uint256 blockReward = IRewardDistributor(distributor).distribute();

        uint256 supply = totalSupply;
        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        if (supply > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken + blockReward * PRECISION / supply;
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        emit RewardsUpdate(_cumulativeRewardPerToken);

        if (_account != address(0)) {
            uint256 stakedAmount = stakedAmounts[_account];
            uint256 accountReward = stakedAmount * (_cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION;
            uint256 _claimableReward = claimableReward[_account] + accountReward;

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;

            if (accountReward > 0 && stakedAmount > 0) {
                uint256 cumulativeReward = cumulativeRewards[_account];
                uint256 nextCumulativeReward = cumulativeReward + accountReward;
                uint256 _averageStakedAmount = averageStakedAmounts[_account] * cumulativeReward / nextCumulativeReward + stakedAmount * accountReward / nextCumulativeReward;
                averageStakedAmounts[_account] = _averageStakedAmount;

                cumulativeRewards[_account] = nextCumulativeReward;
                emit UserRewardsUpdate(_account, claimableReward[_account], _cumulativeRewardPerToken, _averageStakedAmount, nextCumulativeReward);
            } else {
                emit UserRewardsUpdate(_account, claimableReward[_account], _cumulativeRewardPerToken, averageStakedAmounts[_account], cumulativeRewards[_account]);
            }
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override virtual pure returns (bool) {
        return interfaceId == type(IRewardTracker).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

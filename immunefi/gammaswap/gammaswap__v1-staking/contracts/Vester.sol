// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IRestrictedToken.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";

/// @title Vester contract
/// @author Simon Mall
/// @notice Vest esGS tokens to claim GS tokens
/// @notice Vesting is done linearly over an year
/// @dev Requires averaged amount of pair tokens to be reserved
contract Vester is ReentrancyGuard, Ownable2Step, Initializable, IVester {
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override vestingDuration;

    address public override pairToken;
    address public override esToken;
    address public override claimableToken;

    address public override rewardTracker;

    uint256 public override totalSupply;
    uint256 public override pairSupply;
    uint256 public override totalClaimable;

    bool public override hasMaxVestableAmount;

    mapping (address => uint256) public balances;
    mapping (address => uint256) public override pairAmounts;
    mapping (address => uint256) public override cumulativeClaimAmounts;
    mapping (address => uint256) public override claimedAmounts;
    mapping (address => uint256) public override lastVestingTimes;

    mapping (address => uint256) public override cumulativeRewardDeductions;
    mapping (address => uint256) public override bonusRewards;

    mapping (address => bool) public isHandler;

    event Claim(address receiver, uint256 amount);
    event Deposit(address account, uint256 amount);
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);
    event PairTransfer(address indexed from, address indexed to, uint256 value);

    constructor (){
    }

    /// @inheritdoc IVester
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _vestingDuration,
        address _esToken,
        address _pairToken,
        address _claimableToken,
        address _rewardTracker) external override virtual initializer {
        _transferOwnership(msg.sender);
        name = _name;
        symbol = _symbol;

        vestingDuration = _vestingDuration;

        esToken = _esToken;
        pairToken = _pairToken;
        claimableToken = _claimableToken;

        rewardTracker = _rewardTracker;

        if (rewardTracker != address(0)) {
            hasMaxVestableAmount = true;
        }
    }

    /// @inheritdoc IVester
    function setVestingDuration(uint256 _vestingDuration) external override virtual onlyOwner {
        require(_vestingDuration > 0 && _vestingDuration <= 365 days, "Vester: Invalid duration");
        vestingDuration = _vestingDuration;
    }

    /// @inheritdoc IVester
    function setHandler(address _handler, bool _isActive) external override virtual onlyOwner {
        isHandler[_handler] = _isActive;
    }

    /// @inheritdoc IVester
    function withdrawToken(address _token, address _recipient, uint256 _amount) external override virtual onlyOwner {
        if (_token == address(0)) {
            payable(_recipient).transfer(_amount);
        } else {
            uint256 maxAmount = maxWithdrawableAmount();
            _amount = _amount == 0 || _amount > maxAmount ? maxAmount : _amount;
            if (_amount > 0) {
                IERC20(_token).safeTransfer(_recipient, _amount);
            }
        }
    }

    /// @inheritdoc IVester
    function maxWithdrawableAmount() public override virtual view returns (uint256) {
        uint256 rewardsSupply = IERC20(claimableToken).balanceOf(address(this));
        uint256 rewardsRequired = totalSupply + totalClaimable;

        require(rewardsSupply >= rewardsRequired, "Vester: Insufficient funds");

        return rewardsSupply - rewardsRequired;
    }

    /// @dev Restrict max cap of vestable token amounts
    /// @param _hasMaxVestableAmount True if applied
    function setHasMaxVestableAmount(bool _hasMaxVestableAmount) external virtual onlyOwner {
        hasMaxVestableAmount = _hasMaxVestableAmount;
    }

    /// @inheritdoc IVester
    function deposit(uint256 _amount) external override virtual nonReentrant {
        _deposit(msg.sender, _amount);
    }

    /// @inheritdoc IVester
    function depositForAccount(address _account, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        _deposit(_account, _amount);
    }

    /// @inheritdoc IVester
    function claim() external override virtual nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    /// @inheritdoc IVester
    function claimForAccount(address _account, address _receiver) external override virtual nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    /// @inheritdoc IVester
    function withdraw() external override virtual nonReentrant {
        _withdraw(msg.sender);
    }

    /// @inheritdoc IVester
    function withdrawForAccount(address _account) external override virtual nonReentrant {
        _validateHandler();
        _withdraw(_account);
    }

    /// @inheritdoc IVester
    function setCumulativeRewardDeductions(address _account, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        cumulativeRewardDeductions[_account] = _amount;
    }

    /// @inheritdoc IVester
    function setBonusRewards(address _account, uint256 _amount) external override virtual nonReentrant {
        _validateHandler();
        bonusRewards[_account] = _amount;
    }

    /// @inheritdoc IVester
    function claimable(address _account) public override virtual view returns (uint256) {
        uint256 amount = cumulativeClaimAmounts[_account] - claimedAmounts[_account];
        uint256 nextClaimable = _getNextClaimableAmount(_account);

        return amount + nextClaimable;
    }

    /// @inheritdoc IVester
    function getMaxVestableAmount(address _account) public override virtual view returns (uint256) {
        if (!hasRewardTracker()) { return 0; }

        uint256 bonusReward = bonusRewards[_account];
        uint256 cumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_account);
        uint256 maxVestableAmount = cumulativeReward + bonusReward;

        uint256 cumulativeRewardDeduction = cumulativeRewardDeductions[_account];

        if (maxVestableAmount < cumulativeRewardDeduction) {
            return 0;
        }

        return maxVestableAmount - cumulativeRewardDeduction;
    }

    /// @inheritdoc IVester
    function getAverageStakedAmount(address _account) public override virtual view returns (uint256) {
        uint256 cumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_account);
        if (cumulativeReward == 0) { return 0; }

        return IRewardTracker(rewardTracker).averageStakedAmounts(_account);
    }

    /// @inheritdoc IVester
    function getPairAmount(address _account, uint256 _esAmount) public override virtual view returns (uint256) {
        if (!hasRewardTracker()) { return 0; }

        uint256 averageStakedAmount = getAverageStakedAmount(_account);
        if (averageStakedAmount == 0) {
            return 0;
        }

        uint256 maxVestableAmount = getMaxVestableAmount(_account);
        if (maxVestableAmount == 0) {
            return 0;
        }

        return _esAmount * averageStakedAmount / maxVestableAmount;
    }

    /// @dev Returns if reward tracker is set
    function hasRewardTracker() public virtual view returns (bool) {
        return rewardTracker != address(0);
    }

    /// @dev Returns if pair token is set
    function hasPairToken() public virtual view returns (bool) {
        return pairToken != address(0);
    }

    /// @inheritdoc IVester
    function getTotalVested(address _account) public override virtual view returns (uint256) {
        return balances[_account] + cumulativeClaimAmounts[_account];
    }

    /// @inheritdoc IERC20
    function balanceOf(address _account) public override virtual view returns (uint256) {
        return balances[_account];
    }

    /// @inheritdoc IERC20
    // empty implementation, tokens are non-transferrable
    function transfer(address /* recipient */, uint256 /* amount */) public override virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    /// @inheritdoc IERC20
    // empty implementation, tokens are non-transferrable
    function allowance(address /* owner */, address /* spender */) public override virtual view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IERC20
    // empty implementation, tokens are non-transferrable
    function approve(address /* spender */, uint256 /* amount */) public override virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    /// @inheritdoc IERC20
    // empty implementation, tokens are non-transferrable
    function transferFrom(address /* sender */, address /* recipient */, uint256 /* amount */) public override virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    /// @inheritdoc IVester
    function getVestedAmount(address _account) public override virtual view returns (uint256) {
        uint256 balance = balances[_account];
        uint256 cumulativeClaimAmount = cumulativeClaimAmounts[_account];

        return balance + cumulativeClaimAmount;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override virtual pure returns (bool) {
        return interfaceId == type(IVester).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "Vester: forbidden");
    }

    function _mint(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _mintPair(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        pairSupply = pairSupply + _amount;
        pairAmounts[_account] = pairAmounts[_account] + _amount;

        emit PairTransfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        balances[_account] = balances[_account] - _amount;
        totalSupply = totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _burnPair(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        pairAmounts[_account] = pairAmounts[_account] - _amount;
        pairSupply = pairSupply - _amount;

        emit PairTransfer(_account, address(0), _amount);
    }

    function _deposit(address _account, uint256 _amount) private {
        require(_amount > 0, "Vester: invalid _amount");

        _updateVesting(_account);

        IERC20(esToken).safeTransferFrom(_account, address(this), _amount);

        _mint(_account, _amount);

        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[_account];
            uint256 nextPairAmount = getPairAmount(_account, balances[_account]);
            require(hasMaxVestableAmount || nextPairAmount > 0, "Vester: no staking history");
            if (nextPairAmount > pairAmount) {
                uint256 pairAmountDiff = nextPairAmount - pairAmount;
                IERC20(pairToken).safeTransferFrom(_account, address(this), pairAmountDiff);
                _mintPair(_account, pairAmountDiff);
            }
        }

        if (hasMaxVestableAmount) {
            uint256 maxAmount = getMaxVestableAmount(_account);
            require(getTotalVested(_account) <= maxAmount, "Vester: max vestable amount exceeded");
        }

        emit Deposit(_account, _amount);
    }

    /// @dev Returns claimable GS amount
    /// @param _account Vesting account
    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastVestingTimes[_account];

        uint256 balance = balances[_account];
        if (balance == 0) { return 0; }

        uint256 claimableAmount = balance * timeDiff / vestingDuration;

        if (claimableAmount < balance) {
            return claimableAmount;
        }

        return balance;
    }

    /// @dev Claim pending GS tokens
    /// @param _account Vesting account
    /// @param _receiver Receiver of rewards
    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateVesting(_account);

        uint256 amount = claimable(_account);
        unchecked {
            claimedAmounts[_account] = claimedAmounts[_account] + amount;
            totalClaimable -= amount;
        }
        IERC20(claimableToken).safeTransfer(_receiver, amount);

        emit Claim(_account, amount);

        return amount;
    }

    /// @dev Withdraw esGS tokens and cancel vesting
    /// @param _account Vesting account
    function _withdraw(address _account) private {
        _claim(_account, _account);

        uint256 claimedAmount = cumulativeClaimAmounts[_account];
        uint256 balance = balances[_account];
        uint256 totalVested = balance + claimedAmount;
        require(totalVested > 0, "Vester: vested amount is zero");

        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[_account];
            _burnPair(_account, pairAmount);
            IERC20(pairToken).safeTransfer(_account, pairAmount);
        }

        IERC20(esToken).safeTransfer(_account, balance);
        _burn(_account, balance);

        delete cumulativeClaimAmounts[_account];
        delete claimedAmounts[_account];
        delete lastVestingTimes[_account];

        emit Withdraw(_account, claimedAmount, balance);
    }

    /// @dev Update vesting params for user
    /// @param _account Vesting account
    function _updateVesting(address _account) private {
        uint256 amount = _getNextClaimableAmount(_account);
        lastVestingTimes[_account] = block.timestamp;

        if (amount == 0) {
            return;
        }

        // transfer claimableAmount from balances to cumulativeClaimAmounts
        _burn(_account, amount);
        unchecked {
            cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account] + amount;
            totalClaimable += amount;
        }

        IRestrictedToken(esToken).burn(address(this), amount);
    }
}

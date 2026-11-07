// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@gammaswap/v1-core/contracts/interfaces/IGammaPool.sol";
import "@gammaswap/v1-core/contracts/interfaces/observer/ILoanObserver.sol";

import "./interfaces/ILoanTracker.sol";
import "./interfaces/IRewardDistributor.sol";

/// @title LoanTracker contract
/// @author Simon Mall
/// @notice Track loan staking and their rewards
contract LoanTracker is Initializable, ReentrancyGuard, Ownable2Step, ILoanTracker, ILoanObserver {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILoanObserver
    address public override factory;

    /// @inheritdoc ILoanObserver
    uint16 public override refId;

    /// @inheritdoc ILoanObserver
    uint16 public immutable override refType = 2;

    uint256 public constant PRECISION = 1e30;

    uint8 public constant decimals = 18;
    string public name;
    string public symbol;

    address public override manager;
    address public override gsPool;
    address public override distributor;

    mapping (address => bool) public isHandler;

    uint256 public override totalSupply;
    mapping (address => uint256) public balances;
    mapping (uint256 => address) public override stakedLoans;

    uint256 public cumulativeRewardPerToken;
    mapping (address => uint256) public claimableReward;
    mapping (address => uint256) public previousCumulatedRewardPerToken;
    mapping (address => uint256) public override cumulativeRewards;

    constructor(){
    }

    /// @inheritdoc ILoanTracker
    function initialize(
        address _factory,
        uint16 _refId,
        address _manager,
        string memory _name,
        string memory _symbol,
        address _gsPool,
        address _distributor
    ) external override virtual initializer {
        _transferOwnership(msg.sender);

        factory = _factory;
        refId = _refId;
        manager = _manager;
        name = _name;
        symbol = _symbol;
        gsPool = _gsPool;
        distributor = _distributor;
    }

    /// @inheritdoc ILoanTracker
    function setHandler(address _handler, bool _isActive) external override virtual onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function balanceOf(address _account) external override virtual view returns (uint256) {
        return balances[_account];
    }

    /// @inheritdoc ILoanTracker
    function stake(uint256 _loanId) external override virtual nonReentrant {
        _stake(msg.sender, _loanId);
    }

    /// @inheritdoc ILoanTracker
    function stakeForAccount(address _account, uint256 _loanId) external override virtual nonReentrant {
        _validateHandler();
        _stake(_account, _loanId);
    }

    /// @inheritdoc ILoanTracker
    function unstake(uint256 _loanId) external override virtual nonReentrant {
        _unstake(msg.sender, _loanId);
    }

    /// @inheritdoc ILoanTracker
    function unstakeForAccount(address _account, uint256 _loanId) external override virtual nonReentrant {
        _validateHandler();
        _unstake(_account, _loanId);
    }

    function transfer(address, uint256) external override virtual returns (bool) {
        revert("LoanTracker: Forbidden");
    }

    function allowance(address, address) external override virtual pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external override virtual returns (bool) {
        revert("LoanTracker: Forbidden");
    }

    function transferFrom(address, address, uint256) external override virtual returns (bool) {
        revert("LoanTracker: Forbidden");
    }

    /// @inheritdoc ILoanTracker
    function tokensPerInterval() external override virtual view returns (uint256) {
        return IRewardDistributor(distributor).tokensPerInterval();
    }

    /// @inheritdoc ILoanTracker
    function updateRewards() external override virtual nonReentrant {
        _updateRewards(address(0));
    }

    /// @inheritdoc ILoanTracker
    function claim(address _receiver) external override virtual nonReentrant returns (uint256) {
        return _claim(msg.sender, _receiver);
    }

    /// @inheritdoc ILoanTracker
    function claimForAccount(address _account, address _receiver) external override virtual nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    /// @inheritdoc ILoanTracker
    function claimable(address _account) public override virtual view returns (uint256) {
        uint256 balance = balances[_account];
        uint256 _claimableReward = claimableReward[_account];
        if (balance == 0) {
            return _claimableReward;
        }

        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards() * PRECISION;
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken + pendingRewards / totalSupply;

        return _claimableReward + (balance * (nextCumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION);
    }

    /// @inheritdoc ILoanObserver
    function onLoanUpdate(address, uint16, uint256 _loanId, bytes memory _data) external override virtual returns(uint256) {
        IGammaPool.LoanData memory loanData = IGammaPool(gsPool).getLoanData(_loanId);
        require(loanData.initLiquidity > 0, "LoanTracker: invalid loan");

        address account = stakedLoans[_loanId];
        if (account != address(0)) {
            LoanObserved memory loan = abi.decode(_data, (LoanObserved));
            if (loan.liquidity == 0) {
                // Loan liquidated and need to stop rewards for this loan
                _unstake(account, _loanId);
            }
        }

        return 0;
    }

    /// @inheritdoc ILoanObserver
    function validate(address _gsPool) external override virtual view returns(bool) {
        return gsPool == _gsPool;
    }

    /// @inheritdoc ILoanTracker
    function rewardToken() public override virtual view returns (address) {
        return IRewardDistributor(distributor).rewardToken();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override virtual pure returns (bool) {
        return interfaceId == type(ILoanTracker).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken()).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
    }

    /// @dev Mint tokens for user
    /// @dev Triggered in `onLoanUpdate`
    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "LoanTracker: mint to the zero address");

        balances[_account] = balances[_account] + _amount;
        totalSupply = totalSupply + _amount;

        emit Transfer(address(0), _account, _amount);
    }

    /// @dev Burn tokens from user
    /// @dev Triggered in `onLoanUpdate`
    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "LoanTracker: burn from the zero address");

        balances[_account] = balances[_account] - _amount;
        totalSupply = totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "LoanTracker: forbidden");
    }

    /// @dev Stake loan from user
    /// @param _account Owner of the loan
    /// @param _loanId Loan Id
    function _stake(address _account, uint256 _loanId) private {
        require(IERC721(manager).ownerOf(_loanId) == _account, "LoanTracker: stake forbidden");
        require(stakedLoans[_loanId] == address(0), "LoanTracker: loan already staked");

        IGammaPool.LoanData memory loanData = IGammaPool(gsPool).getLoanData(_loanId);
        require(loanData.initLiquidity > 0 && loanData.liquidity > 0, "LoanTracker: invalid loan");

        stakedLoans[_loanId] = _account;

        _updateRewards(_account);

        _mint(_account, loanData.initLiquidity);
    }

    /// @dev Unstake loan from contract
    /// @param _account Owner of the loan
    /// @param _loanId Loan Id
    function _unstake(address _account, uint256 _loanId) private {
        require(stakedLoans[_loanId] == _account, "LoanTracker: loan stake mismatch");

        _updateRewards(_account);

        IGammaPool.LoanData memory loanData = IGammaPool(gsPool).getLoanData(_loanId);

        _burn(_account, loanData.initLiquidity);
    }

    /// @dev Calculate rewards amount for the user
    /// @param _account User earning rewards
    function _updateRewards(address _account) private {
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

        if (_account != address(0)) {
            uint256 balance = balances[_account];
            uint256 accountReward = balance * (_cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION;
            uint256 _claimableReward = claimableReward[_account] + accountReward;

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;

            if (_claimableReward > 0 && balance > 0) {
                uint256 cumulativeReward = cumulativeRewards[_account];
                uint256 nextCumulativeReward = cumulativeReward + accountReward;
                cumulativeRewards[_account] = nextCumulativeReward;
            }
        }
    }
}
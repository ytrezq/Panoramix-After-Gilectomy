// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./inheritance/Controllable.sol";
import "./interface/IController.sol";
import "./interface/IStrategy.sol";

contract RewardPrePayMorhpo is Controllable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event RewardUpdated(address indexed strategy, uint256 oldValue, uint256 newValue);
    event RewardClaimed(address indexed strategy, uint256 amount);
    event RewardRepayed(address indexed strategy, uint256 amount);
    event StrategyInitialized(address indexed strategy, uint256 earned, uint256 claimed);
    event StrategyForceUpdated(address indexed strategy, uint256 earned, uint256 claimed, bool initialized);

    address public constant MORPHO = address(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);

    mapping (address => uint256) public rewardEarned;
    mapping (address => uint256) public rewardClaimed;
    mapping (address => bool) public strategyInitialized;

    modifier onlyHardWorkerOrGovernance() {
        require(IController(controller()).hardWorkers(msg.sender) || (msg.sender == governance()),
            "only hard worker can call this");
        _;
    }

    modifier onlyInitialized(address _strategy) {
        require(strategyInitialized[_strategy], "strategy not initialized");
        _;
    }

    constructor(address _storage) Controllable(_storage) {}

    function updateReward(address _strategy, uint256 _newAmount) public onlyHardWorkerOrGovernance onlyInitialized(_strategy) {
        require(_newAmount >= rewardEarned[_strategy], "new amount must be greater than current amount");
        uint256 oldAmount = rewardEarned[_strategy];
        rewardEarned[_strategy] = _newAmount;
        emit RewardUpdated(_strategy, oldAmount, _newAmount);
    }

    function batchUpdateReward(address[] calldata _strategies, uint256[] calldata _newAmounts) external onlyHardWorkerOrGovernance {
        require(_strategies.length == _newAmounts.length, "array length mismatch");
        for (uint256 i = 0; i < _strategies.length; i++) {
            updateReward(_strategies[i], _newAmounts[i]);
        }
    }

    function claimable(address _strategy) public view returns (uint256) {
        return rewardEarned[_strategy].sub(rewardClaimed[_strategy]);
    }

    function _claim(address _strategy) internal onlyInitialized(_strategy) {
        uint256 claimableAmount = claimable(_strategy);
        uint256 payableAmount = claimableAmount.mul(100).div(101);
        uint256 balance = IERC20(MORPHO).balanceOf(address(this));
        if (payableAmount > 0 && balance > 0) {
            if (payableAmount > balance) {
                payableAmount = balance;
                claimableAmount = payableAmount.mul(101).div(100);
            }
            IERC20(MORPHO).safeTransfer(_strategy, payableAmount);
            rewardClaimed[_strategy] = rewardClaimed[_strategy].add(claimableAmount);
            emit RewardClaimed(_strategy, claimableAmount);
        }
    }

    function claim() external {
        _claim(msg.sender);
    }

    function claimFor(address _strategy) external onlyGovernance {
        _claim(_strategy);
    }

    function initializeStrategy(address _strategy, uint256 _earned, uint256 _claimed) external onlyGovernance {
        require(!strategyInitialized[_strategy], "strategy already initialized");
        rewardEarned[_strategy] = _earned;
        rewardClaimed[_strategy] = _claimed;
        strategyInitialized[_strategy] = true;
        emit StrategyInitialized(_strategy, _earned, _claimed);
    }

    function forceUpdateValues(address _strategy, uint256 _earned, uint256 _claimed, bool _initialized) external onlyGovernance {
        rewardEarned[_strategy] = _earned;
        rewardClaimed[_strategy] = _claimed;
        strategyInitialized[_strategy] = _initialized;
        emit StrategyForceUpdated(_strategy, _earned, _claimed, _initialized);
    }

    function salvage(address _token, uint256 _amount) external onlyGovernance {
        IERC20(_token).safeTransfer(governance(), _amount);
    }

    function morphoClaim(
        address strategy,
        uint256 newAmount,
        address distr,
        bytes calldata txData
    ) public onlyHardWorkerOrGovernance {
        updateReward(strategy, newAmount);
        _claim(strategy);
        uint256 balanceBefore = IERC20(MORPHO).balanceOf(address(this));
        IStrategy(strategy).morphoClaim(distr, txData);
        uint256 received = IERC20(MORPHO).balanceOf(address(this)).sub(balanceBefore);
        rewardClaimed[strategy] = rewardClaimed[strategy].sub(received);
        rewardEarned[strategy] = rewardEarned[strategy].sub(received);
        emit RewardRepayed(strategy, received);
    }

    function batchMorphoClaim(
        address[] calldata strategies,
        uint256[] calldata newAmounts,
        address[] calldata distrs,
        bytes[] calldata txDatas
    ) external onlyHardWorkerOrGovernance {
        require(
            strategies.length == newAmounts.length &&
            strategies.length == distrs.length &&
            strategies.length == txDatas.length,
            "array length mismatch"
        );
        for (uint256 i = 0; i < strategies.length; i++) {
            morphoClaim(strategies[i], newAmounts[i], distrs[i], txDatas[i]);
        }
    }
}

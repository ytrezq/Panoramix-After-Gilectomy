//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/penpie/IPendleRouter.sol";
import "../../base/interface/penpie/IMasterPenpie.sol";
import "../../base/interface/penpie/IPendleDepositHelper.sol";
import "../../base/interface/penpie/ISYToken.sol";
import "../../base/interface/penpie/IPendleStaking.sol";
import "../../base/interface/weth/IWETH.sol";

contract PenpieStrategy is BaseUpgradeableStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public constant harvestMSIG = address(0xF49440C1F012d041802b25A73e5B0B9166a75c02);
    address public constant depositHelper = address(0x1C1Fb35334290b5ff1bF7B4c09130885b10Fc0f4);
    address public constant pendleRouter = address(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    address public constant pendleStaking = address(0x6E799758CEE75DAe3d84e09D40dc416eCf713652);

    // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
    bytes32 internal constant _DEPOSIT_TOKEN_SLOT = 0x219270253dbc530471c88a9e7c321b36afda219583431e7b6c386d2d46e70c86;
    bytes32 internal constant _SY_TOKEN_SLOT = 0xaa4e3a958f46649628713af979d9e90ad0212e775c6bacc4fcedb0fbbbee1e72;

    // this would be reset on each upgrade
    address[] public rewardTokens;

    constructor() BaseUpgradeableStrategy() {
        assert(_DEPOSIT_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositToken")) - 1));
        assert(_SY_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.syToken")) - 1));
    }

    function initializeBaseStrategy(
        address _storage,
        address _underlying,
        address _vault,
        address _rewardPool,
        address _rewardToken,
        address _depositToken,
        address _syToken
    ) public initializer {
        BaseUpgradeableStrategy.initialize(
            _storage,
            _underlying,
            _vault,
            _rewardPool,
            _rewardToken,
            harvestMSIG
        );

        require(ISYToken(_syToken).isValidTokenIn(_depositToken), "Deposit/ST token mismatch");
        _setDepositToken(_depositToken);
        _setSyToken(_syToken);
    }

    function depositArbCheck() public pure returns (bool) {
        return true;
    }

    function _rewardPoolBalance() internal view returns (uint256 balance) {
        balance = IPendleDepositHelper(depositHelper).balance(underlying(), address(this));
    }

    function _investAllUnderlying() internal onlyNotPausedInvesting {
        address _underlying = underlying();
        uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
        if (entireBalance > 0) {
            IERC20(_underlying).safeApprove(pendleStaking, 0);
            IERC20(_underlying).safeApprove(pendleStaking, entireBalance);
            IPendleDepositHelper(depositHelper).depositMarket(_underlying, entireBalance);
        }
    }

    function _exitRewardPool() internal {
        uint256 stakedBalance = _rewardPoolBalance();
        if (stakedBalance != 0) {
            IPendleDepositHelper(depositHelper).withdrawMarket(underlying(), stakedBalance);
        }
    }

    function _withdrawUnderlyingFromPool(uint256 amount) internal {
        if (amount > 0) {
            IPendleDepositHelper(depositHelper).withdrawMarket(underlying(), amount);
        }
    }

    /*
     *   In case there are some issues discovered about the pool or underlying asset
     *   Governance can exit the pool properly
     *   The function is only used for emergency to exit the pool
     */
    function emergencyExit() public onlyGovernance {
        _exitRewardPool();
        _setPausedInvesting(true);
    }

    /*
     *   Resumes the ability to invest into the underlying reward pools
     */
    function continueInvesting() public onlyGovernance {
        _setPausedInvesting(false);
    }

    function unsalvagableTokens(address token) public view returns (bool) {
        return (token == rewardToken() || token == underlying());
    }

    function addRewardToken(address _token) public onlyGovernance {
        rewardTokens.push(_token);
    }

    function _liquidateReward() internal {
        if (!sell()) {
            // Profits can be disabled for possible simplified and rapid exit
            emit ProfitsNotCollected(sell(), false);
            return;
        }

        address _universalLiquidator = universalLiquidator();
        address _rewardToken = rewardToken();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 rewardBalance = IERC20(token).balanceOf(address(this));

            if (rewardBalance == 0) {
                continue;
            }

            if (token != _rewardToken) {
                IERC20(token).safeApprove(_universalLiquidator, 0);
                IERC20(token).safeApprove(_universalLiquidator, rewardBalance);
                IUniversalLiquidator(_universalLiquidator).swap(
                    token,
                    _rewardToken,
                    rewardBalance,
                    1,
                    address(this)
                );
            }
        }

        uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
        _notifyProfitInRewardToken(_rewardToken, rewardBalance);
        uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(
            address(this)
        );

        if (remainingRewardBalance == 0) {
            return;
        }

        address _depositToken = depositToken();

        if (_depositToken != _rewardToken) {
            IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
            IERC20(_rewardToken).safeApprove(
                _universalLiquidator,
                remainingRewardBalance
            );
            IUniversalLiquidator(_universalLiquidator).swap(
                _rewardToken,
                _depositToken,
                remainingRewardBalance,
                1,
                address(this)
            );
        }

        _makePendleLP();
    }

    function _makePendleLP() internal {
        address _depositToken = depositToken();
        address _syToken = syToken();
        uint256 depositBalance = IERC20(_depositToken).balanceOf(address(this));
        if (depositBalance == 0) {
            return;
        }
        IERC20(_depositToken).safeApprove(_syToken, 0);
        IERC20(_depositToken).safeApprove(_syToken, depositBalance);
        ISYToken(_syToken).deposit(address(this), _depositToken, depositBalance, 1);
        uint256 syBalance = IERC20(_syToken).balanceOf(address(this));

        LimitOrderData memory limitData;
        ApproxParams memory approxParams;
        approxParams.guessMax = syBalance.mul(10);
        approxParams.maxIteration = 100;
        approxParams.eps = 1e15;

        IERC20(_syToken).safeApprove(pendleRouter, 0);
        IERC20(_syToken).safeApprove(pendleRouter, syBalance);
        IPendleRouter(pendleRouter).addLiquiditySingleSy(address(this), underlying(), syBalance, 0, approxParams, limitData);
    }

    function _claimRewards() internal {
        IPendleStaking(pendleStaking).harvestMarketReward(underlying(), address(this), 0);
        address[] memory _tokens = new address[](1);
        _tokens[0] = underlying();
        IMasterPenpie(rewardPool()).multiclaim(_tokens);
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawAllToVault() public restricted {
        _exitRewardPool();
        _claimRewards();
        _liquidateReward();
        address underlying_ = underlying();
        IERC20(underlying_).safeTransfer(vault(), IERC20(underlying_).balanceOf(address(this)));
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawToVault(uint256 _amount) public restricted {
        // Typically there wouldn't be any amount here
        // however, it is possible because of the emergencyExit
        address underlying_ = underlying();
        uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));

        if(_amount > entireBalance){
            // While we have the check above, we still using SafeMath below
            // for the peace of mind (in case something gets changed in between)
            uint256 needToWithdraw = _amount.sub(entireBalance);
            uint256 toWithdraw = Math.min(_rewardPoolBalance(), needToWithdraw);
            _withdrawUnderlyingFromPool(toWithdraw);
        }
        IERC20(underlying_).safeTransfer(vault(), _amount);
    }

    /*
     *   Note that we currently do not have a mechanism here to include the
     *   amount of reward that is accrued.
     */
    function investedUnderlyingBalance() external view returns (uint256) {
        if (rewardPool() == address(0)) {
            return IERC20(underlying()).balanceOf(address(this));
        }
        // Adding the amount locked in the reward pool and the amount that is somehow in this contract
        // both are in the units of "underlying"
        // The second part is needed because there is the emergency exit mechanism
        // which would break the assumption that all the funds are always inside of the reward pool
        return _rewardPoolBalance().add(IERC20(underlying()).balanceOf(address(this)));
    }

    /*
     *   Governance or Controller can claim coins that are somehow transferred into the contract
     *   Note that they cannot come in take away coins that are used and defined in the strategy itself
     */
    function salvage(
        address recipient,
        address token,
        uint256 amount
    ) external onlyControllerOrGovernance {
        // To make sure that governance cannot come in and take away the coins
        require(
            !unsalvagableTokens(token),
            "token is defined as not salvagable"
        );
        IERC20(token).safeTransfer(recipient, amount);
    }

    /*
     *   Get the reward, sell it in exchange for underlying, invest what you got.
     *   It's not much, but it's honest work.
     *
     *   Note that although `onlyNotPausedInvesting` is not added here,
     *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
     *   when the investing is being paused by governance.
     */
    function doHardWork() external onlyNotPausedInvesting restricted {
        _claimRewards();
        _liquidateReward();
        _investAllUnderlying();
    }

    /**
     * Can completely disable claiming UNI rewards and selling. Good for emergency withdraw in the
     * simplest possible way.
     */
    function setSell(bool s) public onlyGovernance {
        _setSell(s);
    }

    function _setDepositToken(address _address) internal {
        setAddress(_DEPOSIT_TOKEN_SLOT, _address);
    }

    function depositToken() public view returns (address) {
        return getAddress(_DEPOSIT_TOKEN_SLOT);
    }

    function _setSyToken(address _address) internal {
        setAddress(_SY_TOKEN_SLOT, _address);
    }

    function syToken() public view returns (address) {
        return getAddress(_SY_TOKEN_SLOT);
    }

    function finalizeUpgrade() external onlyGovernance {
        _finalizeUpgrade();
    }

    receive() external payable {}

    function wrapETH() external onlyGovernance {
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).deposit{value: address(this).balance}();
    }
}

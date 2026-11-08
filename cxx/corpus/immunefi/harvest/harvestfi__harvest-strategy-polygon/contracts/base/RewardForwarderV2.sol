// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./inheritance/Governable.sol";
import "./interface/IControllerV2.sol";
import "./interface/IRewardForwarder.sol";
import "./interface/IProfitSharingReceiver.sol";
import "./interface/IStrategy.sol";
import "./interface/IUniversalLiquidator.sol";
import "./inheritance/Controllable.sol";

/**
 * @dev This contract receives rewards from strategies and is responsible for routing the reward's liquidation into
 *      specific buyback tokens and profit tokens for the DAO.
 */
contract RewardForwarderV2 is Controllable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant iFARM = address(0xab0b2ddB9C7e440fAc8E140A89c0dbCBf2d7Bbff);

    constructor(
        address _storage
    ) public Controllable(_storage) {}

    function notifyFee(
        address _token,
        uint256 _profitSharingFee,
        uint256 _strategistFee,
        uint256 _platformFee
    ) external {
        _notifyFee(
            _token,
            _profitSharingFee,
            _strategistFee,
            _platformFee
        );
    }

    function _notifyFee(
        address _token,
        uint256 _profitSharingFee,
        uint256 _strategistFee,
        uint256 _platformFee
    ) internal {
        address _controller = controller();
        address liquidator = IControllerV2(_controller).universalLiquidator();

        uint totalTransferAmount = _profitSharingFee.add(_strategistFee).add(_platformFee);
        require(totalTransferAmount > 0, "totalTransferAmount should not be 0");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), totalTransferAmount);

        address _targetToken = IControllerV2(_controller).targetToken();

        if (_token != _targetToken) {
            IERC20(_token).safeApprove(liquidator, 0);
            IERC20(_token).safeApprove(liquidator, _platformFee);

            uint amountOutMin = 1;

            if (_platformFee > 0) {
                IUniversalLiquidator(liquidator).swap(
                    _token,
                    _targetToken,
                    _platformFee,
                    amountOutMin,
                    IControllerV2(_controller).protocolFeeReceiver()
                );
            }
        } else {
            IERC20(_targetToken).safeTransfer(IControllerV2(_controller).protocolFeeReceiver(), _platformFee);
        }

        if (_token != iFARM) {
            IERC20(_token).safeApprove(liquidator, 0);
            IERC20(_token).safeApprove(liquidator, _profitSharingFee.add(_strategistFee));

            uint amountOutMin = 1;

            if (_profitSharingFee > 0) {
                IUniversalLiquidator(liquidator).swap(
                    _token,
                    iFARM,
                    _profitSharingFee,
                    amountOutMin,
                    IControllerV2(_controller).profitSharingReceiver()
                );
            }
            if (_strategistFee > 0) {
                IUniversalLiquidator(liquidator).swap(
                    _token,
                    iFARM,
                    _strategistFee,
                    amountOutMin,
                    IStrategy(msg.sender).strategist()
                );
            }
        } else {
            if (_strategistFee > 0) {
                IERC20(iFARM).safeTransfer(IStrategy(msg.sender).strategist(), _strategistFee);
            }
            IERC20(iFARM).safeTransfer(IControllerV2(_controller).profitSharingReceiver(), _profitSharingFee);
        }
    }
}
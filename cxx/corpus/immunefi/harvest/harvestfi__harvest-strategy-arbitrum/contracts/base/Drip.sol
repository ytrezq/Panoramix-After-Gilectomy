// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./inheritance/Controllable.sol";
import "./interface/IERC4626.sol";

contract Drip is Controllable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event DripAdded(DripMode mode, address vault, uint256 perSecond);
    event DripRemoved(DripMode mode, address vault, uint256 perSecond);
    event Dripped(address vault, uint256 amount);

    enum DripMode { TokenAmount, FixedRate}

    struct DripInfo {
        DripMode mode;
        address vault;
        uint256 perSecond;
        uint256 lastDripTime;
    }

    DripInfo[] public drips;

    constructor(address _storage) Controllable(_storage) {}

    function addDrip(DripMode _mode, address _vault, uint256 _perSecond) public onlyGovernance {
        drips.push(DripInfo({
            mode: _mode,
            vault: _vault,
            perSecond: _perSecond,
            lastDripTime: block.timestamp
        }));
        emit DripAdded(_mode, _vault, _perSecond);
    }

    function removeDrip(uint256 _dripIndex) public onlyGovernance {
        require(_dripIndex < drips.length, "Invalid index");
        emit DripRemoved(drips[_dripIndex].mode, drips[_dripIndex].vault, drips[_dripIndex].perSecond);
        drips[_dripIndex] = drips[drips.length - 1];
        drips.pop();
    }

    function drip(uint256 _dripIndex) public {
        require(_dripIndex < drips.length, "Invalid index");
        DripInfo storage dripInfo = drips[_dripIndex];
        uint256 timePassed = block.timestamp.sub(dripInfo.lastDripTime);
        if (timePassed > 0) {
            address token = IERC4626(dripInfo.vault).asset();
            uint256 amount;
            if (dripInfo.mode == DripMode.TokenAmount) {
                amount = dripInfo.perSecond.mul(timePassed);
            } else if (dripInfo.mode == DripMode.FixedRate) {
                uint256 totalAssets = IERC4626(dripInfo.vault).totalAssets();
                uint256 rate = dripInfo.perSecond.mul(timePassed);
                amount = totalAssets.mul(rate).div(1e18);
            } else {
                revert("Invalid drip mode");
            }
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (Math.min(amount, balance) > 0) {
                dripInfo.lastDripTime = block.timestamp;
                IERC20(token).safeTransfer(dripInfo.vault, Math.min(amount, balance));
                emit Dripped(dripInfo.vault, Math.min(amount, balance));
            }
        }
    }

    function dripAll() public {
        for (uint256 i = 0; i < drips.length; i++) {
            drip(i);
        }
    }

    function salvage(address _token, uint256 _amount) public onlyGovernance {
        IERC20(_token).safeTransfer(governance(), _amount);
    }
}

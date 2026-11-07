// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IRestrictedToken.sol";
import "./interfaces/IRewardTracker.sol";
import "./Vester.sol";

/// @title VesterNoReserve contract
/// @author Simon Mall
/// @notice Vest esGSb tokens to claim GS tokens
/// @notice Vesting is done linearly over an year
/// @dev No need for pair tokens
contract VesterNoReserve is ReentrancyGuard, Ownable2Step, Initializable, Vester {
    using SafeERC20 for IERC20;

    constructor() {
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
        pairToken = address(0);
        claimableToken = _claimableToken;

        rewardTracker = _rewardTracker;

        if (rewardTracker != address(0)) {
            hasMaxVestableAmount = true;
        }
    }

    /// @inheritdoc Vester
    function hasPairToken() public override virtual view returns (bool) {
        return false;
    }

    /// @inheritdoc IVester
    function getPairAmount(address _account, uint256 _esAmount) public override virtual view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IVester
    function getAverageStakedAmount(address) public override virtual pure returns (uint256) {
        return 0;
    }
}

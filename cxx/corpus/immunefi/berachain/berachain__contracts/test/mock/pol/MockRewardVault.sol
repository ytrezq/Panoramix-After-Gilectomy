// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { StakingRewards } from "src/base/StakingRewards.sol";

/// @title Rewards Vault Mock
/// @author Berachain Team
contract MockRewardVault is StakingRewards {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Struct to hold delegate stake data.
    /// @param delegateTotalStaked The total amount staked by delegates.
    /// @param stakedByDelegate The mapping of the amount staked by each delegate.
    struct DelegateStake {
        uint256 delegateTotalStaked;
        mapping(address delegate => uint256 amount) stakedByDelegate;
    }

    /// @notice Struct to hold an incentive data.
    /// @param minIncentiveRate The minimum amount of the token to incentivize per BGT emission.
    /// @param incentiveRate The amount of the token to incentivize per BGT emission.
    /// @param amountRemaining The amount of the token remaining to incentivize.
    struct Incentive {
        uint256 minIncentiveRate;
        uint256 incentiveRate;
        uint256 amountRemaining;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The maximum count of incentive tokens that can be stored.
    uint8 public maxIncentiveTokensCount;

    /// @notice The address of the distributor contract.
    address public distributor;

    /// @notice The Berachef contract.
    IBeraChef public beraChef;

    mapping(address account => DelegateStake) internal _delegateStake;

    /// @notice The mapping of accounts to their operators.
    mapping(address account => address operator) internal _operators;

    /// @notice the mapping of incentive token to its incentive data.
    mapping(address token => Incentive incentives) public incentives;

    /// @notice The list of whitelisted tokens.
    address[] public whitelistedTokens;

    /// @notice variable added to test the upgradeability of the contract.
    uint256 public constant VERSION = 2;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _bgt, address _stakingToken) external initializer {
        __StakingRewards_init(_stakingToken, _bgt, 7 days);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice function to check if the contract is the new implementation.
    function isNewImplementation() external pure returns (bool) {
        return true;
    }
}
